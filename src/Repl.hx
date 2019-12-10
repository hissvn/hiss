package;

import haxe.CallStack;

import HissParser;
import HissInterp;
import HTypes;

using HissTools;

class Repl {
 	public static function run() {
		var interp = new HissInterp();
		interp.variables['__running__'] = T;
		interp.variables['quit'] = Function(Haxe(Fixed, () -> { interp.variables['__running__' ] = Nil; Sys.exit(0);}));
		while (interp.variables['__running__'].truthy()) {
	 		Sys.print(">>> ");
	 		var input = Sys.stdin().readLine();
			try {
				var parsed = HissParser.read(input+ "\n");
				var hval = interp.eval(parsed);
				
				Sys.println(hval.toPrint());
			} catch (e: Dynamic) {
				Sys.println('error $e');
				Sys.println(CallStack.exceptionStack());
			}
		}
 	}
}