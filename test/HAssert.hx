package test;

import utest.Assert;
import Type;
import hiss.HTypes;
import hiss.HissInterp;

class HAssert {
    public static function objectEquals(expected: Dynamic, actual: Dynamic) {
        Assert.equals(Std.string(expected), Std.string(actual));
    }

    public static function hvalEquals(expected: HValue, actual: HValue) {
        //trace('Comparing $expected with $actual');
        Assert.isTrue(HissInterp.truthy(HissInterp.eq(expected, actual)), '$actual was supposed to equal $expected');
    }
}