/* Modeled after this: https://github.com/deathbeam/parsihax/blob/74f2ac81ccd07d26278433c36f13172173ab6860/test/parsihax/LispGrammar.hx#L1 */

package;

import parsihax.*;
import parsihax.Parser.*;
using parsihax.Parser;
using parsihax.ParseObject;

using HissParser;

import HTypes;

class HissParser {
    public static function read(str: String) {

        // Remove comments
        var comment = ~/;.*\n/;
        
        var oldStr = "";
        do {
            oldStr = str;
            str = comment.replace(str, "");
        } while (str != oldStr);

        if (parseFunction == null) { init(); }
        var result = parseFunction(str);
        if (!result.status) {
            throw 'failed to parse. expected ${result.expected}';
        } else {
            return result.value;
        }
    }
    static var parseFunction: ParseFunction<HValue> = null;

    private static inline function trim(parser : ParseObject<String>) {
        return parser.skip(optWhitespace());
    }

    static function init() {
        var hissExpression: ParseObject<HValue> = empty();

        var hissString = '"'.string().then(~/[^"]*/.regexp()).skip('"'.string()).trim()
            .map((r) -> Atom(String(r)))
            .as('string literal');

        // Allow more characters than the Parsihax lisp example per https://www.gnu.org/software/emacs/manual/html_node/elisp/Symbol-Type.html
        // -+=*/
        // _~!@$%^&:<>{}?
        var punctuation = "[=\\+\\*\\/\\|\\.!@$%^&:<>{}\\?_-]";
        var number = "[0-9]";
        var letter = "[a-zA-z]";
        var symbolRegex = new EReg('($letter|$punctuation)($letter|$punctuation|$number)*', '');

        var hissSymbol = symbolRegex.regexp().trim()
            .map((r) -> Atom(Symbol(r)))
            .as('symbol');

        var hissInt = ~/[+-]?[0-9][0-9]*/.regexp().trim()
            .map((r) -> Atom(Int(Std.parseInt(r))))
            .as('integer literal');

        var hissDouble = ~/[+-]?[0-9]*\.[0-9]+/.regexp().trim()
            .map((r) -> Atom(Float(Std.parseFloat(r))))
            .as('double literal');

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

        hissExpression.apply = [
            hissQuasiquote,
            hissQuote,
            hissUnquote,
            hissInt,
            hissDouble,
            hissSymbol,
            hissString,
            hissList,
            //hissCons,
        ].alt();

        parseFunction = optWhitespace().then(hissExpression).apply;
    }
}