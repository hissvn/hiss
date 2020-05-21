package hiss;

import haxe.Timer;
import haxe.ds.ListSort;
import ihx.ConsoleReader;

import hiss.HissReader;
import hiss.HissInterp;
import hiss.HTypes;
import hiss.StaticFiles;

using hiss.HissTools;

class HissRepl {
	public var interp: HissInterp;

	public function new() {
		// TODO it's weird that all of these parts are necessary in this order to get a working hiss environment, and once we have it, it's actually static.
		interp = new HissInterp();
		var reader = new HissReader(interp);
		load("stdlib.hiss",
			// When running the tests, time the execution of each expression in stdlib.hiss
			#if test
			true
			#else
			false
			#end
		);
	}

	public function read(hiss: String): HValue {
		return HissReader.read(String(hiss+ "\n"));
	}

	public function readAll(hiss: String): HValue {
		return HissReader.readAll(String(hiss+"\n"));
	}

	public function eval(hiss: String): HValue {
		var hval = interp.eval(read(hiss));
		
		return hval;
	}

	public function load(file: String, timed = false) {
		var program = HissReader.readAll(String(StaticFiles.getContent(file))).toList();
		
		if (timed) {
			for (expression in program) {
				trace('loading expression ${expression.toPrint()}');
				Timer.measure(function() {interp.eval(expression);});
			}
		} else {
			var list = [Symbol("progn")];
			list = list.concat(program);
			interp.eval(List(list));
		}
	}

	public function repl(hiss: String) {
		HaxeTools.println(eval(hiss).toPrint());
	}

 	public function run() {
		#if !sys
		throw 'Cannot run a repl on a non-system platform';
		#end
		var consoleReader = new ConsoleReader();

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
			
			consoleReader.cmd.prompt = ">>> ";

			input = consoleReader.readLine();
			try {
				var parsed = HissReader.read(String(input+ "\n"));
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