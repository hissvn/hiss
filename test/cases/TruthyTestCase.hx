package test.cases;

import hiss.CCInterp;

using hiss.HissTools;

import utest.Assert;

class TruthyTestCase extends utest.Test {
    function evalString(s:String, interp:CCInterp):Dynamic {
        return interp.eval(interp.read(s)).value(interp);
    }

    public function testZeroTruthy() {
        var interp = new CCInterp();

        interp.truthy = (value) -> switch (value) {
            case Int(0): false;
            default: true;
        };

        // (Until this proves to be a bad idea)
        // Nil and T actually return different Haxe values when truthy changes:
        Assert.equals(true, evalString("nil", interp));
        Assert.equals(true, evalString("t", interp));

        // Other primitive values still convert normally, though:
        Assert.equals(0, evalString("0", interp));

        // But for logical purposes, we get the expected change:
        Assert.equals("good", evalString("(if 0 \"bad\" \"good\")", interp));
        Assert.equals(true, evalString("(not 0)", interp));
    }
}
