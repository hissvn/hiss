using Type;

import parsihax.*;
import parsihax.Parser.*;
using parsihax.Parser;

import HissParser;
import HissInterp;
import HTypes;

class Main {
	static function aoc1cheating() {
		var interp = new HissInterp();
		var inputLines = sys.io.File.getContent('input1-1.txt').split('\n');

		var sum = 0;
		for (line in inputLines) {
			sum += interp.eval(HissParser.read('(haxe- (floor (haxe/ $line 3)) 2)'));
		}
		trace('Advent Of Code Answer #1: $sum');
	}
	
	static function main() {
		
		aoc1cheating();

		/*trace(Type.typeof(new HissFunction()));*/
		trace(Type.typeof(Sys.println));
		Repl.run();

		/*
		var numberFunc = ~/[0-9]+/.regexp().map(function(x) return Std.parseInt(x) * 2).apply;

		trace(numberFunc("500"));
		trace(numberFunc("hello world"));

		var parser = new HissParser();

		trace(parser.parseString("50"));
		trace(parser.parseString("0.1"));
		trace(parser.parseString("hello"));
		trace(parser.parseString("\"fuck\""));
		trace(parser.parseString("(hello world)"));
		trace(parser.parseString("(hello . world"));
		trace(parser.parseString("(hey)(me too)"));
		*/
	}
}
