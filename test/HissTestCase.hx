package test;

import haxe.Timer;

using hx.strings.Strings;
import utest.Assert;

import hiss.HTypes;
import hiss.CCInterp;
import hiss.HissTools;
using hiss.HissTools;
import hiss.StaticFiles;

class HissTestCase extends utest.Test {

    var interp: CCInterp;
    var file: String;

    var functionsTested: Map<String, Bool> = [];
    var ignoreFunctions: Array<String> = [];

    public function new(hissFile: String, ?ignoreFunctions: Array<String>) {
        super();
        file = hissFile;

        // Some functions just don't wanna be tested
        if (ignoreFunctions != null) this.ignoreFunctions = ignoreFunctions;
    }

    function hissTest(args: HValue, env: HValue, cc: Continuation) {
        var fun = args.first().symbolName();
        var assertions = args.rest();
        var env = List([Dict([])]);
        for (ass in assertions.toList()) {
            var failureMessage = 'Failure testing $fun: ${ass.toPrint()} evaluated to: ';
            var errorMessage = 'Error testing $fun: ${ass.toPrint()}: ';
            try {
                interp.eval(ass, env, (val) -> {
                    Assert.isTrue(val.truthy(), failureMessage + val.toPrint());
                });
            } catch (err: Dynamic) {
                Assert.fail(errorMessage + err.toString());
            }
        }
        
        functionsTested[fun] = true;
    }

    /**
        Function for asserting that a given expression prints what it's supposed to
    **/
    function hissPrints(interp: CCInterp, args: HValue, env: HValue, cc: Continuation) {
        var expectedPrint = "";
        interp.eval(args.first(), env, (_expectedPrint) -> { expectedPrint = _expectedPrint.toHaxeString(); });
        var expression = args.second();

        var actualPrint = "";
        var testEnv = env.extend(Dict(["print" => Function((innerArgs, innerEnv, innerCC) -> {
            actualPrint += innerArgs.first().toPrint() + "\n";
        }, "print")]));

        interp.eval(expression, testEnv, (result) -> {
            Assert.equals(expectedPrint, actualPrint);
        });
    }

    /**
        Any unnecessary printing is a bug, so replace print() with this function while running tests.
    **/
    function hissPrint(args: HValue, env: HValue, cc: Continuation) {
        Assert.fail('Tried to print ${args.first().toPrint()} unnecessarily');
    }

    var tempTrace = null;
    function failOnTrace() {
        // Make trace() a test failure :)
        tempTrace = haxe.Log.trace;
        haxe.Log.trace = (str, ?posInfo) -> {
            Assert.fail('Traced $str to console');
        };
    }

    function enableTrace() {
        haxe.Log.trace = tempTrace;
    }

    function testFile() {
        

        trace("Measuring time to construct the Hiss environment:");
        interp = Timer.measure(function () { 
            failOnTrace();
            var i = new CCInterp();
            enableTrace();
            return i;
        });

        interp.globals.put("test", SpecialForm(hissTest));
        interp.globals.put("prints", SpecialForm(hissPrints.bind(interp)));
        interp.globals.put("print", SpecialForm(hissPrint));

        for (f in ignoreFunctions) {
            functionsTested[f] = true;
        }

        trace("Measuring time taken to run the unit tests:");

        Timer.measure(function() {
            failOnTrace();
            interp.load(file);
            enableTrace();
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
    }

}