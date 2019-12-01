package hiss;

import Expressions;
import Parser;

class Repl {
 public static function main() {
	var parser = new Parser();
	while (true) {
	 Sys.print(">>> ");
	 var input = Sys.stdin().readLine();
	 printValue(parser.parse(input));
	 Sys.print("\n");
	}
 }

 static function printValue(v: HValue) {
	switch (v) {
	 case Atom(a):
	  switch (a) {
		 case Nil:
		  Sys.print("nil");
		 case Int(value):
		  Sys.print(value);
		 case Double(value):
		  Sys.print(value);
		 case Symbol(name):
		  Sys.print(name);
		 case String(value):
		  Sys.print('"$value"');
		}
	 case Cons(c):
	  Sys.print("(");
	  printValue(c.first);
	  Sys.print(" . ");
	  printValue(c.rest);
	  Sys.print(")");
	 }
 }
}