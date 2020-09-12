package hiss;

import haxe.Timer;
import haxe.Log;
import haxe.PosInfos;
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

    static var functionsTested: Map<String, Bool> = [];
    var ignoreFunctions: Array<String> = [];
    var useTimeout: Bool;
    var expressions: HValue = null;

    static var printTestCommands: Bool = true; // Only enable this for debugging infinite loops and mysterious hangs

    public function new(hissFile: String, useTimeout: Bool = false, ?ignoreFunctions: Array<String>) {
        super();
        file = hissFile;

        this.useTimeout = useTimeout;

        reallyTrace = Log.trace;

        // Some functions just don't wanna be tested
        if (ignoreFunctions != null) this.ignoreFunctions = ignoreFunctions;
    }

    public static function testAtRuntime(interp: CCInterp, args: HValue, env: HValue, cc: Continuation) {
        var instance = new HissTestCase(null, false, null);
        instance.interp = interp;
        instance.expressions = args;
        utest.UTest.run([instance]);
        cc(Nil);
    }

    public static var reallyTrace: (Dynamic, ?PosInfos) -> Void = null;

    public static function hissTest(interp: CCInterp, args: HValue, env: HValue, cc: Continuation) {
        failOnTrace(interp);

        var functionsCoveredByUnit = switch (args.first()) {
            case Symbol(name): [name];
            case List(symbols): [for (symbol in symbols) symbol.symbolName()];
            default: throw 'Bad syntax for (test) statement';
        }

        if (printTestCommands) {
            reallyTrace(functionsCoveredByUnit);
        }

        var assertions = args.rest();

        var freshEnv = interp.emptyEnv();
        for (ass in assertions.toList()) {
            var failureMessage = 'Failure testing $functionsCoveredByUnit: ${ass.toPrint()} evaluated to: ';
            var errorMessage = 'Error testing $functionsCoveredByUnit: ${ass.toPrint()}: ';
            try {
                var val = interp.eval(ass, freshEnv);
                Assert.isTrue(val.truthy(), failureMessage + val.toPrint());
            }
            #if !throwErrors
            catch (err: Dynamic) {
                Assert.fail(errorMessage + err.toString());
            }
            #end
        }

        for (fun in functionsCoveredByUnit) {
            functionsTested[fun] = true;
        }

        enableTrace(interp);

        cc(Nil);
    }

    /**
        Function for asserting that a given expression prints what it's supposed to
    **/
    public static function hissPrints(interp: CCInterp, args: HValue, env: HValue, cc: Continuation) {
        var expectedPrint = interp.eval(args.first(), env).toHaxeString();
        var expression = args.second();

        var actualPrint = "";

        interp.importFunction((val: HValue) -> {
            actualPrint += val.toPrint() + "\n";
        }, "print", T);

        interp.importFunction((val: HValue) -> {
            actualPrint += val.toMessage() + "\n";
        }, "message", T);

        interp.eval(expression, env);
        interp.importFunction(hissPrintFail, "print", T);
        interp.importFunction(HissTools.message, "message", T); // It's ok to send messages from the standard library, just not to print raw HValues
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
    static function hissPrintFail(v: HValue) {
        if (!printTestCommands) {
            Assert.fail('Tried to print ${v.toPrint()} unnecessarily');
        }
        return v;
    }

    static var tempTrace = null;
    /**
        Make all forms of unnecessary printing into test failures :)
    **/
    static function failOnTrace(?interp: CCInterp) {
        tempTrace = Log.trace;
        
        // When running Hiss to throw errors, this whole situation gets untenable because `throw` relies on trace()
        #if !throwErrors
        Log.trace = (str, ?posInfo) -> {
            try {
                if (!printTestCommands) {
                    Assert.fail('Traced $str to console');
                }
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

    static function enableTrace(interp: CCInterp) {
        #if !throwErrors
        Log.trace = tempTrace;
        #end

        interp.importFunction(HissTools.print, "print", T);
    }

    function testWithoutTimeout() {
        if (!useTimeout) runTests();
        else Assert.pass();
    }

    @:timeout(10000)
    function testWithTimeout(async: Async) {
        if (useTimeout) {
            #if target.threaded
            Thread.create(runTests.bind(async));
            #else
            reallyTrace("Warning! On single-threaded target, an infinite loop will cause tests to hang.");
            runTests(async);
            #end
        }
        else { Assert.pass(); async.done(); };
    }

    function runTests(?async: Async) {
        if (file == null) {
            hissTest(interp, expressions, interp.emptyEnv(), CCInterp.noCC);
        } else {
            // Full-blown test run
            trace("Measuring time to construct the Hiss environment:");
            interp = Timer.measure(function () { 
                failOnTrace();
                var i = new CCInterp(hissPrintFail);
                enableTrace(i);
                return i;
            });

            // Get a list of BUILT-IN functions to make sure they're covered by tests.
            for (v => val in interp.globals.toDict()) {
                switch (val) {
                    case Function(_, _) | SpecialForm(_) | Macro(_):
                        if (!functionsTested.exists(v.symbolName())) functionsTested[v.symbolName()] = false;
                    default:
                }
            }
            // We don't want to be accountable for testing functions defined IN the tests.

            interp.globals.put("test", SpecialForm(hissTest.bind(interp), "test"));
            interp.globals.put("prints", SpecialForm(hissPrints.bind(interp), "prints"));

            for (f in ignoreFunctions) {
                functionsTested[f] = true;
            }

            trace("Measuring time taken to run the unit tests:");

            Timer.measure(function() {
                interp.load(file);
                trace("Total time to run tests:");
            });

            var functionsNotTested = [for (fun => tested in functionsTested) if (!tested) fun];

            if (functionsNotTested.length != 0) {
                #if sys
                Sys.print('Warning: $functionsNotTested were never tested');
                #end
            }

            if (async != null) {
                async.done();
            }
        }
    }
}