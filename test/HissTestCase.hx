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
        HissInterp.importWrappedVoid(interp, Assert.isTrue);
        HissInterp.importWrappedVoid(interp, Assert.isFalse);

        interp.load(Atom(String(file)));
    }

}