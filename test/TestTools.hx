package test;

import utest.Assert;

class TestTools {
    public static function assertEquals(expected: Dynamic, v: Dynamic) {
        Assert.equals(Std.string(expected), Std.string(v));
    }
}