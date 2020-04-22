package hiss;

import haxe.CallStack;

import hiss.HissReader;
import hiss.HissInterp;
import hiss.HTypes;

using hiss.HissTools;

class HissRepl {
	public var interp: HissInterp;
	var reader: HissReader;

	public function new() {
		// TODO it's weird that all of these parts are necessary in this order to get a working hiss environment, and once we have it, it's actually static.
		interp = new HissInterp();
		var reader = new HissReader(interp);
		interp.load(Atom(String('src/hiss/stdlib.hiss')));
	}

	public function read(hiss: String): HValue {
		return HissReader.read(Atom(String(hiss+ "\n")));
	}

	public function eval(hiss: String): HValue {
		var hval = interp.eval(read(hiss));
		
		return hval;
	}

	public function load(file: String, wrappedIn: String = '(progn * t)') {
		return interp.load(Atom(String(file)), Atom(String(wrappedIn)));
	}

	public function repl(hiss: String) {
		HaxeUtils.println(eval(hiss).toPrint());
	}

 	public function run() {
		#if !sys
		throw 'Cannot run a repl on a non-system platform';
		#end

		interp.variables.toDict()['__running__'] = T;
		interp.variables.toDict()['quit'] = Function(Haxe(Fixed, () -> {
			interp.variables.toDict()['__running__' ] = Nil;
			#if sys
			Sys.exit(0);
			#end
		}, "quit"));

		while (interp.variables.toDict()['__running__'].truthy()) {
	 		HaxeUtils.print(">>> ");
			var input = "";
			#if sys
				input = Sys.stdin().readLine();
			#end
			try {
				var parsed = HissReader.read(Atom(String(input+ "\n")));
				//trace(parsed);
				var hval = interp.eval(parsed);
				
				HaxeUtils.println(hval.toPrint());
			} catch (e: Dynamic) {
				HaxeUtils.println('error $e');
				// Sys.println(CallStack.exceptionStack());
			}
		}
 	}
}