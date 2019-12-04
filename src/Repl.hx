package;

import HissParser;
import HissInterp;

class Repl {
 	public static function run() {
		var parser = new HissParser();
		var interp = new HissInterp();
		while (true) {
	 		Sys.print(">>> ");
	 		var input = Sys.stdin().readLine();
			var parsed = parser.parseString(input);
	 		if (parsed.status) {
				Sys.print(interp.eval(parsed.value));
				Sys.print('\n');
			} else {
				Sys.print("failed to parse");
			}
	 		Sys.print("\n");
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