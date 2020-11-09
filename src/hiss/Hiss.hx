package hiss;

import haxe.macro.Context;
import haxe.macro.Expr;
import hiss.Stream;
import hiss.Reader;

class Hiss {
	/**
		Build a Haxe class from a corresponding .hiss file
	**/
	public static function build(hissFile) {
		var classFields = Context.getBuildFields();

		var stream = new Stream(hissFile);
		var reader = new Reader();
		while (!stream.isEmpty()) {
			classFields.push(expressionToField(reader.read(stream)));
		}

		return classFields;
	}

	static function expressionToField(exp:ReaderExp):Field {
		return {
			// TODO make the pos be in the .hiss file!
			pos: Context.currentPos();
		};
	}
}
