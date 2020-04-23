package test;

using hx.strings.Strings;
import utest.Assert;

import haxe.ds.Option;

import test.HAssert;

import hiss.HaxeTools;
import hiss.HStream;

class HStreamTestCase extends utest.Test {

    var stream: HStream;

    function assertPos(line: Int, col: Int) {
        HAssert.objectEquals(new HPosition("test/expressions.hiss", line, col), stream.position());
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
        HAssert.objectEquals([0], stream.everyIndexOf("h"));
        HAssert.objectEquals([2, 3, 9], stream.everyIndexOf("l"));
        HAssert.objectEquals([3, 9], stream.everyIndexOf("l", 3));
    }

    public function testPeekLine() {
        stream.takeLine();
        HAssert.objectEquals(Some("  hello-world  "), stream.peekLine(''));
        HAssert.objectEquals(Some("hello-world  "), stream.peekLine('l'));
        HAssert.objectEquals(Some("hello-world"), stream.peekLine('lr'));
        HAssert.objectEquals(Some("  hello-world"), stream.peekLine('r'));
    }

    public function testDropWhitespace() {
        stream.takeLine();
        stream.dropWhitespace();
        HAssert.objectEquals(Some("hello-world  "), stream.peekLine('l'));
    }

    public function testTakeLine1() {
        stream.takeLine();
        HAssert.objectEquals(Some("  hello-world  "), stream.takeLine(''));
        assertPos(3, 1);
    }

    public function testTakeLine2() {
        stream.takeLine();
        HAssert.objectEquals(Some("hello-world  "), stream.takeLine('l'));
        assertPos(3, 1);
    }

    public function testTakeLine3() {
        stream.takeLine();
        HAssert.objectEquals(Some("  hello-world"), stream.takeLine('r'));
        assertPos(3, 1);
    }

    public function testTakeLine4() {
        stream.takeLine();
        HAssert.objectEquals(Some("hello-world"), stream.takeLine('rl'));
        assertPos(3, 1);
    }
}