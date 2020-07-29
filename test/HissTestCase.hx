package test;

import haxe.Timer;
import haxe.Log;
#if target.threaded
import sys.thread.Thread;
#end

import utest.Test;
import utest.Async;
import utest.Assert;

import hiss.HTypes;
import hiss.CCInterp;
import hiss.HissTools;
import hiss.CompileInfo;
using hiss.HissTools;
import hiss.StaticFiles;
import hiss.HaxeTools;

class HissTestCase extends Test {

    var interp: CCInterp;
    var file: String;

    var functionsTested: Map<String, Bool> = [];
    var ignoreFunctions: Array<String> = [];
    var useTimeout: Bool;

    public function new(hissFile: String, useTimeout: Bool = false, ?ignoreFunctions: Array<String>) {
        super();
        file = hissFile;

        this.useTimeout = useTimeout;

        // Some functions just don't wanna be tested
        if (ignoreFunctions != null) this.ignoreFunctions = ignoreFunctions;
    }

    function hissTest(args: HValue, env: HValue, cc: Continuation) {
        failOnTrace(interp);

        var fun = args.first().symbolName();
        var assertions = args.rest();

        for (ass in assertions.toList()) {
            var failureMessage = 'Failure testing $fun: ${ass.toPrint()} evaluated to: ';
            var errorMessage = 'Error testing $fun: ${ass.toPrint()}: ';
            try {
                var val = interp.eval(ass, env);
                Assert.isTrue(val.truthy(), failureMessage + val.toPrint());
            }
            #if !throwErrors
            catch (err: Dynamic) {
                Assert.fail(errorMessage + err.toString());
            }
            #end
        }

        functionsTested[fun] = true;

        enableTrace(interp);

        cc(Nil);
    }

    /**
        Function for asserting that a given expression prints what it's supposed to
    **/
    function hissPrints(interp: CCInterp, args: HValue, env: HValue, cc: Continuation) {
        var expectedPrint = interp.eval(args.first(), env).toHaxeString();
        var expression = args.second();

        var actualPrint = "";

        interp.importFunction((val: HValue) -> {
            actualPrint += val.toPrint() + "\n";
        }, "print", T);

        interp.eval(expression, env);
        interp.importFunction(hissPrintFail, "print", T);
        cc(if (expectedPrint == actualPrint
                // Forgive a missing newline in the `prints` statement
                || (actualPrint.charAt(actualPrint.length-1) == '\n' && expectedPrint == actualPrint.substr(0, actualPrint.length-1))) {
            T;
        } else {
            trace('"$actualPrint" != "$expectedPrint"');
            Nil;
        });
    }

    /**
        Any unnecessary printing is a bug, so replace print() with this function while running tests.
    **/
    function hissPrintFail(v: HValue) {
        Assert.fail('Tried to print ${v.toPrint()} unnecessarily');
        return v;
    }

    var tempTrace = null;
    /**
        Make all forms of unnecessary printing into test failures :)
    **/
    function failOnTrace(?interp: CCInterp) {
        tempTrace = Log.trace;
        
        // When running Hiss to throw errors, this whole situation gets untenable because `throw` relies on trace()
        #if !throwErrors
        Log.trace = (str, ?posInfo) -> {
            try {
                Assert.fail('Traced $str to console');
            } catch (_: Dynamic) {
                // Because of asynchronous nonsense, this might be called out of context sometimes. When that happens,
                // assume that things were SUPPOSED to trace normally.
                tempTrace(str, posInfo);
            }
        };
        #end

        if (interp != null) {
            interp.importFunction(hissPrintFail, "print", T);
        }
    }

    function enableTrace(interp: CCInterp) {
        #if !throwErrors
        Log.trace = tempTrace;
        #end

        interp.importFunction(HissTools.print, "print", T);
    }

    function testWithoutTimeout() {
        if (!useTimeout) runTests();
        else Assert.pass();
    }

    @:timeout(5000)
    function testWithTimeout(async: Async) {
        if (useTimeout) {
            #if target.threaded
            Thread.create(runTests.bind(async));
            #else
            TestAll.reallyTrace("Warning! On single-threaded target, an infinite loop will cause tests to hang.");
            runTests(async);
            #end
        }
        else Assert.pass();
    }

    function runTests(?async: Async) {
        trace("Measuring time to construct the Hiss environment:");
        interp = Timer.measure(function () { 
            failOnTrace();
            var i = new CCInterp(hissPrintFail);
            enableTrace(i);
            return i;
        });

        interp.globals.put("test", SpecialForm(hissTest));
        interp.globals.put("prints", SpecialForm(hissPrints.bind(interp)));

        for (f in ignoreFunctions) {
            functionsTested[f] = true;
        }

        trace("Measuring time taken to run the unit tests:");

        Timer.measure(function() {
            interp.load(file);
            trace("Total time to run tests:");
        });

        for (v => val in interp.globals.toDict()) {
            switch (val) {
                case Function(_, _) | SpecialForm(_) | Macro(_):
                    if (!functionsTested.exists(v)) functionsTested[v] = false;
                default:
            }
        }

        for (fun => tested in functionsTested) {
            Assert.isTrue(tested, 'Failure: $fun was never tested');
        }

        if (async != null) {
            async.done();
        }
    }

}