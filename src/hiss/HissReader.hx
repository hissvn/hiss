package hiss;

using hx.strings.Strings;

using hiss.HissReader;

import hiss.HTypes;

using hiss.HissInterp;
using hiss.HissTools;

import hiss.HStream.HPosition;

@:allow(hiss.HissInterp)
class HissReader {
    static var readTable: HValue;
    static var defaultReadFunction: HValue;

    static var interp: HissInterp;
    static var macroLengths = [];

    public static function setMacroString(s: HValue, f: HValue) {
        var sk = s.toString();
        readTable.put(sk, f);
        if (macroLengths.indexOf(sk.length) == -1) {
            macroLengths.push(sk.length);
        }
        // Sort macro lengths from longest to shortest so, for example, ,@ and , can both be operators.
        macroLengths.sort(function(a, b) { return b - a; });
        //trace(macroLengths[0]);
        return Nil;
    }

    public static function setDefaultReadFunction(f: HValue) {
        defaultReadFunction = f;
    }

    static function internalSetMacroString(s: String, f: Dynamic) {
        readTable.put(s, Function(Haxe(Fixed, f, 'read$s')));
        if (macroLengths.indexOf(s.length) == -1) {
            macroLengths.push(s.length);
        }
        macroLengths.sort(function(a, b) { return b - a; });
    }

    public function new(globalInterp: HissInterp) {
        interp = globalInterp;
        readTable = Dict(new HDict());
        interp.set("*readtable*", readTable);

        defaultReadFunction = Function(Haxe(Fixed, readSymbol, "read-symbol"));

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
        internalSetMacroString("(", readDelimitedList.bind(Atom(String(")")), null));

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
        var position = if (pos != null) HissInterp.valueOf(pos) else null;

        return switch (stringOrStream) {
            case Atom(String(s)):
                HStream.FromString(s, position);
            case Object("HStream", v):
                v;
            default:
                throw 'Cannot make an hstream out of $stringOrStream';
        }
    }

    public static function readQuoteExpression(start: HValue, str: HValue, terminators: HValue, position: HValue): HValue {
        var expression = read(str, terminators, position);
        return switch (start.toString()) {
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

    public static function readNumber(start: HValue, str: HValue, ?terminators: HValue, position: HValue): HValue {
        var stream = toStream(str);
        stream.putBack(start.toString());

        var token = nextToken(str, terminators);
        return if (token.indexOf('.') != -1) {
            Atom(Float(Std.parseFloat(token)));
        } else {
            Atom(Int(Std.parseInt(token)));
        };
    }

    public static function readSymbolOrSign(start: HValue, str: HValue, terminators: HValue, position: HValue): HValue {
        // Hyphen could either be a symbol, or the start of a negative numeral
        return if (toStream(str).nextIsWhitespace() || toStream(str).nextIsOneOf([for (term in terminators.toList()) term.toString()])) {
            readSymbol(Atom(String("")), start, terminators, position);
        } else {
            readNumber(start, str, terminators, position);
        }
    }

    public static function readBlockComment(start: String, str: HValue, _: HValue, position: HValue): HValue {
        var text = toStream(str).takeUntil(["*/"]);

        return Comment;
    }

    public static function readLineComment(start: String, str: HValue, _: HValue, position: HValue): HValue {
        var text = toStream(str).takeLine();

        return Comment;
    }

    public static function readString(start: String, str: HValue, _: HValue, position: HValue): HValue {
        switch (toStream(str).takeUntil(['"'])) {
            case Some(s): 
                var escaped = s.output;

                // Via https://haxe.org/manual/std-String-literals.html, missing ASCII and Unicode code point support:
                escaped = escaped.replaceAll("\\t", "\t");
                escaped = escaped.replaceAll("\\n", "\n");
                escaped = escaped.replaceAll("\\r", "\r");
                escaped = escaped.replaceAll("\\\"", "\"");
                // Single quotes are not a thing in Hiss

                return Atom(String(escaped));
            case None:
                throw 'Expected close quote for read-string';
        }
    }

    static function nextToken(str: HValue, ?terminators: HValue): String {
        var whitespaceOrTerminator = HStream.WHITESPACE.copy();
        if (terminators != null) {
            for (terminator in terminators.toList()) {
                whitespaceOrTerminator.push(terminator.toString());
            }
        }
        return HaxeTools.extract(toStream(str).takeUntil(whitespaceOrTerminator, true, false), Some(s) => s).output;
    }

    public static function readSymbol(start: HValue, str: HValue, terminators: HValue, position: HValue): HValue {
        return Atom(Symbol(nextToken(str, terminators)));
    }

    public static function readDelimitedList(terminator: HValue, ?delimiters: HValue, start: HValue, str: HValue, terminators: HValue, position: HValue): HValue {
        var stream = toStream(str, position);
        /*trace('t: ${terminator.toString()}');
        trace('s: $start');
        trace('str: ${toStream(str).peekAll()}');
        */

        var delims = [];
        if (delimiters == null || delimiters.match(Nil)) {
            delims = HStream.WHITESPACE.copy();
        } else {
            delims = [for (s in delimiters.toList()) s.toString()];
        }

        var delimsOrTerminator = [for (delim in delims) Atom(String(delim))];
        delimsOrTerminator.push(terminator);
        delimsOrTerminator.push(Atom(String("//")));
        delimsOrTerminator.push(Atom(String("/*")));


        var term = terminator.toString();

        var values = [];

        stream.dropWhile(delims);
        //trace(stream.length());
        while (stream.length() >= terminator.toString().length && stream.peek(term.length) != term) {
            values.push(read(Object("HStream", stream), /*terminator*/ List(delimsOrTerminator)));
            //trace(values);
            stream.dropWhile(delims);
            //trace(stream.peekAll());
            //trace(stream.length());
        }

        //trace('made it');
        stream.drop(terminator.toString());
        return List(values);
    }

    static function callReadFunction(func: HValue, start: String, stream: HStream, terminators: HValue): HValue {
        var pos = stream.position();
        try {
            return interp.funcall(func, List([Atom(String(start)), Object("HStream", stream), Quote(terminators), Object("HPosition", pos)]));
        } catch (s: Dynamic) {
            if (s.indexOf("Reader error") == 0) throw s;
            throw 'Reader error `$s` at ${pos.toString()}';
        }
    }

    public static function read(str: HValue, ?terminators: HValue, ?pos: HValue): HValue {
        var stream: HStream = toStream(str, pos);
        stream.dropWhitespace();

        if (terminators == null || terminators == Nil) {
            terminators = List([Atom(String(")")), Atom(String('/*')), Atom(String('//'))]);
        }

        for (length in macroLengths) {
            if (stream.length() < length) continue;
            var couldBeAMacro = stream.peek(length);
            if (readTable.toDict().exists(couldBeAMacro)) {
                stream.drop(couldBeAMacro);
                var pos = stream.position();
                var expression = null;
                //trace('read called');
                
                expression = callReadFunction(readTable.toDict()[couldBeAMacro], couldBeAMacro, stream, terminators);

                // If the expression is a comment, try to read the next one
                return switch (expression) {
                    case Comment:
                        read(Object("HStream", stream), terminators); 
                    default: 
                        expression;
                }
            }
        }


        // Call default read function
        return callReadFunction(defaultReadFunction, "", stream, terminators);
    }
}