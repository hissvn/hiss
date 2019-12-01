package hiss;

import Expressions;

class Repl {
 public static function main() {
	trace("Hsssssss");
	print(HValue.Atom(HAtom.Nil));
	print(HValue.Cons(new HCons(HValue.Atom(HAtom.String("fuck")), HValue.Cons(new HCons(HValue.Atom(HAtom.String("me")), HValue.Atom(HAtom.Nil))))));
 }

 static function print(v: HValue) {
	trace(Std.string(v));
 }
}