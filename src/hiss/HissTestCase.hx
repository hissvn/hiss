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

    static var printTestCommands:Bool = true; // Only enable this for debugging infinite loops and mysterious hangs

    public function new(hissFile:String, ?ignoreFunctions:Array<String>) {
        super();
        file = hissFile;

        reallyTrace = Log.trace;

        // Some functions just don't wanna be tested
        if (ignoreFunctions != null)
            this.ignoreFunctions = ignoreFunctions;
    }

    public static function testAtRuntime(interp:CCInterp, args:HValue, env:HValue, cc:Continuation) {
        var instance = new HissTestCase(null, null);
        instance.interp = interp;
        instance.expressions = args;
        var runner = new utest.Runner();
        runner.addCase(instance);
        new NoExitReport(runner);
        runner.run();
        cc(Nil);
    }

    public static var reallyTrace:(Dynamic, ?PosInfos) -> Void = null;

    public static function hissTest(interp:CCInterp, args:HValue, env:HValue, cc:Continuation) {
        failOnTrace(interp);

        var functionsCoveredByUnit = switch (args.first()) {
            case Symbol(name): [name];
            case List(symbols): [for (symbol in symbols) symbol.symbolName_h()];
            default: throw 'Bad syntax for (test) statement';
        }

        if (printTestCommands) {
            #if (sys || hxnodejs)
            Sys.println(functionsCoveredByUnit.toString());
            #else
            tempTrace(functionsCoveredByUnit.toString(), null);
            #end
        }

        var assertions = args.rest_h();

        var freshEnv = interp.emptyEnv();
        for (ass in assertions.toList()) {
            var failureMessage = 'Failure testing $functionsCoveredByUnit: ${ass.toPrint()} evaluated to: ';
            var errorMessage = 'Error testing $functionsCoveredByUnit: ${ass.toPrint()}: ';
            try {
                var val = interp.eval(ass, freshEnv);
                Assert.isTrue(interp.truthy(val), failureMessage + val.toPrint());
            }
            #if !throwErrors
            catch (err:Dynamic) {
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
    static function hissPrintFail(v:HValue) {
        if (!printTestCommands) {
            Assert.fail('Tried to print ${v.toPrint()} unnecessarily');
        } else {
            #if (sys || hxnodejs)
            Sys.println(v.toPrint());
            #else
            tempTrace(v.toPrint(), null);
            #end
        }
        return v;
    }

    static var tempTrace:(Dynamic, ?PosInfos) -> Void = null;

    /**
        Make all forms of unnecessary printing into test failures :)
    **/
    static function failOnTrace(?interp:CCInterp) {
        tempTrace = Log.trace;

        // When running Hiss to throw errors, this whole situation gets untenable because `throw` relies on trace()
        #if !throwErrors
        Log.trace = (str, ?posInfo) -> {
            try {
                if (!printTestCommands) {
                    Assert.fail('Traced $str to console');
                } else {
                    tempTrace(str, posInfo);
                }
            } catch (_:Dynamic) {
                // Because of asynchronous nonsense, this might be called out of context sometimes. When that happens,
                // assume that things were SUPPOSED to trace normally.
                tempTrace(str, posInfo);
            }
        };
        #end

        if (interp != null) {
            interp.importFunction(HissTestCase, hissPrintFail, {name: "print"}, T); // TODO make it deprecated
            interp.importFunction(HissTestCase, hissPrintFail, {name: "print!"}, T);
        }
    }

    static function enableTrace(interp:CCInterp) {
        #if !throwErrors
        Log.trace = tempTrace;
        #end

        interp.importFunction(HissTools, Stdlib.print_hd, {name: "print"}, T); // TODO make it deprecated
        interp.importFunction(HissTools, Stdlib.print_hd, {name: "print!"}, T);
    }

    function testStdlib() {
        if (file == null) {
            hissTest(interp, expressions, interp.emptyEnv(), CCInterp.noCC);
        } else {
            // Full-blown test run
            trace("Measuring time to construct the Hiss environment:");
            interp = Timer.measure(function() {
                failOnTrace();
                var i = new CCInterp(hissPrintFail);
                enableTrace(i);
                return i;
            });

            // Get a list of BUILT-IN functions to make sure they're covered by tests.
            for (v => val in interp.globals.toDict()) {
                switch (val) {
                    case Function(_, _) | SpecialForm(_) | Macro(_):
                        if (!functionsTested.exists(v.symbolName_h()))
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
        }
    }
}
