package test;

import HTypes;
import test.TestTools;

class HissReaderTestCase extends utest.Test {
    
    var interp: HissInterp;
    var reader: HissReader;

    function assertRead(v: HValue, s: String) {
        TestTools.assertEquals(v, HissReader.read(Atom(String(s))));
    }

    function assertReadList(v: HValue, s: String) {
        var actual = HissReader.read(Atom(String(s))).toList();
        var i = 0;
        for (lv in v.toList()) {
            TestTools.assertEquals(lv, actual[i++]);
        }
    }


    public function setup() {
        var interp = new HissInterp();
        reader = new HissReader(interp); // Don't need to save it because it's static
    }

    public function testReadSymbol() {
        assertRead(Atom(Symbol("hello-world")), "hello-world");
        assertRead(Atom(Symbol("hello-world!")), "hello-world!");
    }

    public function testReadBlockComment() {
        assertRead(Atom(Symbol("fork")), "/* foo */ fork");
        assertRead(Atom(Symbol("fork")), "fork /* fu\nk */");
        assertRead(List([Atom(Symbol("fo")), Atom(Symbol("rk"))]), "(fo /*fuuuuu*/ rk)");
    }

    public function testReadLineComment() {
        assertRead(Atom(Symbol("fork")), "fork // foo\n");
        assertRead(Atom(Symbol("fork")), "// foo \nfork");
    }

    public function testReadString() {
        assertRead(Atom(String("foo")), '"foo"');
        assertRead(Atom(String("foo  ")), '"foo  "');
    }

    public function testReadSymbolOrSign() {
        assertRead(Atom(Symbol("-")), "-");
        assertRead(Atom(Symbol("+")), "+");
    }

    public function testReadNumbers() {
        assertRead(Atom(Int(5)), "+5");
        assertRead(Atom(Int(-5)), "-5");
        assertRead(Atom(Float(0)), "0.");
        assertRead(Atom(Float(-5)), "-5.");
        assertRead(Atom(Int(5)), "5");
    }

    public function testReadList() {
        var list = List([
            Atom(String("foo")),
            Atom(Int(5)),
            Atom(Symbol("fork")),
        ]);
        
        assertRead(list, '("foo" 5 fork)');
        assertRead(list, '  ( "foo" 5 fork )');

        var nestedList = List([
            Atom(String("foo")),
            Atom(Int(5)),
            list,
            Atom(Symbol("fork")),
        ]);
        
        assertReadList(nestedList, '("foo" 5 ("foo" 5 fork) fork)');
        assertReadList(nestedList, '("foo" 5 (  "foo" 5 fork )   fork)');
    }

    public function testReadQuotes() {
        assertRead(Quote(Atom(Symbol("fork"))), "'fork");
        assertRead(Quasiquote(Atom(Symbol("fork"))), "`fork");
        assertRead(Unquote(Atom(Symbol("fork"))), ",fork");
        assertRead(Quote(List([Atom(Symbol("fork")), Atom(String("hello"))])), "'(fork \"hello\")");
        assertRead(Quasiquote(List([Unquote(Atom(Symbol("fork"))), Atom(String("hello"))])), "`(,fork \"hello\")");
    }
}