package test;

using hx.strings.Strings;
import utest.Assert;

import HTypes;
import HissInterp;

class HissTestCase extends utest.Test {

    var repl: HissRepl;
    var file: String;

    public function new(hissFile: String) {
        super();
        file = hissFile;
    }

    function testFile() {
        repl = new HissRepl();
        
        var results = repl.load(file, "(for statement '(*) (eval statement))");
        for (v in results.toList()) {
            Assert.isTrue(HissInterp.truthy(v));
        }
    }

}