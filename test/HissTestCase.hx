package test;

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
        repl = new HissRepl();
        
        var expressions = HissReader.readAll(Atom(String(StaticFiles.getContent(file))));
        for (e in expressions.toList()) {
            var v = repl.interp.eval(e);
            Assert.isTrue(HissInterp.truthy(v), 'Failure: ${HissTools.toPrint(e)} evaluated to ${HissTools.toPrint(v)}');
        }

        for (fun => callCount in repl.interp.functionStats) {
            if (fun != "test-std" && fun != "lp" && fun != "lstd" && fun != "compare-by-even-odd" && fun != "what")
                Assert.isTrue(callCount > 0, 'Failure: $fun was never called in testing');
        }
    }

}