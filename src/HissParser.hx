/* Modeled after this: https://github.com/deathbeam/parsihax/blob/74f2ac81ccd07d26278433c36f13172173ab6860/test/parsihax/LispGrammar.hx#L1 */

package;

using StringTools;

import parsihax.*;
import parsihax.Parser.*;
using parsihax.Parser;
using parsihax.ParseObject;

using HissParser;

enum HAtom {
 Int(value: Int);
 Double(value: Float);
 Symbol(name: String);
 String(value: String);
}

enum HExpression {
 Atom(a: HAtom);
 Cons(first: HExpression, rest: HExpression);
 List(exps: Array<HExpression>);
 ParseError(badToken: String);
}

class HissParser {
    public var parseString(default, null): ParseFunction<HExpression>;

    private static inline function trim(parser : ParseObject<String>) {
        return parser.skip(optWhitespace());
    }

    public function new() {
        var hissExpression: ParseObject<HExpression> = empty();

        var hissString = '"'.string().then(~/[^"]*/.regexp()).skip('"'.string()).trim()
            .map((r) -> HExpression.Atom(HAtom.String(r)))
            .as('string literal');

        var hissSymbol = ~/[a-zA-Z_-][a-zA-Z0-9_-]*/.regexp().trim()
            .map((r) -> HExpression.Atom(HAtom.Symbol(r)))
            .as('symbol');

        var hissInt = ~/[+-]?[1-9][0-9]*/.regexp().trim()
            .map((r) -> HExpression.Atom(HAtom.Int(Std.parseInt(r))))
            .as('integer literal');

        var hissDouble = ~/[+-]?[0-9]*\.[0-9]+/.regexp().trim()
            .map((r) -> HExpression.Atom(HAtom.Double(Std.parseFloat(r))))
            .as('double literal');

        // TODO this just doesn't want to work
        var hissCons = '('.string().trim()
            .then(sepBy(hissExpression, ~/\s+\.\s+/.regexp()))
            .skip(')'.string().trim())
            .map((r) -> { /*todo assert only 2 elements */trace(r); return HExpression.Cons(r[0], r[1]); })
            .as('cons cell');

        var hissList = '('.string().trim()
            .then(hissExpression.many())
            .skip(')'.string().trim())
            .map((r) -> HExpression.List(r));

        hissExpression.apply = [
            hissSymbol,
            hissInt,
            hissDouble,
            hissString,
            hissList,
            //hissCons,
        ].alt();

        parseString = optWhitespace().then(hissExpression).apply;
    }
}