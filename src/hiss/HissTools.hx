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

    public static function toPrint(v: HValue): String {
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
                var valueStr = "";
                for (v in l) {
                    valueStr += v.toPrint() + ' ';
                }
                valueStr = valueStr.substr(0, valueStr.length - 1); // no trailing space
                '(${valueStr})';
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
                '${[for (k => v in hdict) '$k => ${v.toPrint()}, ']}';
            case VarInfo(hvi):
                //trace(hvi);
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
                //trace(name);
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

    public static function unwrapList(hl: HValue): Array<Dynamic> {
        return [for (v in hl.toList()) HissTools.valueOf(v)];
    }

    /**
     * Behind the scenes function to HaxeTools.extract a haxe-compatible value from an HValue
     **/
     public static function valueOf(hv: HValue): Dynamic {
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
                [for (hvv in l) HissTools.valueOf(hvv)];
            case Dict(d):
                d;
            default: 
                hv;
                /*throw 'hvalue $hv cannot be unwrapped for a native Haxe operation';*/
        }
    }
}