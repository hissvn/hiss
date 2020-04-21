package test;

using hx.strings.Strings;
import utest.Assert;

import haxe.ds.Option;

import test.TestTools;

import HaxeUtils;
import HStream;

class HStreamTestCase extends utest.Test {

    var stream: HStream;

    function assertPos(line: Int, col: Int) {
        TestTools.assertEquals(new HPosition("test/expressions.hiss", line, col), stream.position());
    }

    public function setup() {
        stream = HStream.FromFile("test/expressions.hiss");
    }

    public function testPeek() {
        Assert.equals("h", stream.peek(1));
        assertPos(1, 1);
        Assert.equals("he", stream.peek(2));
        assertPos(1, 1);
    }

    public function testTake() {
        Assert.equals("h", stream.take(1));
        assertPos(1, 2);
        Assert.equals("e", stream.take(1));
        assertPos(1, 3);
        Assert.equals("llo", stream.take(3));
        assertPos(1, 6);
    }

    public function testEveryIndexOf() {
        stream = stream.takeLineAsStream();
        TestTools.assertEquals([0], stream.everyIndexOf("h"));
        TestTools.assertEquals([2, 3, 9], stream.everyIndexOf("l"));
        TestTools.assertEquals([3, 9], stream.everyIndexOf("l", 3));
    }

    public function testPeekLine() {
        stream.takeLine();
        TestTools.assertEquals(Some("  hello-world  "), stream.peekLine(''));
        TestTools.assertEquals(Some("hello-world  "), stream.peekLine('l'));
        TestTools.assertEquals(Some("hello-world"), stream.peekLine('lr'));
        TestTools.assertEquals(Some("  hello-world"), stream.peekLine('r'));
    }

    public function testDropWhitespace() {
        stream.takeLine();
        stream.dropWhitespace();
        TestTools.assertEquals(Some("hello-world  "), stream.peekLine('l'));
    }

    public function testTakeLine1() {
        stream.takeLine();
        TestTools.assertEquals(Some("  hello-world  "), stream.takeLine(''));
        assertPos(3, 1);
    }

    public function testTakeLine2() {
        stream.takeLine();
        TestTools.assertEquals(Some("hello-world  "), stream.takeLine('l'));
        assertPos(3, 1);
    }

    public function testTakeLine3() {
        stream.takeLine();
        TestTools.assertEquals(Some("  hello-world"), stream.takeLine('r'));
        assertPos(3, 1);
    }

    public function testTakeLine4() {
        stream.takeLine();
        TestTools.assertEquals(Some("hello-world"), stream.takeLine('rl'));
        assertPos(3, 1);
    }
}