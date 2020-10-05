package hiss;

using StringTools;

import haxe.ds.Option;

/**
	A position in an HStream, used for debugging.
**/
class HPosition {
	public var file:String;
	public var line:Int;
	public var column:Int;

	public function new(file:String, line:Int, column:Int) {
		this.file = file;
		this.line = line;
		this.column = column;
	}

	public function equals(other:HPosition) {
		return file == other.file && line == other.line && column == other.column;
	}

	public function copy(): HPosition {
		return new HPosition(file, line, column);
	}

	public function toString(): String {
		return '$file:$line:$column';
	}
}

typedef HStreamOutput = {
	output:String,
	terminator:String
};

typedef Retriever = (Array<String>, Bool, Bool, Bool) -> Option<HStreamOutput>;

/**
	Helper class for reading/parsing information from a string stream.
**/
@:allow(tests.HStreamTest)
class HStream {
	var rawString:String;
	var pos: HPosition;
	static var dummyCount: Int = 0;

	public function new(path:String, rawString:String, line:Int = 1, column:Int = 1) {
		if (rawString == null) {
			throw 'Tried to create buffer of path $path with null contents';
		}

		// Banish ye Windows line-endings
		rawString = rawString.replace('\r', '');

		this.rawString = rawString;
		this.pos = new HPosition(path, line, column);
	}

	public static function FromString(s: String, ?pos: HPosition): HStream {
		return if (pos == null) {
			new HStream('!NOTAFILE-${dummyCount++}!', s);
		} else {
			new HStream(pos.file, s, pos.line, pos.column);
		}
	}

	#if (sys || hxnodejs)
	public static function FromFile(path: String): HStream {
		return new HStream(path, sys.io.File.getContent(path));
	}
	#end

	public function indexOf(s:String, start:Int = 0):Int {
		return rawString.indexOf(s, start);
	}

	public function everyIndexOf(s:String, start:Int = 0):Array<Int> {
		return [for (i in start...rawString.length) i].filter(function(i) return rawString.charAt(i) == s);
	}

	public function length():Int {
		return rawString.length;
	}

	public function position():HPosition {
		return pos.copy();
	}

	/** Peek at contents buffer waiting further ahead in the buffer **/
	public function peekAhead(start:Int, length:Int):String {
		return rawString.substr(start, length);
	}

	/** Peek through the buffer until encountering one of the given terminator sequences
		@param eofTerminates Whether the end of the file is also a valid terminator
	**/
	// NOTE: The _ parameter is to match the signature of a Retriever function for getLine
	public function peekUntil(terminators:Array<String>, eofTerminates:Bool = false, allowEscapedTerminators:Bool = true, _:Bool = false):Option<HStreamOutput> {
		if (rawString.length == 0)
			return None;

		var index = rawString.length;

		var whichTerminator = '';
		for (terminator in terminators) {
			var nextIndex = rawString.indexOf(terminator);
			// Don't acknowledge terminators preceded by the escape operator 
			while (allowEscapedTerminators && nextIndex > 0 && rawString.charAt(nextIndex-1) == '\\') {
				nextIndex = rawString.indexOf(terminator, nextIndex+1);
			}
			if (nextIndex != -1 && nextIndex < index) {
				index = nextIndex;
				whichTerminator = terminator;
			}
		}

		return if (index < rawString.length) {
			Some({
				output: rawString.substr(0, index),
				terminator: whichTerminator
			});
		} else if (eofTerminates) {
			Some({output: rawString, terminator: null});
		} else {
			None;
		}
	}

	public function toString() {
		var snip = rawString.substr(0, 50);
		return '`$snip...`';
	}

	public function copy() {
		return HStream.FromString(rawString, pos);
	}

	public function drop(s:String) {
		//trace('dropping $s');
		var next = peek(s.length);
		if (next != s) {
			throw 'Expected to drop `$s` from buffer but found `$next`';
		}

		var lines = HStream.FromString(next).everyIndexOf('\n').length;
		if (lines > 0) {
			pos.line += lines;
			pos.column = next.substring(next.lastIndexOf('\n')).length;
		} else {
			pos.column += next.length;
		}

		rawString = rawString.substr(s.length);
	}

	/** Take data from the file until encountering one of the given terminator sequences. **/
	public function takeUntil(terminators:Array<String>, eofTerminates:Bool = false, allowEscapedTerminators:Bool = true, dropTerminator = true):Option<HStreamOutput> {
		return switch (peekUntil(terminators, eofTerminates, allowEscapedTerminators)) {
			case Some({output: s, terminator: t}):
				// Remove the desired data from the buffer
				drop(s);

				// Remove the terminator that followed the data from the buffer
				if (dropTerminator && t != null) {
					//trace('dropping the terminator which is "$t"');
					drop(t);
				}

				// Return the desired data
				Some({output: s, terminator: t});
			case None:
				None;
		}
	}

	public function peek(chars:Int) {
		if (rawString.length < chars) {
			throw 'Not enough characters left in buffer.';
		}
		var data = rawString.substr(0, chars);
		return data;
	}

	public function take(chars:Int) {
		var data = peek(chars);
		drop(data);
		return data;
	}

	/** Count consecutive occurrence of the given string at the current buffer position, dropping the counted sequence **/
	public function countConsecutive(s:String) {
		var num = 0;

		while (rawString.substr(0, s.length) == s) {
			num += 1;
			drop(s);
		}

		return num;
	}

	/** If the given expression comes next in the buffer, take its contents. Otherwise, return None **/
	/*public function expressionIfNext(o:String, c:String):Option<String> {
		if (rawString.startsWith(o) && cleanBuffer.indexOf(c) != -1) {
			drop(o);
			var end = cleanBuffer.indexOf(c);
			var content = take(end);
			drop(c);
			return Some(content);
		}
		return None;
	}*/

	/** DRY Helper for peekLine() and takeLine() 
		@param trimmed String including 'l' (ltrim), and/or 'r' (rtrim)
	**/
	function getLine(trimmed:String, retriever:Retriever):Option<String> {
		var nextLine = retriever(['\n'], true, true, true);

		return switch (nextLine) {
			case Some({output: nextLine, terminator: _}):
				if (nextLine.charAt(nextLine.length-1) == '\n') {
					//trace('dropping the thing');
					nextLine = nextLine.substr(0, -1);
				}
				if (trimmed.indexOf('r') != -1) {
					nextLine = nextLine.rtrim();
				}
				if (trimmed.indexOf('l') != -1) {
					nextLine = nextLine.ltrim();
				}
				Some(nextLine);
			case None:
				None;
		};
	}

	/** Peek the next line of data from the stream. **/
	public function peekLine(trimmed = ''):Option<String> {
		return getLine(trimmed, peekUntil);
	}

	/** Take the next line of data from the stream.
		@param trimmed Which sides of the line to trim ('r' 'l', 'lr', or 'rl')
	**/
	public function takeLine(trimmed = ''):Option<String> {
		return getLine(trimmed, takeUntil);
	}

	public function takeLineAsStream(trimmed = ''): HStream {
		var pos = position();
		return HStream.FromString(HaxeTools.extract(takeLine(trimmed), Some(s) => s), pos);
	}

	public static var WHITESPACE = [" ", "\n", "\t"];
	// \r doesn't need to be considered whitespace because HStream removes \r before doing anything else

	// This function is more complicated than nextIsOneOf() because it needs to give longer strings precedence
	public function dropWhileOneOf(stringsToDrop: Array<String>, limit: Int = -1) {
		var lengths: Map<Int, Bool> = [];
		var stringsToDropMap: Map<String, Bool> = [];
		for (str in stringsToDrop) {
			lengths[str.length] = true;
			stringsToDropMap[str] = true;
		}
		var lengthsDescending = [for (l in lengths.keys()) l];
		lengthsDescending.sort(Reflect.compare);
		lengthsDescending.reverse();
		while (limit == -1 || limit-- > 0) {
			var dropped = false;
			for (l in lengthsDescending) {
				if (length() >= l) {
					var couldBeOneOf = peek(l);
					if (stringsToDropMap.exists(couldBeOneOf)) {
						drop(couldBeOneOf);
						dropped = true;
						break; // out of the for loop
					}
				}
			}
			if (dropped) continue;
			break; 
		}
	}

	public function dropIfOneOf(stringsToDrop: Array<String>) {
		dropWhileOneOf(stringsToDrop, 1);
	}

	public function dropWhitespace() {
		dropWhileOneOf(WHITESPACE);
	}

	public function takeUntilWhitespace() {
		return takeUntil(WHITESPACE, true, false);
	}

	public function peekUntilWhitespace() {
		return peekUntil(WHITESPACE, true, false);
	}

	public function nextIsWhitespace() {
		return rawString.length == 0 || WHITESPACE.indexOf(peek(1)) != -1;
	}

	public function nextIsOneOf(a: Array<String>) {
		for (s in a) {
			if (rawString.length >= s.length && rawString.indexOf(s) == 0) {
				return true;
			}
		}
		return false;
	}

	public function putBack(s: String) {
		rawString = s + rawString;
		if (s.indexOf('\n') != -1) {
			pos.line -= HStream.FromString(s).everyIndexOf('\n').length;
			pos.column = 0;
		} else {
			pos.column -= s.length;
		}
	}

	public function peekAll() {
		return rawString;
	}

	public function isEmpty() {
		return rawString.length == 0;
	}
}
