package hiss;

import haxe.ds.Either;

using hx.strings.Strings;

using hiss.HissReader;

import hiss.HTypes;
import hiss.CCInterp;

using hiss.HissTools;
using hiss.HaxeTools;

import hiss.HStream.HPosition;

typedef HaxeReadFunction = (start: String, stream: HStream) -> HValue;

class HissReader {
    var readTable: Map<String, HValue> = new Map();
    var defaultReadFunction: HValue;

    var macroLengths = [];
    var interp: CCInterp;

    public function setMacroString(s: String, f: HValue) {
        readTable.set(s, f);
        if (macroLengths.indexOf(s.length) == -1) {
            macroLengths.push(s.length);
        }
        macroLengths.sort(function(a, b) { return b - a; });
        return f;
    }

    public function setDefaultReadFunction(f: HValue) {
        defaultReadFunction = f;
    }

    function hissReadFunction(f: HaxeReadFunction, s: String) {
        return Function((args: HValue, env: HValue, cc: Continuation) -> {
            var start = args.first().toHaxeString();
            var str = toStream(args.second());
            cc(f(start, str));
        }, s);
    }

    function internalSetMacroString(s: String, f: HaxeReadFunction) {
        readTable.set(s, hissReadFunction(f, 'read-$s'));
        if (macroLengths.indexOf(s.length) == -1) {
            macroLengths.push(s.length);
        }
        macroLengths.sort(function(a, b) { return b - a; });
    }

    public function new(interp: CCInterp) {
        this.interp = interp;

        defaultReadFunction = hissReadFunction(readSymbol, "read-symbol");

        // Literals
        internalSetMacroString('"', readString);
        var numberChars = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"];
        for (s in numberChars) {
            internalSetMacroString(s, readNumber);
        }
        internalSetMacroString("-", readSymbolOrSign);
        internalSetMacroString("+", readSymbolOrSign);
        internalSetMacroString(".", readSymbolOrSign);

        // Lists
        internalSetMacroString("(", readDelimitedList.bind(")", null));

        // Quotes
        for (symbol in ["`", "'", ",", ",@"]) {
            internalSetMacroString(symbol, readQuoteExpression);
        }

        // Ignore comments
        internalSetMacroString("/*", readBlockComment);
        internalSetMacroString("//", readLineComment);
        internalSetMacroString(";", readLineComment);
        
    }
    
    static function toStream(stringOrStream: HValue, ?pos: HValue) {
        var position = if (pos != null) pos.value() else null;

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

    function readNumber(start: String, stream: HStream): HValue {
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
            trace('reading number from $start : $stream');
            readNumber(start, stream);
        }
    }

    public function readBlockComment(start: String, stream: HStream): HValue {
        stream.takeUntil(["*/"]);
        return Comment;
    }

    public function readLineComment(start: String, stream: HStream): HValue {
        stream.takeLine();
        return Comment;
    }

    public static function readString(start: String, str: HStream): HValue {
        //trace(str);
        switch (str.takeUntil(['"'])) {
            case Some(s): 
                var escaped = s.output;

                // Via https://haxe.org/manual/std-String-literals.html, missing ASCII and Unicode code point support:
                escaped = escaped.replaceAll("\\t", "\t");
                escaped = escaped.replaceAll("\\n", "\n");
                escaped = escaped.replaceAll("\\r", "\r");
                escaped = escaped.replaceAll('\\"', '"');
                // Single quotes are not a thing in Hiss

                return String(escaped);
            case None:
                throw 'Expected close quote for read-string of $str';
        }
    }

    function nextToken(str: HStream): String {
        var whitespaceOrTerminator = HStream.WHITESPACE.concat(terminators);

        return HaxeTools.extract(str.takeUntil(whitespaceOrTerminator, true, false), Some(s) => s, "next token").output;
    }

    function readSymbol(start: String, str: HStream): HValue {
        var symbolName = nextToken(str);
        // We mustn't return Symbol(nil) because it creates a logical edge case
        if (symbolName == "nil") return Nil;
        if (symbolName == "t") return T;
        return Symbol(symbolName);
    }

    function readDelimitedList(terminator: String, delimiters: Array<String>, start: String, stream: HStream): HValue {
        // While reading a delimited list we will use different terminators
        var oldTerminators = terminators.copy();
        
        if (delimiters == null) {
            delimiters = HStream.WHITESPACE.copy();
        } else {
            delimiters = delimiters.copy();
            terminators = terminators.concat(delimiters);
        }

        terminators.push(terminator);

        var values = [];

        stream.dropWhile(delimiters);
        
        while (stream.length() >= terminator.length && stream.peek(terminator.length) != terminator) {
            values.push(read("", stream));
            
            stream.dropWhile(delimiters);
        }

        stream.drop(terminator);

        terminators = oldTerminators;

        return List(values);
    }

    function callReadFunction(func: HValue, start: String, stream: HStream): HValue {
        var pos = stream.position();
        try {
            var result = null;
            interp.eval(func.cons(List([String(start), Object("HStream", stream)])), Dict([]), (r) -> {
                result = r;
            });
            return result;
        }
        #if !throwErrors
        catch (s: Dynamic) {
            if (s.indexOf("Reader error") == 0) throw s;
            throw 'Reader error `$s` at ${pos.toString()}';
        }
        #end
    }

    var terminators = [")", "/*", ";", "//"];

    public function read(start: String, stream: HStream): HValue {
        stream.dropWhitespace();

        for (length in macroLengths) {
            if (stream.length() < length) continue;
            var couldBeAMacro = stream.peek(length);
            if (readTable.exists(couldBeAMacro)) {
                stream.drop(couldBeAMacro);
                var pos = stream.position();
                var expression = null;
                
                expression = callReadFunction(readTable[couldBeAMacro], couldBeAMacro, stream);

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
        return callReadFunction(defaultReadFunction, "", stream);
    }

    public function readAll(str: HValue, ?dropWhitespace: HValue, ?terminators: HValue, ?pos: HValue): HValue {
        var stream: HStream = toStream(str, pos);

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