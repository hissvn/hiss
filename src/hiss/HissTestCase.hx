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

import hiss.Stdlib;

using hiss.Stdlib;

import hiss.StaticFiles;
import hiss.HaxeTools;

using StringTools;

// Source: https://github.com/haxe-utest/utest/issues/105#issuecomment-687710047
// and PlainTextReport.hx
class NoExitReport extends utest.ui.text.PrintReport {
    override function complete(result:utest.ui.common.PackageResult) {
        this.result = result;
        if (handler != null)
            handler(this);
        if (!result.stats.isOk) {
            #if (php || neko || cpp || cs || java || python || lua || eval || hl)
            Sys.exit(1);
            #elseif js
            if (#if (haxe_ver >= 4.0) js.Syntax.code #else untyped __js__ #end ('typeof phantom != "undefined"'))
                #if (haxe_ver >= 4.0) js.Syntax.code #else untyped __js__ #end ('phantom').exit(1);
            if (#if (haxe_ver >= 4.0) js.Syntax.code #else untyped __js__ #end ('typeof process != "undefined"'))
                #if (haxe_ver >= 4.0) js.Syntax.code #else untyped __js__ #end ('process').exit(1);
            #elseif (flash && exit)
            if (flash.system.Security.sandboxType == "localTrusted") {
                var delay = 5;
                trace('all done, exiting in $delay seconds');
                haxe.Timer.delay(function() try {
                    flash.system.System.exit(1);
                } catch (e:Dynamic) {
                    // do nothing
                }, delay * 1000);
            }
            #end
        }
    }
}

class HissTestCase extends Test {
    var interp:CCInterp;
    var file:String;

    static var functionsTested:Map<String, Bool> = [];

    var ignoreFunctions:Array<String> = [];
    var expressions:HValue = null;
    var requireCoverage:Bool;

    public function new(hissFile:String, requireCoverage = false) {
        super();
        file = hissFile;
        this.requireCoverage = requireCoverage;

        trace("Measuring time to construct the Hiss environment:");
        interp = Timer.measure(function() {
            failOnTrace();
            var i = new CCInterp(hissPrintFail);
            enableTrace(i);
            return i;
        });
    }

    public static function testAtRuntime(interp:CCInterp, args:HValue, env:HValue, cc:Continuation) {
        var instance = new HissTestCase(null);
        instance.interp = interp;
        instance.expressions = args;
        var runner = new utest.Runner();
        runner.addCase(instance);
        new NoExitReport(runner);
        runner.run();
        cc(Nil);
    }

    static var traceCalled = false;

    public static function reallyTrace(s:Dynamic) {
        var wasTraceCalled = traceCalled;
        trace(s);
        traceCalled = wasTraceCalled;
    }

    public static function hissTest(interp:CCInterp, args:HValue, env:HValue, cc:Continuation) {
        failOnTrace(interp);

        var functionsCoveredByUnit = switch (args.first()) {
            case Symbol(name): [name];
            case List(symbols): [for (symbol in symbols) symbol.symbolName_h()];
            case String(_) | InterpString(_): [];
            default: throw 'Bad syntax for (test) statement';
        }

        var testDescription:String = if (functionsCoveredByUnit.length > 0) {
            functionsCoveredByUnit.toString();
        } else {
            args.first().toPrint_h();
        };

        interp.profile('testing $testDescription');

        var assertions = args.rest_h();

        var freshEnv = interp.emptyEnv();
        for (ass in assertions.toList()) {
            var failureMessage = 'Failure testing $functionsCoveredByUnit: ${ass.toPrint()} evaluated to: ';
            var errorMessage = 'Error testing $functionsCoveredByUnit: ${ass.toPrint()}: ';
            try {
                interp.evalCC(ass, (val) -> {
                    Assert.isTrue(interp.truthy(val), failureMessage + val.toPrint());
                }, freshEnv);
            }
            #if !throwErrors
            catch (err:Dynamic) {
                Assert.fail(errorMessage + err.toString());
            }
            #end
        }

        interp.profile();

        for (fun in functionsCoveredByUnit) {
            functionsTested[fun] = true;
        }

        Assert.isFalse(traceCalled, "trace was called");
        enableTrace(interp);

        cc(Nil);
    }

    /**
        Function for asserting that a given expression prints what it's supposed to
    **/
    public static function hissPrints(interp:CCInterp, args:HValue, env:HValue, cc:Continuation) {
        var expectedPrint = interp.eval(args.first(), env).toHaxeString();
        var expression = args.second();

        var actualPrint = "";

        interp.importFunction(HissTestCase, (val : HValue) -> {
            actualPrint += val.toPrint() + "\n";
        }, {name: "print"}, T); // TODO make it deprecated
        interp.importFunction(HissTestCase, (val : HValue) -> {
            actualPrint += val.toPrint() + "\n";
        }, {name: "print!"}, T);

        interp.importFunction(HissTestCase, (val : HValue) -> {
            actualPrint += val.toMessage() + "\n";
        }, {name: "message"}, T); // TODO make it deprecated
        interp.importFunction(HissTestCase, (val : HValue) -> {
            actualPrint += val.toMessage() + "\n";
        }, {name: "message!"}, T);

        interp.eval(expression, env);
        interp.importFunction(HissTestCase, hissPrintFail, {name: "print"}, T); // TODO make it deprecated
        interp.importFunction(HissTestCase, hissPrintFail, {name: "print!"}, T);

        interp.importFunction(HissTools, Stdlib.message_hd, {name: "message"}, T); // TODO make it deprecated
        interp.importFunction(HissTools, Stdlib.message_hd, {name: "message!"},
            T); // It's ok to send messages from the standard library, just not to print raw HValues
        cc(if (expectedPrint == actualPrint // Forgive a missing newline in the `prints` statement
            || (actualPrint.charAt(actualPrint.length - 1) == '\n' && expectedPrint == actualPrint.substr(0, actualPrint.length - 1))) {
            T;
        } else {
            trace('"$actualPrint" != "$expectedPrint"');
            Nil;
        });
    }

    /**
        Any unnecessary printing is a bug, so replace print() with this function while running tests.
    **/
    static function hissPrintFail(v:Dynamic) {
        traceCalled = true;
        return v;
    }

    static function printReplacement(v:Dynamic) {
        return Stdlib.print_hd(v.toHValue());
    }

    static var originalTrace = Log.trace;

    /**
        Make all forms of unnecessary printing into test failures :)
    **/
    static function failOnTrace(?interp:CCInterp) {
        traceCalled = false;

        Log.trace = (str, ?posInfo) -> {
            originalTrace(str, posInfo);
            traceCalled = true;
        };

        if (interp != null) {
            interp.importFunction(HissTestCase, hissPrintFail, {name: "print"}, T); // TODO make it deprecated
            interp.importFunction(HissTestCase, hissPrintFail, {name: "print!"}, T);
        }
    }

    static function enableTrace(interp:CCInterp) {
        #if !throwErrors
        Log.trace = originalTrace;
        #end

        interp.importFunction(HissTools, printReplacement, {name: "print"}, T); // TODO make it deprecated
        interp.importFunction(HissTools, printReplacement, {name: "print!"}, T);
    }

    function testStdlib() {
        if (file == null) {
            hissTest(interp, expressions, interp.emptyEnv(), CCInterp.noCC);
        } else {
            // Full-blown test run

            // Get a list of BUILT-IN functions to make sure they're covered by tests.
            for (v => val in interp.globals.toDict()) {
                switch (val) {
                    case Function(_, meta) | SpecialForm(_, meta) | Macro(_, meta):
                        if (!meta.deprecated && !functionsTested.exists(v.symbolName_h()))
                            functionsTested[v.symbolName_h()] = false;
                    default:
                }
            }
            // We don't want to be accountable for testing functions defined IN the tests.

            interp.globals.put("test!", SpecialForm(hissTest.bind(interp), {name: "test!"}));
            interp.defDestructiveAlias("test!", "!");
            interp.globals.put("prints", SpecialForm(hissPrints.bind(interp), {name: "prints"}));

            for (f in ignoreFunctions) {
                functionsTested[f] = true;
            }

            reallyTrace("Measuring time taken to run the unit tests:");

            Timer.measure(function() {
                interp.load(file);
                reallyTrace("Total time to run tests:");
            });

            var functionsNotTested = [for (fun => tested in functionsTested) if (!tested && !fun.startsWith("_")) fun];

            if (requireCoverage && functionsNotTested.length != 0) {
                Assert.fail('These functions were never tested: $functionsNotTested');
            }
        }
    }
}
