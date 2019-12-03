import parsihax.*;
import parsihax.Parser.*;
using parsihax.Parser;

import HissParser;

class Main {
	static function main() {
		trace("Hello, world!");

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
	}
}
