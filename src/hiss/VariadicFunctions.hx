package hiss;

import hiss.HTypes;
using hiss.HissTools;
using hiss.Stdlib;

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

    public static function add(interp: CCInterp, args: HValue, env: HValue, cc: Continuation) {
        var sum:Dynamic = switch (args.first()) {
            case Int(_): 0;
            case Float(_): 0;
            case String(_): "";
            case List(_): [];
            default: throw 'Cannot perform addition with operands: ${args.toPrint()} because first element is  ${Type.enumConstructor(args.first())}';
        };
        var addNext: (Dynamic)->Void = switch (args.first()) {
            case Int(_) | Float(_) | String(_): (i) -> sum += i;
            case List(_): (i) -> sum = sum.concat(i);
            default: null; // The error should already have been thrown.
        }
        for (i in args.unwrapList(interp)) {
            addNext(i);
        }
        cc(HissTools.toHValue(sum));
    }

    public static function subtract(interp: CCInterp, args: HValue, env: HValue, cc: Continuation) {
        switch (args.length_h()) {
            case 0: cc(Int(0));
            case 1: cc(HissTools.toHValue(0 - args.first().value(interp)));
            default:
                var first: Dynamic = args.first().value(interp);
                for (val in args.rest().unwrapList(interp)) {
                    first -= val;
                }
                cc(HissTools.toHValue(first));
        }
        
    }

    public static function divide(interp: CCInterp, args: HValue, env: HValue, cc: Continuation) {
        switch (args.length_h()) {
            case 0: throw "Can't divide without operands";
            case 1: cc(HissTools.toHValue(1 / args.first().value(interp)));
            default:
                var first: Dynamic = args.first().value(interp);
                for (val in args.rest().unwrapList(interp)) {
                    first /= val;
                }
                cc(HissTools.toHValue(first));
        }
    }

    public static function multiply(interp: CCInterp, args: HValue, env: HValue, cc: Continuation) {
        switch (args.first()) {
            case Int(_) | Float(_):
                var product: Dynamic = 1;
                var operands = args.unwrapList(interp);

                switch (args.last()) {
                    case List(_) | String(_):
                        multiply(interp, operands[operands.length-1].toHValue().cons(operands.slice(0, operands.length-1).toHList()), env, cc);
                        return;
                    default:
                }
                for (val in operands) {
                    product *= val;
                }
                cc(HissTools.toHValue(product));
            case String(str):
                var product = "";
                var toRepeat = args.first().toHaxeString();
                var times = args.second().toInt();
                for (i in 0...times) {
                    product += toRepeat;
                }
                if (args.length_h() == 2) {
                    cc(String(product));
                } else {
                    multiply(interp, String(product).cons(args.slice(2)), env, cc);
                }
            case List(l):
                var product = [];
                var toRepeat = args.first().toList();
                var times = args.second().toInt();
                for (i in 0...times) {
                    product = product.concat(toRepeat);
                }
                if (args.length_h() == 2) {
                    cc(List(product));
                } else {
                    multiply(interp, List(product).cons(args.slice(2)), env, cc);
                }
            default: throw 'Cannot multiply with first operand ${args.first().toPrint()}';
        }
    }

    public static function numCompare(interp: CCInterp, type: Comparison, args: HValue, env: HValue, cc: Continuation) {
        switch (args.length_h()) {
            case 0: throw "Can't compare without operands";
            case 1: cc(T);
            default:
                var leftSide: Dynamic = args.first().value(interp);
                for (val in args.rest().unwrapList(interp)) {
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