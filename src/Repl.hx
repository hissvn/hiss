package;

import haxe.CallStack;

import HissReader;
import HissInterp;
import HTypes;

using HissTools;

class Repl {
 	public static function run() {
		var interp = new HissInterp();
		interp.variables.toDict()['__running__'] = T;
		interp.variables.toDict()['quit'] = Function(Haxe(Fixed, () -> { interp.variables.toDict()['__running__' ] = Nil; Sys.exit(0);}, "quit"));
		while (interp.variables.toDict()['__running__'].truthy()) {
	 		Sys.print(">>> ");
	 		var input = Sys.stdin().readLine();
			try {
				var parsed = HissReader.read(Atom(String(input+ "\n")));
				var hval = interp.eval(parsed);
				
				Sys.println(hval.toPrint());
			} catch (e: Dynamic) {
				Sys.println('error $e');
				// Sys.println(CallStack.exceptionStack());
			}
		}
 	}
}