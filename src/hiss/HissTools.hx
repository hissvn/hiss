package hiss;

import haxe.macro.Expr;

import hiss.HaxeTools;
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

    public static function toHaxeString(hv: HValue): String {
        return HaxeTools.extract(hv, String(s) => s, "string");
    }

    public static function toInt(v: HValue): Int {
        return HaxeTools.extract(v, Int(i) => i, "int");
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

    // Can't be ported because the Haxe reflection API allows array indexing
    public static function nth(list: HValue, idx: HValue):HValue {
        return list.toList()[idx.toInt()];
    }
    
    public static function setNth(arr: HValue, idx: HValue, val: HValue) { 
        arr.toList()[idx.toInt()] = val; return arr;
    }


    public static function symbolName(v: HValue): HValue {
        return String(HaxeTools.extract(v, Symbol(name) => name, "symbol name"));
    }

    // Since the variadic binop macro uses cons and it's one of the first
    // things in the Hiss prelude, might as well let this one stand as a Haxe function.
    public static function cons(hv: HValue, hl: HValue): HValue {
        var l = hl.toList().copy();
        l.insert(0, hv);
        return List(l);
    }

    // This one can't be pure Hiss because we can't instantiate a Map with a type parameter using reflection:
    static function emptyDict() {
        return Dict([]);
    }

    // TODO It's possible eq could be re-implemented in Hiss now
    public static function eq(a: HValue, b: HValue): HValue {
        if (Type.enumIndex(a) != Type.enumIndex(b)) {
            return Nil;
        }
        switch (a) {
            case Int(_) | String(_) | Symbol(_) | Float(_)  | T | Nil:
                return if (Type.enumEq(a, b)) T else Nil;
            case List(_):
                var l1 = a.toList();
                var l2 = b.toList();
                if (l1.length != l2.length) return Nil;
                var i = 0;
                while (i < l1.length) {
                    if (!HissTools.truthy(eq(l1[i], l2[i]))) return Nil;
                    i++;
                }
                return T;
            case Quote(aa) | Quasiquote(aa) | Unquote(aa) | UnquoteList(aa):
                var bb = HaxeTools.extract(b, Quote(e) | Quasiquote(e) | Unquote(e) | UnquoteList(e) => e);
                return eq(aa, bb);
            default:
                return Nil;
        }
    }

    static var recursivePrintDepth = 5;
    public static function toPrint(v: HValue, recursiveCall: Int = 0): String {
        return switch (v) {
            case Int(i):
                Std.string(i);
            case Float(f):
                Std.string(f);
            case Symbol(name):
                name;
            case String(str):
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
            case Error(m):
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
        are contained in keepWrapped, an optional list or T/Nil value.
    **/
    public static function unwrapList(hl: HValue, keepWrapped: HValue = Nil): Array<Dynamic> {
        var indices: Array<Dynamic> = if (keepWrapped == Nil) {
            [];
        } else if (keepWrapped == T) {
            [for (i in 0... hl.toList().length) i];
        } else {
            unwrapList(keepWrapped); // This looks like a recursive call but it's not. It's unwrapping the list of indices!
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
            //case Int(i) if (i == 0): false; /* 0 being falsy will be useful for Hank read-counts */
            case List(l) if (l.length == 0): false;
            case Error(m): false;
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
                    [for (hvv in l) HissTools.valueOf(hvv, true)]; // So far it seems that nested list elements should stay wrapped
                }
            case Dict(d):
                d;
            default: 
                hv;
                /*throw 'hvalue $hv cannot be unwrapped for a native Haxe operation';*/
        }
    }
}