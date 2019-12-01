package;

using StringTools;
using ParserTools;

import Expressions;

class ParserTools {
 public static function before(str: String, delimiter: String) {
	var index = str.indexOf(delimiter);
	return str.substr(0, index);
 }

 public static function after(str: String, delimiter: String) {
	var index = str.indexOf(delimiter);
	return str.substr(index);
	}

}

class Parser {

 public function new() {
 }

 public function parse(input: String): HValue {
	switch (input[0]) {
	 case "'":
	  // TODO this doesn't allow for quoted lists
	  return HValue.Atom(HAtom.Symbol(input.substr(1)));
	 case '"':
	  // TODO allow for escaped quotes
	  return HValue.Atom(HAtom.String(input.after('"').before('"')));
	 case "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9":
	  if (input.contains(".")) {
	   return HValue.Atom(HAtom.Double(Std.parseFloat(input)));
	  } else {
		 return HValue.Atom(HAtom.Int(Std.parseInt(input)));
	  }
	 case "(":
	  input = input.after("(");
    var lastParen 
	 default:
    return HValue.Atom(HValue.Symbol(input));
	}
	return HValue.Atom(HAtom.Nil);
 }

}