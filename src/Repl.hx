package;

import haxe.CallStack;

import HissParser;
import HissInterp;
import HTypes;

class Repl {
 	public static function run() {
		var interp = new HissInterp();
		interp.variables['__running__'] = T;
		interp.variables['quit'] = Function(Haxe(Fixed, () -> { interp.variables['__running__'] = Nil; }));
		while (interp.variables['__running__'].truthy()) {
	 		Sys.print(">>> ");
	 		var input = Sys.stdin().readLine();
			try {
				var parsed = HissParser.read(input);
				Sys.println(interp.eval(parsed));
			} catch (e: Dynamic) {
				Sys.println('error $e');
				Sys.println(CallStack.exceptionStack());
			}
		}
 	}

	/*
 	static function printValue(v: HExpression) {
		switch (v) {
	 		case Atom(a):
	  			switch (a) {
		 			case Int(value):
		  				Sys.print(value);
		 			case Double(value):
		  				Sys.print(value);
		 			case Symbol(name):
		  				Sys.print(name);
		 			case String(value):
		  				Sys.print('"$value"');
				}
	 		case Cons(first, rest):
	  			Sys.print("(");
	  			printValue(first);
	  			Sys.print(" . ");
	  			printValue(rest);
	  			Sys.print(")");
			case List(a):
				Sys.print("(");
				for (exp in a) {
					printValue(exp);
					Sys.print(" ");
				}
				Sys.print(")");
		 }
 	}
	*/
}