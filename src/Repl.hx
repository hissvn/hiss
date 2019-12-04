package;

import HissParser;
import HissInterp;

class Repl {
 	public static function run() {
		var interp = new HissInterp();
		interp.variables['__running__'] = true;
		interp.variables['quit'] = () -> interp.variables['__running__'] = false;
		while (interp.variables['__running__']) {
	 		Sys.print(">>> ");
	 		var input = Sys.stdin().readLine();
			var parsed = HissParser.read(input);
			try {
				Sys.println(interp.eval(parsed));
			} catch (e: String) {
				Sys.println('error $e');
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