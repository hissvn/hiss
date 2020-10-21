package test;

import hiss.HTypes;
import test.HAssert;
import hiss.HissRepl;

class HissReaderTestCase extends utest.Test {
    var repl:HissRepl;

    function assertRead(v:HValue, s:String) {
        HAssert.hvalEquals(v, repl.read(s));
    }

    function assertReadList(v:HValue, s:String) {
        var actual = repl.read(s).toList();
        var i = 0;
        for (lv in v.toList()) {
            HAssert.hvalEquals(lv, actual[i++]);
        }
    }

    public function setup() {
        repl = new HissRepl();
    }

    public function testReadSymbol() {
        assertRead(Symbol("hello-world"), "hello-world");
        assertRead(Symbol("hello-world!"), "hello-world!");
    }

    public function testReadBlockComment() {
        assertRead(Symbol("fork"), "/* foo */ fork");
        assertRead(Symbol("fork"), "/* foo */fork");

        assertRead(Symbol("fork"), "fork /* fu\nk */");
        assertRead(Symbol("fork"), "fork/* fu\nk */");

        assertRead(List([Symbol("fo"), Symbol("rk")]), "(fo /*fuuuuu*/ rk)");
        assertRead(List([Symbol("fo"), Symbol("rk")]), "(fo/*fuuuuu*/rk)");
    }

    public function testReadLineComment() {
        assertRead(Symbol("fork"), "fork // foo\n");
        assertRead(Symbol("fork"), "fork// foo\n");
        assertRead(Symbol("fork"), "// foo \nfork");
    }

    public function testReadString() {
        assertRead(String("foo"), '"foo"');
        assertRead(String("foo  "), '"foo  "');
    }

    public function testReadSymbolOrSign() {
        assertRead(Symbol("-"), "-");
        assertRead(Symbol("+"), "+");
    }

    public function testReadNumbers() {
        assertRead(Int(5), "+5");
        assertRead(Int(-5), "-5");
        assertRead(Float(0), "0.");
        assertRead(Float(-5), "-5.");
        assertRead(Int(5), "5");
    }

    public function testReadList() {
        // Single-element lists
        assertRead(List([Symbol("-")]), "(-)");
        assertRead(List([Symbol("fork")]), "(fork)");

        var list = List([String("foo"), Int(5), Symbol("fork"),]);

        assertRead(list, '("foo" 5 fork)');
        assertRead(list, '  ( "foo" 5 fork )');

        var nestedList = List([String("foo"), Int(5), list, Symbol("fork"),]);

        assertReadList(nestedList, '("foo" 5 ("foo" 5 fork) fork)');
        assertReadList(nestedList, '("foo" 5 (  "foo" 5 fork )   fork)');
    }

    public function testReadQuotes() {
        // trace("TESTING QUOTES");
        assertRead(Quote(Symbol("fork")), "'fork");
        assertRead(Quasiquote(Symbol("fork")), "`fork");
        assertRead(Unquote(Symbol("fork")), ",fork");
        assertRead(Quote(List([Symbol("fork"), String("hello")])), "'(fork \"hello\")");
        assertRead(Quasiquote(List([Unquote(Symbol("fork")), String("hello")])), "`(,fork \"hello\")");
        assertRead(Quasiquote(List([Unquote(List([Symbol("fork"), Symbol("you")])), String("hello")])), "`(,(fork you) \"hello\")");
        assertRead(Quasiquote(List([UnquoteList(Symbol("fork")), String("hello")])), "`(,@fork \"hello\")");
        assertRead(Quasiquote(List([UnquoteList(List([Symbol("fork"), Symbol("you")])), String("hello")])), "`(,@(fork you) \"hello\")");
        // trace("DONE TESTING QUOTES");
    }

    public function testStringEscapeSequences() {
        assertRead(String("\n"), '"\n"');
    }
}
