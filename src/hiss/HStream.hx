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

    public function copy():HPosition {
        return new HPosition(file, line, column);
    }

    public function toString():String {
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
    var _rawString:String;
    var _pos:HPosition;

    static var _dummyCount:Int = 0;

    public function new(path:String, rawString:String, line:Int = 1, column:Int = 1) {
        if (rawString == null) {
            throw 'Tried to create buffer of path $path with null contents';
        }

        // Banish ye Windows line-endings
        rawString = rawString.replace('\r', '');

        this._rawString = rawString;
        this._pos = new HPosition(path, line, column);
    }

    public static function FromString(s:String, ?pos:HPosition):HStream {
        return if (pos == null) {
            new HStream('!NOTAFILE-${_dummyCount++}!', s);
        } else {
            new HStream(pos.file, s, pos.line, pos.column);
        }
    }

    #if (sys || hxnodejs)
    public static function FromFile(path:String):HStream {
        return new HStream(path, sys.io.File.getContent(path));
    }
    #end

    public function indexOf(s:String, start:Int = 0):Int {
        return _rawString.indexOf(s, start);
    }

    public function everyIndexOf(s:String, start:Int = 0):Array<Int> {
        return [for (i in start..._rawString.length) i].filter(function(i) return _rawString.charAt(i) == s);
    }

    public function length():Int {
        return _rawString.length;
    }

    public function _position():HPosition {
        return _pos.copy();
    }

    /** Peek at contents buffer waiting further ahead in the buffer **/
    public function peekAhead(start:Int, length:Int):String {
        return _rawString.substr(start, length);
    }

    /** Peek through the buffer until encountering one of the given terminator sequences
        @param eofTerminates Whether the end of the file is also a valid terminator
    **/
    // NOTE: The _ parameter is to match the signature of a Retriever function for getLine
    public function peekUntil(terminators:Array<String>, eofTerminates:Bool = false, allowEscapedTerminators:Bool = true,
            _:Bool = false):Option<HStreamOutput> {
        if (_rawString.length == 0)
            return None;

        var index = _rawString.length;

        var whichTerminator = '';
        for (terminator in terminators) {
            var nextIndex = _rawString.indexOf(terminator);
            // Don't acknowledge terminators preceded by the escape operator
            while (allowEscapedTerminators && nextIndex > 0 && _rawString.charAt(nextIndex - 1) == '\\') {
                nextIndex = _rawString.indexOf(terminator, nextIndex + 1);
            }
            if (nextIndex != -1 && nextIndex < index) {
                index = nextIndex;
                whichTerminator = terminator;
            }
        }

        return if (index < _rawString.length) {
            Some({
                output: _rawString.substr(0, index),
                terminator: whichTerminator
            });
        } else if (eofTerminates) {
            Some({output: _rawString, terminator: null});
        } else {
            None;
        }
    }

    public function toString() {
        var snip = _rawString.substr(0, 50);
        return '`$snip...`';
    }

    public function copy() {
        return HStream.FromString(_rawString, _pos);
    }

    public function drop_d(s:String) {
        // trace('dropping $s');
        var next = peek(s.length);
        if (next != s) {
            throw 'Expected to drop `$s` from buffer but found `$next`';
        }

        var lines = HStream.FromString(next).everyIndexOf('\n').length;
        if (lines > 0) {
            _pos.line += lines;
            _pos.column = next.substring(next.lastIndexOf('\n')).length;
        } else {
            _pos.column += next.length;
        }

        _rawString = _rawString.substr(s.length);
    }

    /** Take data from the file until encountering one of the given terminator sequences. **/
    public function takeUntil_d(terminators:Array<String>, eofTerminates:Bool = false, allowEscapedTerminators:Bool = true,
            dropTerminator = true):Option<HStreamOutput> {
        return switch (peekUntil(terminators, eofTerminates, allowEscapedTerminators)) {
            case Some({output: s, terminator: t}):
                // Remove the desired data from the buffer
                drop_d(s);

                // Remove the terminator that followed the data from the buffer
                if (dropTerminator && t != null) {
                    // trace('dropping the terminator which is "$t"');
                    drop_d(t);
                }

                // Return the desired data
                Some({output: s, terminator: t});
            case None:
                None;
        }
    }

    public function peek(chars:Int) {
        if (_rawString.length < chars) {
            throw 'Not enough characters left in buffer.';
        }
        var data = _rawString.substr(0, chars);
        return data;
    }

    public function take_d(chars:Int) {
        var data = peek(chars);
        drop_d(data);
        return data;
    }

    /** Count consecutive occurrence of the given string at the current buffer position, dropping the counted sequence **/
    public function countConsecutive_d(s:String) {
        var num = 0;

        while (_rawString.substr(0, s.length) == s) {
            num += 1;
            drop_d(s);
        }

        return num;
    }

    /** DRY Helper for peekLine() and takeLine() 
        @param trimmed String including 'l' (ltrim), and/or 'r' (rtrim)
    **/
    function getLine(trimmed:String, retriever:Retriever):Option<String> {
        var nextLine = retriever(['\n'], true, true, true);

        return switch (nextLine) {
            case Some({output: nextLine, terminator: _}):
                if (nextLine.charAt(nextLine.length - 1) == '\n') {
                    // trace('dropping the thing');
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
    public function takeLine_d(trimmed = ''):Option<String> {
        return getLine(trimmed, takeUntil_d);
    }

    public function takeLineAsStream_d(trimmed = ''):HStream {
        var pos = _position();
        return HStream.FromString(HaxeTools.extract(takeLine_d(trimmed), Some(s) => s), pos);
    }

    public static var _WHITESPACE = [" ", "\n", "\t"];

    // \r doesn't need to be considered whitespace because HStream removes \r before doing anything else
    // This function is more complicated than nextIsOneOf() because it needs to give longer strings precedence
    public function dropWhileOneOf_d(stringsToDrop:Array<String>, limit:Int = -1) {
        var lengths:Map<Int, Bool> = [];
        var stringsToDropMap:Map<String, Bool> = [];
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
                        drop_d(couldBeOneOf);
                        dropped = true;
                        break; // out of the for loop
                    }
                }
            }
            if (dropped)
                continue;
            break;
        }
    }

    public function dropIfOneOf_d(stringsToDrop:Array<String>) {
        dropWhileOneOf_d(stringsToDrop, 1);
    }

    public function dropWhitespace_d() {
        dropWhileOneOf_d(_WHITESPACE);
    }

    public function takeUntilWhitespace_d() {
        return takeUntil_d(_WHITESPACE, true, false);
    }

    public function peekUntilWhitespace() {
        return peekUntil(_WHITESPACE, true, false);
    }

    public function nextIsWhitespace() {
        return _rawString.length == 0 || _WHITESPACE.indexOf(peek(1)) != -1;
    }

    public function nextIsOneOf(a:Array<String>) {
        for (s in a) {
            if (_rawString.length >= s.length && _rawString.indexOf(s) == 0) {
                return true;
            }
        }
        return false;
    }

    public function putBack_d(s:String) {
        _rawString = s + _rawString;
        if (s.indexOf('\n') != -1) {
            _pos.line -= HStream.FromString(s).everyIndexOf('\n').length;
            _pos.column = 0;
        } else {
            _pos.column -= s.length;
        }
    }

    public function peekAll() {
        return _rawString;
    }

    public function isEmpty() {
        return _rawString.length == 0;
    }
}
