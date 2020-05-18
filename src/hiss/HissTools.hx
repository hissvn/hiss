package hiss;

import haxe.macro.Expr;

import hiss.HTypes;
import Type;

class HissTools {
    public static function put(dict: HValue, key: String, v: HValue) {
        dict.toDict()[key] = v;
    }

    public static function toList(list: HValue, hint: String = "list"): HList {
        return HaxeTools.extract(list, List(l) => l, "list");
    }

    public static function toObject(obj: HValue, ?hint: String = "object"): Dynamic {
        return HaxeTools.extract(obj, Object(_, o) => o, "object");
    }

    public static function toFunction(f: HValue, hint: String = "function"): Dynamic {
        return HaxeTools.extract(f, Function(Haxe(_, v, _)) => v, hint);
    }

    public static function toString(hv: HValue): String {
        return HaxeTools.extract(hv, Atom(String(s)) => s, "string");
    }

    public static function toInt(v: HValue): Int {
        return HaxeTools.extract(v, Atom(Int(i)) => i, "int");
    }

    public static function toHFunction(hv: HValue): HFunction {
        return HaxeTools.extract(hv, Function(f) => f, "function");
    }

    public static function toDict(dict: HValue): HDict {
        return HaxeTools.extract(dict, Dict(h) => h, "dict");
    }

    public static function first(list: HValue): HValue {
        return list.toList()[0];
    }

    public static function rest(list: HValue): HValue {
        return List(list.toList().slice(1));
    }

    public static function nth(list: HValue, idx: HValue):HValue {
        return list.toList()[idx.toInt()];
    }

    static var recursivePrintDepth = 3;
    public static function toPrint(v: HValue, recursiveCall: Int = 0): String {
        return switch (v) {
            case Atom(Int(i)):
                Std.string(i);
            case Atom(Float(f)):
                Std.string(f);
            case Atom(Symbol(name)):
                name;
            case Atom(String(str)):
                '"$str"';
            case List(l):
                if (recursiveCall > recursivePrintDepth) {
                    "STACK OVERFLOW DANGER";
                } else {
                    var valueStr = "";
                    for (v in l) {
                        valueStr += v.toPrint(recursiveCall+1) + ' ';
                    }
                    valueStr = valueStr.substr(0, valueStr.length - 1); // no trailing space
                    '(${valueStr})';
                };
            case Quote(e):
                "'" + e.toPrint();
            case Object(t, o):
                '[$t: ${Std.string(o)}]';
            case Function(Haxe(_, _)):
                '[hxfunction]';
            case Function(Hiss(f)):
                '[hissfunction ${f.argNames}]';
            case Function(Macro(e,f)):
                '[${if (!e) "special " else ""}macro ${Function(f).toPrint()}]';
            case Signal(Error(m)):
                '!$m!';
            case Nil:
                'nil';
            case T:
                't';
            case Dict(hdict):
                if (recursiveCall > recursivePrintDepth) {
                    "STACK OVERFLOW DANGER";
                } else {
                    '${[for (k => v in hdict) '$k => ${v.toPrint(recursiveCall+1)}, ']}';
                }
            case VarInfo(hvi):
                var container = if (hvi.container != null) Std.string(hvi.container) else "null";
                '{name: ${hvi.name}, value: ${hvi.value.toPrint()}, container: $container}';
            case Quasiquote(e):
                return '`${e.toPrint()}';
            case Unquote(e):
                return ',${e.toPrint()}';
            case UnquoteList(e):
                return ',@${e.toPrint()}';

            default: 
                throw 'Not clear why $v is being converted to string';
        }
    }

    public static function toHValue(v: Dynamic, hint:String = "HValue"): HValue {
        if (v == null) return Nil;
        var t = Type.typeof(v);
        return switch (t) {
            case TNull:
                Nil;
            case TInt:
                Atom(Int(v));
            case TFloat:
                Atom(Float(v));
            case TBool:
                if (v) T else Nil;
            case TClass(c):
                var name = Type.getClassName(c);
                return switch (name) {
                    case "String":
                        Atom(String(v));
                    case "Array":
                        var va = cast(v, Array<Dynamic>);
                        List([for (e in va) HissTools.toHValue(e)]);
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
                        return cast (v, HValue);
                    case "hiss.HAtom":
                        return Atom(v);
                    default:
                        return Object(name, e);
                };
            case TObject:
                Object("!ANONYMOUS!", v);
            case TFunction:
                Function(Haxe(Fixed, v, "[wrapped-function]"));
            
            default:
                throw 'value $v of type $t cannot be wrapped as $hint';
        }
    }

    /**
        Unwrap hvalues in a hiss list to their underlying types. Don't unwrap values whose indices
        are contained in keepWrapped, an optional list.
    **/
    public static function unwrapList(hl: HValue, keepWrapped: HValue = Nil): Array<Dynamic> {
        var indices: Array<Dynamic> = if (keepWrapped == Nil) {
            [];
        } else if (keepWrapped == T) {
            [for (i in 0... hl.toList().length) i];
        } else {
            unwrapList(keepWrapped);
        }
        var idx = 0;
        return [for (v in hl.toList()) {
            if (indices.indexOf(idx++) != -1) {
                v;
            } else {
                HissTools.valueOf(v);
            }
        }];
    }

    /**
     * Behind the scenes, this function evaluates the truthiness of an HValue
     **/
     public static function truthy(cond: HValue): Bool {
        return switch (cond) {
            case Nil: false;
            //case Atom(Int(i)) if (i == 0): false; /* 0 being falsy will be useful for Hank read-counts */
            case List(l) if (l.length == 0): false;
            case Signal(Error(m)): false;
            default: true;
        }
    }

    /**
     * Behind the scenes function to HaxeTools.extract a haxe-compatible value from an HValue
     **/
     public static function valueOf(hv: HValue, reference: Bool = false): Dynamic {
        return switch (hv) {
            case Nil: false;
            case T: true;
            case Atom(Int(v)):
                v;
            case Atom(Float(v)):
                v;
            case Atom(String(v)):
                v;
            case Object(_, v):
                v;
            case List(l):
                if (reference) {
                    l;
                } else {
                    [for (hvv in l) HissTools.valueOf(hvv)];
                }
            case Dict(d):
                d;
            default: 
                hv;
                /*throw 'hvalue $hv cannot be unwrapped for a native Haxe operation';*/
        }
    }
}