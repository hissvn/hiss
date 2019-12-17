package test;

using hx.strings.Strings;
import utest.Assert;

import HTypes;
import HissInterp;

class HissTestCase extends utest.Test {

    var interp: HissInterp;
    var file: String;

    public function new(hissFile: String) {
        super();
        file = hissFile;
    }

    function testFile() {
        interp = new HissInterp();
        
        var results = interp.load(Atom(String(file)), "(for statement '(*) (eval statement))").toList();
        for (v in results) {
            Assert.isTrue(HissInterp.truthy(v));
        }
    }

}