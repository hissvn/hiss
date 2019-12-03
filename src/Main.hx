import parsihax.*;
import parsihax.Parser.*;
using parsihax.Parser;

class Main {
	static function main() {
		trace("Hello, world!");

		var numberFunc = ~/[0-9]+/.regexp().map(function(x) return Std.parseInt(x) * 2).apply;

		trace(numberFunc("500"));
		trace(numberFunc("hello world"));
	}
}
