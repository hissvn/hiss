package hiss;

import haxe.macro.Expr;

import hiss.HTypes;

class HissTools {
    public static function put(dict: HValue, key: String, v: HValue) {
        dict.toDict()[key] = v;
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

            default: 
                throw 'Not clear why $v is being converted to string';
        }
    }
}