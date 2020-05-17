package test;

using hx.strings.Strings;
import utest.Assert;

import hiss.HTypes;
import hiss.HissRepl;
import hiss.HissInterp;
import hiss.HissTools;

class HissTestCase extends utest.Test {

    var repl: HissRepl;
    var file: String;

    public function new(hissFile: String) {
        super();
        file = hissFile;
    }

    function testFile() {
        repl = new HissRepl();
        
        var results = repl.load(file, "(for statement '(*) (list statement (eval statement)))");
        for (v in results.toList()) {
            var expression = HissInterp.first(v);
            var value = HissInterp.nth(v, Atom(Int(1)));
            Assert.isTrue(HissInterp.truthy(value), 'Failure: ${HissTools.toPrint(expression)} evaluated to ${HissTools.toPrint(value)}');
        }

        for (fun => callCount in repl.interp.functionStats) {
            Assert.isTrue(callCount > 0, 'Failure: $fun was never called in testing');
        }
    }

}