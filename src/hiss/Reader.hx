package hiss;

import hiss.Stream;

enum ReaderExp {
	List(exps:Array<ReaderExp>); // (f a1 a2...)
	Array(exps:Array<ReaderExp>); // [v1 v2 v3]
	Symbol(name:String); // s
}

typedef ReadFunction = (Stream) -> ReaderExp;

class Reader {
	var readTable:Map<String, ReadFunction> = new Map();

	public function new() {
		readTable["("] = (stream) -> List(readExpArray(stream));
	}

	public function read(stream:Stream):ReaderExp {
		return Symbol("s");
	}

	public function readExpArray(stream:Stream):Array<ReaderExp> {
		return [];
	}
}
