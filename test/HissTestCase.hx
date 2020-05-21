package test;

import haxe.Timer;

using hx.strings.Strings;
import utest.Assert;

import hiss.HTypes;
import hiss.HissRepl;
import hiss.HissInterp;
import hiss.HissReader;
import hiss.HissTools;
import hiss.StaticFiles;

class HissTestCase extends utest.Test {

    var repl: HissRepl;
    var file: String;

    public function new(hissFile: String) {
        super();
        file = hissFile;
    }

    function testFile() {
        trace("Measuring time to construct the Hiss environment:");
        repl = Timer.measure(function () { return new HissRepl(); });
        
        trace("Measuring time taken to read the unit tests:");
        var expressions = Timer.measure(function() { return HissReader.readAll(String(StaticFiles.getContent(file))); });

        trace("Measuring time taken to run the unit tests:");

        var num = expressions.toList().length;
        var count = 0;
        Timer.measure(function() {
            for (e in expressions.toList()) {
                trace('testing expression #$count: ${e.toPrint()}');
                Timer.measure(function () {
                    try {
                        var v = repl.interp.eval(e);
                        Assert.isTrue(HissTools.truthy(v), 'Failure: ${HissTools.toPrint(e)} evaluated to ${HissTools.toPrint(v)}');
                    } catch (s: Dynamic) {
                        trace('uncaught error $s from test expression ${HissTools.toPrint(e)}');
                    }
                });

                count++;
            }
            trace("Total time to run tests:");
        });

        for (fun => callCount in repl.interp.functionStats) {
            if (fun != "read-line" && fun != "test-std" && fun != "lp" && fun != "lstd" && fun != "compare-by-even-odd" && fun != "what")
                Assert.isTrue(callCount > 0, 'Failure: $fun was never called in testing');
        }
    }

}