package test;

import hiss.CCInterp;
import utest.Assert;

class NativeFunctionTestCase extends utest.Test {
    var interp:CCInterp;

    public function setup() {
        interp = new CCInterp();
    }

    function getGlobal(name:String) {
        return interp.eval(interp.read(name));
    }

    public function testCallNativeGroups() {
        var groups = interp.toNativeFunction(getGlobal("groups"));

        Assert.equals(2, groups([1, 2, 3, 4, 5], 2, false).length);
        Assert.equals(3, groups([1, 2, 3, 4, 5], 2, true).length);
    }
}
