package hiss;

import haxe.CallStack;
import hiss.HaxeTools;

using hiss.HaxeTools;

import hiss.HTypes;
import hiss.CompileInfo;
import Type;
import Reflect;

using hiss.HissTools;

import hiss.HDict;
import hiss.Stdlib;

using hiss.Stdlib;

/**
    Useful functions for HValues that don't get imported to the Hiss standard library
**/
@:expose
class HissTools {
    // These dictionary functions are for Haxe usage and are more ergonomic with string args,
    // although the underlying keys will be HValues:
    public static function get(dict:HValue, key:String) {
        return dict.toDict().get_h(Symbol(key));
    }

    public static function exists(dict:HValue, key:String) {
        return dict.toDict().exists_h(Symbol(key));
    }

    public static function put(dict:HValue, key:String, v:HValue) {
        dict.toDict().put_hd(Symbol(key), v);
        return dict;
    }

    public static function toList(list:HValue, hint:String = "list"):HList {
        return HaxeTools.extract(list, List(l) => l, "list");
    }

    public static function toObject(obj:HValue, ?hint:String = "object"):Dynamic {
        return HaxeTools.extract(obj, Object(_, o) => o, "object");
    }

    public static function toCallable(f:HValue, hint:String = "function"):HFunction {
        return HaxeTools.extract(f, Function(hf, _) | Macro(hf, _) | SpecialForm(hf, _) => hf, hint);
    }

    public static function toHaxeString(hv:HValue):String {
        return HaxeTools.extract(hv, String(s) => s, "string");
    }

    public static function toInt(v:HValue):Int {
        return HaxeTools.extract(v, Int(i) => i, "int");
    }

    public static function toFloat(v:HValue):Float {
        return switch (v) {
            case Float(f): f;
            case Int(i): i;
            default: throw 'can\'t extract float from $v';
        };
    }

    public static function toHFunction(hv:HValue):HFunction {
        return HaxeTools.extract(hv, Function(f, _) => f, "function");
    }

    public static function toDict(dict:HValue):HDict {
        return HaxeTools.extract(dict, Dict(h) => h, "dict");
    }

    public static function first(list:HValue):HValue {
        return list.toList()[0];
    }

    public static function second(list:HValue):HValue {
        return list.toList()[1];
    }

    public static function third(list:HValue):HValue {
        return list.toList()[2];
    }

    public static function fourth(list:HValue):HValue {
        return list.toList()[3];
    }

    public static function last(list:HValue):HValue {
        return list.nth_h(Int(list.length_h() - 1));
    }

    public static function slice(list:HValue, idx:Int) {
        return List(list.toList().slice(idx));
    }

    public static function alternates(list:HValue, start:Bool) {
        var result = new Array<HValue>();
        var l = list.toList().copy();
        while (l.length > 0) {
            var next = l.shift();
            if (start)
                result.push(next);
            start = !start;
        }
        return List(result);
    }

    /**
        Return the first argument HDict extended with the keys and values of the second.
    **/
    public static function dictExtend(dict:HValue, extension:HValue) {
        var extended = dict.toDict().copy();
        for (pair in extension.toDict().keyValueIterator()) {
            extended.put_hd(pair.key, pair.value);
        }
        return Dict(extended);
    }

    public static function extend(env:HValue, extension:HValue) {
        return extension.cons_h(env);
    }

    public static function destructuringBind(names:HValue, interp:CCInterp, values:HValue) {
        var bindings = interp.emptyDict();

        switch (names) {
            case Symbol(name):
                // Destructuring bind is still valid with a one-value binding
                bindings.put(name, values);
            case List(l1):
                var l2 = values.toList();

                /*if (l1.length != l2.length) {
                    throw 'Cannot bind ${l2.length} values to ${l1.length} names';
                }*/

                for (idx in 0...l1.length) {
                    switch (l1[idx]) {
                        case List(nestedList):
                            bindings = bindings.dictExtend(destructuringBind(l1[idx], interp, l2[idx]));
                        case Symbol("&optional"):
                            var numOptionalValues = l1.length - idx - 1;
                            var remainingValues = l2.slice(idx);
                            while (remainingValues.length < numOptionalValues) {
                                remainingValues.push(Nil);
                            }
                            bindings = bindings.dictExtend(destructuringBind(List(l1.slice(idx + 1)), interp, List(remainingValues)));
                            break;
                        case Symbol("&rest"):
                            var remainingValues = l2.slice(idx);
                            bindings.put(l1[idx + 1].symbolName_h(), List(remainingValues));
                            break;
                        case Symbol(name):
                            bindings.put(name, l2[idx]);
                        default:
                            throw 'Bad element ${l1[idx]} in name list for bindings';
                    }
                }
            default:
                throw 'Cannot perform destructuring bind on ${names.toPrint()} and ${values.toPrint()}';
        }

        return bindings;
    }

    public static function toHValue(v:Dynamic, hint:String = "HValue"):HValue {
        if (v == null)
            return Nil;
        var t = Type.typeof(v);
        return switch (t) {
            case TInt:
                Int(v);
            case TFloat:
                Float(v);
            case TBool:
                if (v) T else Nil;
            case TClass(c):
                var name = Type.getClassName(c);
                return switch (name) {
                    case "String":
                        String(v);
                    case "Array":
                        var va = cast(v, Array<Dynamic>);
                        List([for (e in va) HissTools.toHValue(e)]);
                    case "hiss.HDict":
                        return Dict(v);
                    default:
                        Object(name, v);
                };
            case TEnum(e):
                var name = Type.getEnumName(e);
                switch (name) {
                    case "haxe.ds.Option":
                        return switch (cast(v, haxe.ds.Option<Dynamic>)) {
                            case Some(vInner): HissTools.toHValue(vInner);
                            case None: Nil;
                        }
                    case "hiss.HValue":
                        return cast(v, HValue);
                    default:
                        return Object(name, e);
                };
            case TObject:
                Object("!ANONYMOUS!", v);
            case TFunction:
                Object("NativeFun", v);
            default:
                throw 'value $v of type $t cannot be wrapped as $hint';
        }
    }

    /**
        Unwrap hvalues in a hiss list to their underlying types. Don't unwrap values whose indices
        are contained in keepWrapped, an optional list or T/Nil value.
    **/
    public static function unwrapList(hl:HValue, interp:CCInterp, keepWrapped:HValue = Nil):Array<Dynamic> {
        var indices:Array<Dynamic> = if (keepWrapped == Nil) {
            [];
        } else if (keepWrapped == T) {
            [for (i in 0...hl.toList().length) i];
        } else {
            unwrapList(keepWrapped, interp); // This looks like a recursive call but it's not. It's unwrapping the list of indices!
        }
        var idx = 0;
        return [
            for (v in hl.toList()) {
                if (indices.indexOf(idx++) != -1) {
                    v;
                } else {
                    v.value(interp);
                }
            }
        ];
    }

    public static function toHList(l:Array<Dynamic>):HValue {
        return List([for (v in l) v.toHValue()]);
    }

    /**
     * Behind the scenes function to HaxeTools.extract a haxe-compatible value from an HValue
    **/
    public static function value(hv:HValue, interp:CCInterp, reference:Bool = false):Dynamic {
        if (interp == null)
            trace(hv);
        if (hv == null)
            return Nil;
        return switch (hv) {
            case Nil | T:
                interp.truthy(hv);
            case Null: null;
            case Int(v):
                v;
            case Float(v):
                v;
            case String(v):
                v;
            case Object(_, v):
                v;
            case List(l):
                if (reference) {
                    l;
                } else {
                    [for (hvv in l) value(hvv, interp, true)]; // So far it seems that nested list elements should stay wrapped
                }
            case Dict(d):
                d;
            case Function(_, _):
                interp.toNativeFunction(hv);
            default:
                hv;
                /*throw 'hvalue $hv cannot be unwrapped for a native Haxe operation';*/
        }
    }

    public static function metadata(callable:HValue) {
        return HaxeTools.extract(callable, Function(_, meta) | Macro(_, meta) | SpecialForm(_, meta) => meta);
    }

    public static function toPrint(v:HValue) {
        return v.toPrint_h();
    }

    public static function toMessage(v:HValue) {
        return v.toMessage_h();
    }
}
