package;

using hx.strings.Strings;

using HissReader;

import HTypes;

using HissInterp;
using HissTools;

@:allow(HissInterp)
class HissReader {
    static var readTable: HValue;

    static var interp: HissInterp;
    static var macroLengths = [];

    function setMacroString(s: String, f: Dynamic) {
        readTable.put(s, Function(Haxe(Fixed, f, 'read$s')));
        if (macroLengths.indexOf(s.length) == -1) {
            macroLengths.push(s.length);
        }
    }

    public function new(globalInterp: HissInterp) {
        interp = globalInterp;
        readTable = Dict(new HDict());

        // Literals
        setMacroString('"', readString);
        var numberChars = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"];
        for (s in numberChars) {
            setMacroString(s, readNumber);
        }
        setMacroString("-", readSymbolOrSign);
        setMacroString("+", readSymbolOrSign);
        setMacroString(".", readSymbolOrSign);

        // Lists
        setMacroString("(", readDelimitedList.bind(Atom(String(")")), null));

        // Quotes
        for (symbol in ["`", "'", ","]) {
            setMacroString(symbol, readQuoteExpression);
        }

        // Ignore comments
        setMacroString("/*", readBlockComment);
        setMacroString("//", readLineComment);
        setMacroString(";", readLineComment);
    }

    static function toStream(stringOrStream: HValue) {
        return switch (stringOrStream) {
            case Atom(String(s)):
                HStream.FromString(s);
            case Object("HStream", v):
                v;
            default:
                throw 'Cannot make an hstream out of $stringOrStream';
        }
    }

    public static function readQuoteExpression(start: HValue, str: HValue, terminator: HValue): HValue {
        var expression = read(str, terminator);
        return switch (start.toString()) {
            case "`":
                Quasiquote(expression);
            case "'":
                Quote(expression);
            case ",":
                Unquote(expression);
            default:
                throw 'Not a quote expression';
        }
    }

    public static function readNumber(start: HValue, str: HValue, terminator: HValue): HValue {
        var stream = toStream(str);
        stream.putBack(start.toString());

        var token = nextToken(str, terminator);
        return if (token.indexOf('.') != -1) {
            Atom(Float(Std.parseFloat(token)));
        } else {
            Atom(Int(Std.parseInt(token)));
        };
    }

    public static function readSymbolOrSign(start: HValue, str: HValue, terminator: HValue): HValue {
        // Hyphen could either be a symbol, or the start of a negative numeral
        return if (toStream(str).nextIsWhitespace()) {
            readSymbol(start, terminator);
        } else {
            readNumber(start, str, terminator);
        }
    }

    public static function readBlockComment(start: String, str: HValue, _: HValue): HValue {
        var text = toStream(str).takeUntil(["*/"]);

        return Comment;
    }

    public static function readLineComment(start: String, str: HValue, _: HValue): HValue {
        var text = toStream(str).takeLine();

        return Comment;
    }

    public static function readString(start: String, str: HValue, _: HValue): HValue {
        return Atom(String(HaxeUtils.extract(toStream(str).takeUntil(['"']), Some(s) => s).output));
    }

    static function nextToken(str: HValue, terminator: HValue): String {
        var whitespaceOrTerminator = HStream.WHITESPACE.copy();
        whitespaceOrTerminator.push(terminator.toString());
        return HaxeUtils.extract(toStream(str).takeUntil(whitespaceOrTerminator, true, false), Some(s) => s).output;
    }

    public static function readSymbol(str: HValue, terminator: HValue): HValue {
        return Atom(Symbol(nextToken(str, terminator)));
    }

    public static function readDelimitedList(terminator: HValue, ?delimiters: HValue, start: HValue, str: HValue, _: HValue): HValue {
        var stream = toStream(str);
        /*trace('t: ${terminator.toString()}');
        trace('s: $start');
        trace('str: ${toStream(str).peekAll()}');
        */

        var delims = [];
        if (delimiters == null) {
            delims = HStream.WHITESPACE.copy();
        } else {
            delims = [for (s in delimiters.toList()) s.toString()];
        }

        var delimsOrTerminator = delims.copy();
        delimsOrTerminator.push(terminator.toString());

        var term = terminator.toString();

        var values = [];

        stream.dropWhile(delims);
        //trace(stream.length());
        while (stream.length() >= terminator.toString().length && stream.peek(term.length) != term) {
            values.push(read(Object("HStream", stream)));
            //trace(values);
            stream.dropWhile(delims);
            //trace(stream.peekAll());
            //trace(stream.length());
        }

        //trace('made it');
        stream.drop(terminator.toString());
        return List(values);
    }

    public static function read(str: HValue, ?terminator: HValue): HValue {
        var stream: HStream = toStream(str);
        stream.dropWhitespace();

        if (terminator == null) {
            terminator = Atom(String(")"));
        }

        for (length in macroLengths) {
            if (stream.length() < length) continue;
            var couldBeAMacro = stream.peek(length);
            if (readTable.toDict().exists(couldBeAMacro)) {
                stream.drop(couldBeAMacro);
                var expression = interp.funcall(
                    readTable.toDict()[couldBeAMacro], 
                    List([Atom(String(couldBeAMacro)), Object("HStream", stream), terminator]));

                // If the expression is a comment, try to read the next one
                return switch (expression) {
                    case Comment:
                        read(Object("HStream", stream), terminator); 
                    default: 
                        expression;
                }
            }
        }


        // Default to symbol
        try {
            return readSymbol(Object("HStream", stream), terminator);
        } catch (s: Dynamic) {
            throw 'Failed to read from $stream because no macros matched and then $s';
        }
    }
}

        /*

        var hissList = '('.string().trim()
            .then(hissExpression.many())
            .skip(')'.string().trim())
            .map((r) -> List(r));

        var hissQuasiquote = '`'.string().then(hissExpression)
            .map((r) -> Quasiquote(r));

        var hissQuote = "'".string().then(hissExpression)
            .map((r) -> Quote(r));

        var hissUnquote = ",".string().then(hissExpression)
            .map((r) -> Unquote(r)); 

}
*/