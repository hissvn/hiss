package hiss;

import hiss.HTypes;
using hiss.HissTools;


enum Comparison {
    Lesser;
    LesserEqual;
    Greater;
    GreaterEqual;
    Equal;
}

/**
    Variadic operations that used to be fun and DRY, but are efficient now instead
**/
class VariadicFunctions {
    public static function append(args: HValue, env: HValue, cc: Continuation) {
        var result = args.first().toList();
        for (l in args.rest().toList()) {
            result = result.concat(l.toList());
        }
        cc(List(result));
    }

    public static function add(args: HValue, env: HValue, cc: Continuation) {
        var sum:Dynamic = switch (args.first()) {
            case Int(_): 0;
            case Float(_): 0;
            case String(_): "";
            default: throw 'Cannot perform addition with operands: ${args.toPrint()} because first element is  ${Type.enumConstructor(args.first())}';
        };
        for (i in args.unwrapList()) {
            sum += i;
        }
        cc(HissTools.toHValue(sum));
    }

    public static function subtract(args: HValue, env: HValue, cc: Continuation) {
        switch (args.length()) {
            case 0: cc(Int(0));
            case 1: cc(HissTools.toHValue(0 - args.first().value()));
            default:
                var first: Dynamic = args.first().value();
                for (val in args.rest().unwrapList()) {
                    first -= val;
                }
                cc(HissTools.toHValue(first));
        }
        
    }

    public static function divide(args: HValue, env: HValue, cc: Continuation) {
        switch (args.length()) {
            case 0: throw "Can't divide without operands";
            case 1: cc(HissTools.toHValue(1 / args.first().value()));
            default:
                var first: Dynamic = args.first().value();
                for (val in args.rest().unwrapList()) {
                    first /= val;
                }
                cc(HissTools.toHValue(first));
        }
    }

    public static function multiply(args: HValue, env: HValue, cc: Continuation) {
        switch (args.length()) {
            case 0: cc(Int(0));
            default:
                var first: Dynamic = 1;
                for (val in args.rest().unwrapList()) {
                    first *= val;
                }
                cc(HissTools.toHValue(first));
        }
    }

    public static function numCompare(type: Comparison, args: HValue, env: HValue, cc: Continuation) {
        switch (args.length()) {
            case 0: throw "Can't compare without operands";
            case 1: cc(T);
            default:
                var leftSide: Dynamic = args.first().value();
                for (val in args.rest().unwrapList()) {
                    var rightSide: Dynamic = val;
                    var pass = switch (type) {
                        case Lesser:
                            leftSide < rightSide;
                        case LesserEqual:
                            leftSide <= rightSide;
                        case Greater:
                            leftSide > rightSide;
                        case GreaterEqual:
                            leftSide >= rightSide;
                        case Equal:
                            leftSide == rightSide;
                    }
                    if (pass) {
                        leftSide = rightSide;
                    } else {
                        cc(Nil);
                        return;
                    }
                }

                cc(T);
        }
    }
}