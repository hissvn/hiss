package test;

import hiss.CCInterp;
import utest.Assert;

class NativeFunctionTestCase extends utest.Test {
    var interp: CCInterp;

    public function setup() {
        interp = new CCInterp();
    }

    function getGlobal(name: String) {
        return interp.eval(interp.read(name));
    }

    public function testCallNativePrint() {
        var print = interp.toNativeFunction1(getGlobal("print"));

        Assert.equals("stuff", print("stuff"));
    }

    public function testCallNativeNth() {
        var nth = interp.toNativeFunction2(getGlobal("nth"));

        var list = [1, 3, 5];
        Assert.equals(1, nth(list, 0));
        Assert.equals(3, nth(list, 1));
        Assert.equals(5, nth(list, 2));
    }
}