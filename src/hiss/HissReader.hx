package hiss;

import haxe.ds.Either;

using hx.strings.Strings;

import hiss.HDict;
using hiss.HissReader;

import hiss.HTypes;
import hiss.CCInterp;

using hiss.HissTools;
using hiss.HaxeTools;

import hiss.HStream.HPosition;

typedef HaxeReadFunction = (start: String, stream: HStream) -> HValue;

class HissReader {
    var readTable: HDict;

    var macroLengths = [];
    var interp: CCInterp;

    public function copyReadtable(): HDict {
        return readTable.copy();
    }

    public function useReadtable(table: HDict) {
        this.readTable = table;
    }

    public function setMacroString(s: String, f: HValue) {
        readTable.put(String(s), f);
        if (macroLengths.indexOf(s.length) == -1) {
            macroLengths.push(s.length);
        }
        macroLengths.sort(function(a, b) { return b - a; });
        return f;
    }

    public function setDefaultReadFunction(f: HValue) {
        readTable.put(String(""), f);
    }

    function hissReadFunction(f: HaxeReadFunction, s: String) {
        return Function((args: HValue, env: HValue, cc: Continuation) -> {
            var start = args.first().toHaxeString();
            var str = toStream(interp, args.second());
            cc(f(start, str));
        }, s, ["start", "stream"]);
    }

    function internalSetMacroString(s: String, f: HaxeReadFunction) {
        readTable.put(String(s), hissReadFunction(f, 'read-$s'));
        if (macroLengths.indexOf(s.length) == -1) {
            macroLengths.push(s.length);
        }
        macroLengths.sort(function(a, b) { return b - a; });
    }

    public function new(interp: CCInterp) {
        this.interp = interp;

        readTable = new HDict(interp);
        setDefaultReadFunction(hissReadFunction(readSymbol, "read-symbol"));

        // Literals
        internalSetMacroString('"', readString);
        internalSetMacroString("#", readRawString);
        var numberChars = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0x", "0X"];
        for (s in numberChars) {
            internalSetMacroString(s, readNumber);
        }
        internalSetMacroString("-", readSymbolOrSign);
        internalSetMacroString("+", readSymbolOrSign);
        internalSetMacroString(".", readSymbolOrSign);

        // Lists
        internalSetMacroString("(", readDelimitedList.bind(")", [], false, null));

        // Quotes
        for (symbol in ["`", "'", ",", ",@"]) {
            internalSetMacroString(symbol, readQuoteExpression);
        }

        // Ignore comments
        internalSetMacroString("/*", readBlockComment);
        internalSetMacroString("//", readLineComment);
        internalSetMacroString(";", readLineComment);
        
    }
    
    static function toStream(interp: CCInterp, stringOrStream: HValue, ?pos: HValue) {
        var position = if (pos != null) pos.value(interp) else null;

        return switch (stringOrStream) {
            case String(s):
                HStream.FromString(s, position);
            case Object("HStream", v):
                v;
            default:
                throw 'Cannot make an hstream out of $stringOrStream';
        }
    }

    function readQuoteExpression(start: String, stream: HStream): HValue {
        var expression = read("", stream);
        return switch (start) {
            case "`":
                Quasiquote(expression);
            case "'":
                Quote(expression);
            case ",":
                Unquote(expression);
            case ",@":
                UnquoteList(expression);
            default:
                throw 'Not a quote expression';
        }
    }

    public function readNumber(start: String, stream: HStream): HValue {
        stream.putBack(start);

        var token = nextToken(stream);
        return if (token.indexOf('.') != -1) {
            Float(Std.parseFloat(token));
        } else {
            Int(Std.parseInt(token));
        };
    }

    function readSymbolOrSign(start: String, stream: HStream): HValue {
        // Hyphen could either be a symbol (subraction), or the start of a negative numeral
        return if (stream.nextIsWhitespace() || stream.nextIsOneOf(terminators)) {
            stream.putBack(start);
            readSymbol("", stream);
        } else {
            readNumber(start, stream);
        }
    }

    function readBlockComment(start: String, stream: HStream): HValue {
        stream.takeUntil(["*/"]);
        return Comment;
    }

    function readLineComment(start: String, stream: HStream): HValue {
        stream.takeLine();
        return Comment;
    }

    function readRawString(start: String, str: HStream): HValue {
        var pounds = "#";
        while (str.peek(1) == "#") {
            pounds += str.take(1);
        }
        str.drop('"');
        var terminator = '"$pounds';

        switch (str.takeUntil([terminator], false, false)) {
            case Some(s): 
                return String(s.output);
            case None:
                throw 'Expected closing $terminator for read-raw-string of $str';
        }
    }

    public function readString(start: String, str: HStream): HValue {
        // Quotes inside Interpolated expressions shouldn't terminate the literal

        var literal = "";
        while (true) {
            var outputInfo = HaxeTools.extract(str.takeUntil(['"', '\\$', '$', '\\\\'], false, true, false), Some(o) => o); // don't drop the terminator
            //trace(outputInfo.terminator);
            switch (outputInfo.terminator) {
                case '"':
                    literal += outputInfo.output;
                    str.drop(outputInfo.terminator);
                    break;
                case "\\$":
                    literal += outputInfo.output + outputInfo.terminator;
                    str.drop(outputInfo.terminator);
                case '$':
                    literal += outputInfo.output + outputInfo.terminator;
                    str.drop(outputInfo.terminator);

                    // There is a painful edge case where string literals could be inside an expression
                    // being interpolated into another string literal. The only way to make sure we're
                    // taking the entire OUTER string literal is to preemptively read the expression
                    // being interpolated, even though it will need to be read again later at eval-time.
                    var expStream = str.copy();

                    var exp = null;
                    var expLength = -1;
                    var startingLength = expStream.length();

                    if (expStream.peek(1) == "{") {
                        expStream.drop("{");
                        var braceContents = HaxeTools.extract(expStream.takeUntil(['}'], false, false, true), Some(o) => o).output;
                        expStream = HStream.FromString(braceContents);
                        expLength = 2 + expStream.length();
                        exp = read("", expStream);
                    } else {
                        exp = read("", expStream);
                        expLength = startingLength - expStream.length();
                    }
                    switch (exp) {
                        // The closing quote of an interp string like "$var" will get caught up as part of the symbol name
                        case Symbol(name) if (name.charAt(name.length - 1) == '"'):
                            expLength -= 1;
                        default:
                    }
                    literal += str.take(expLength);
                case '\\\\':
                    literal += "\\";
                    str.drop(outputInfo.terminator);
            }
        }

        var escaped = literal;

        // Via https://haxe.org/manual/std-String-literals.html, missing ASCII and Unicode code point support:
        escaped = escaped.replaceAll("\\t", "\t");
        escaped = escaped.replaceAll("\\n", "\n");
        escaped = escaped.replaceAll("\\r", "\r");
        escaped = escaped.replaceAll('\\"', '"');
        // Single quotes are not a thing in Hiss                

        // Strings with regular quotes need to be interpolated at eval-time
        return InterpString(escaped);
    }

    public function nextToken(str: HStream): String {
        str.dropWhitespace();

        var whitespaceOrTerminator = HStream.WHITESPACE.concat(terminators);

        var token = try {
            HaxeTools.extract(str.takeUntil(whitespaceOrTerminator, true, false, false), Some(s) => s, "next token").output;
        } catch (s: Dynamic) {
            "";
        };

        if (token == "") {
            throw "nextToken() called without a next token in the stream";
        }

        return token;
    }

    public function readSymbol(start: String, str: HStream): HValue {
        if (str.peek(1) == ")") throw "Unmatched closing paren";
        var symbolName = nextToken(str);
        // braces are not allowed in symbols because they would break string interpolation
        if (symbolName.indexOf("{") != -1 || symbolName.indexOf("}") != -1) {
            throw 'Cannot have braces in symbol $symbolName';
        }
        // We mustn't return Symbol(nil) or Symbol(null) or Symbol(t) because it creates annoying logical edge cases
        if (symbolName == "nil") return Nil;
        if (symbolName == "null") return Null;
        if (symbolName == "t") return T;
        return Symbol(symbolName);
    }

    // blankElements specifies a value to return for blank elements (i.e. if there are two delimiters in a row).
    // if blankElements is null, consecutive delimiters are skipped as a group
    public function readDelimitedList(terminator: String, delimiters: Array<String>, eofTerminates: Bool, ?blankElements: HValue, start: String, stream: HStream): HValue {
        // While reading a delimited list we will use different terminators
        var oldTerminators = terminators.copy();
        
        // We want to skip any whitespace that follows a delimiter, but if the terminator is a whitespace character, that will
        // cause an error, so for these purposes, don't treat the terminator as whitespace no matter what.
        var whitespaceForThesePurposes = HStream.WHITESPACE.copy();
        whitespaceForThesePurposes.remove(terminator);

        if (delimiters.length == 0) {
            delimiters = HStream.WHITESPACE.copy();
        } else {
            delimiters = delimiters.copy(); // TODO why?
            terminators = terminators.concat(delimiters);
        }

        terminators.push(terminator);

        var values = [];

        while (stream.length() >= terminator.length && stream.peek(terminator.length) != terminator) {
            if (stream.nextIsOneOf(delimiters) || stream.nextIsOneOf([terminator]) || (eofTerminates && stream.isEmpty())) {
                if (blankElements != Null) {
                    values.push(blankElements);
                }
            } else {
                values.push(read("", stream));
            }
            stream.dropIfOneOf(delimiters);
            stream.dropWhileOneOf(whitespaceForThesePurposes);
        }
        
        // require the terminator unless eofTerminates
        if (eofTerminates && stream.isEmpty()) {
        } else {
            // Always drop the terminator if it's there
            try {
                stream.drop(terminator);
            } catch (s: Dynamic) {
                trace(eofTerminates);
                trace(stream.isEmpty());
                throw 'terminator $terminator not found while reading $delimiters delimited list from $stream';
            }
        }

        terminators = oldTerminators;

        return List(values);
    }

    function callReadFunction(func: HValue, start: String, stream: HStream): HValue {
        var pos = stream.position();
        var startingStream = stream.toString();
        try {
            var result = interp.eval(func.cons(List([String(start), Object("HStream", stream)])));
            #if traceReader
            HissTools.print(result);
            #end
            return result;
        }
        #if !throwErrors
        catch (s: Dynamic) {
            var endingStream = stream.toString();
            var consumed = startingStream.substr(0, startingStream.length - endingStream.length);
            if (s.indexOf("Reader error") == 0) throw s;
            throw 'Reader error `$s` after taking `$consumed` at ${pos.toString()}';
        }
        #end
    }

    var terminators = [")", "/*", ";", "//"];

    public function read(start: String, stream: HStream): HValue {
        stream.dropWhitespace();

        for (length in macroLengths) {
            if (stream.length() < length) continue;
            var couldBeAMacro = stream.peek(length);
            if (readTable.exists(String(couldBeAMacro))) {
                stream.drop(couldBeAMacro);
                var pos = stream.position();
                var expression = null;
                
                expression = callReadFunction(readTable.get(String(couldBeAMacro)), couldBeAMacro, stream);

                // If the expression is a comment, try to read the next one
                return switch (expression) {
                    case Comment:
                        return if (stream.isEmpty()) {
                            Nil; // This is awkward but better than always erroring when the last expression is a comment
                        } else {
                            read("", stream); 
                        }
                    default:
                        expression;
                }
            }
        }

        // Call default read function
        return callReadFunction(readTable.get(String("")), "", stream);
    }

    public function readAll(str: HValue, ?dropWhitespace: HValue, ?terminators: HValue, ?pos: HValue): HValue {
        var stream: HStream = toStream(interp, str, pos);

        if (dropWhitespace == null) dropWhitespace = T;

        var exprs = [];

        while (!stream.isEmpty()) {
            exprs.push(read("", stream));
            if (dropWhitespace != Nil) {
                stream.dropWhitespace();
            }
        }
        return List(exprs);
    }
}