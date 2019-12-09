import haxe.macro.Expr;

import HTypes;

class HissTools {
    public static macro function extract(value:ExprOf<EnumValue>, pattern:Expr):Expr {
        switch (pattern) {
            case macro $a => $b:
                return macro switch ($value) {
                    case $a: $b;
                    default: throw 'extraction failed';
                }
            default:
                throw new Error("Invalid enum value extraction pattern", pattern.pos);
        }
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
            case Function(Macro(f)):
                '[macro ${Function(f).toPrint()}]';
            case Error(m):
                '!$m!';
            case Nil:
                'nil';
            case T:
                't';
            /*
            case map
            case varinfo
            */

            case Quasiquote(e):
                return '`${e.toPrint()}';
            case Unquote(e):
                return ',${e.toPrint()}';

            default: 
                throw 'Not clear why $v is being converted to string';
        }
    }
}