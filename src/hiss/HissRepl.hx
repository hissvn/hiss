package hiss;

import hiss.HissReader;
import hiss.HissInterp;
import hiss.HTypes;
import hiss.StaticFiles;

using hiss.HissTools;

class HissRepl {
	public var interp: HissInterp;
	var reader: HissReader;

	public function new() {
		// TODO it's weird that all of these parts are necessary in this order to get a working hiss environment, and once we have it, it's actually static.
		interp = new HissInterp();
		var reader = new HissReader(interp);
		load("stdlib.hiss");
	}

	public function read(hiss: String): HValue {
		return HissReader.read(Atom(String(hiss+ "\n")));
	}

	public function readAll(hiss: String): HValue {
		return HissReader.readAll(Atom(String(hiss+"\n")));
	}

	public function eval(hiss: String): HValue {
		var hval = interp.eval(read(hiss));
		
		return hval;
	}

	public function load(file: String) {
		var list = [Atom(Symbol("progn"))];
		list = list.concat(HissReader.readAll(Atom(String(StaticFiles.getContent(file)))).toList());
		interp.eval(List(list));
	}

	public function repl(hiss: String) {
		HaxeTools.println(eval(hiss).toPrint());
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
	 		HaxeTools.print(">>> ");
			var input = "";
			#if sys
				input = Sys.stdin().readLine();
			#end
			try {
				var parsed = HissReader.read(Atom(String(input+ "\n")));
				//trace(parsed);
				var hval = interp.eval(parsed);
				
				HaxeTools.println(hval.toPrint());
			}
			#if !throwErrors
			catch (e: Dynamic) {
				HaxeTools.println('error $e');
				//Sys.println(CallStack.exceptionStack());
			}
			#end
		}
 	}
}