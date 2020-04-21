package;

import haxe.CallStack;

import HissReader;
import HissInterp;
import HTypes;

using HissTools;

class HissRepl {
	var interp: HissInterp;
	var reader: HissReader;

	public function new() {
		// TODO it's weird that all of these parts are necessary in this order to get a working hiss environment, and once we have it, it's actually static.
		interp = new HissInterp();
		var reader = new HissReader(interp);
		interp.load(Atom(String('src/stdlib.hiss')));
	}

	public function read(hiss: String): HValue {
		return HissReader.read(Atom(String(hiss+ "\n")));
	}

	public function eval(hiss: String): HValue {
		var hval = interp.eval(read(hiss));
		
		return hval;
	}

	public function load(file: String, wrappedIn: String) {
		return interp.load(Atom(String(file)), Atom(String(wrappedIn)));
	}

	public function repl(hiss: String) {
		Sys.println(eval(hiss).toPrint());
	}

 	public function run() {
		interp.variables.toDict()['__running__'] = T;
		interp.variables.toDict()['quit'] = Function(Haxe(Fixed, () -> { interp.variables.toDict()['__running__' ] = Nil; Sys.exit(0);}, "quit"));

		while (interp.variables.toDict()['__running__'].truthy()) {
	 		Sys.print(">>> ");
	 		var input = Sys.stdin().readLine();
			try {
				var parsed = HissReader.read(Atom(String(input+ "\n")));
				//trace(parsed);
				var hval = interp.eval(parsed);
				
				Sys.println(hval.toPrint());
			} catch (e: Dynamic) {
				Sys.println('error $e');
				// Sys.println(CallStack.exceptionStack());
			}
		}
 	}
}