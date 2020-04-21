package;

import haxe.macro.Expr;
import haxe.macro.ExprTools;

class HaxeUtils {
    public static macro function extract(value:ExprOf<EnumValue>, pattern:Expr, ?hint: ExprOf<String>):Expr {
        switch (pattern) {
            case macro $a => $b:
                return macro switch ($value) {
                    case $a: $b;
                    default: 
                        var v = Std.string($value);
                        throw 'extraction to `' + $hint + '` failed on `' + v + '`';
                }
            default:
                throw new Error("Invalid enum value extraction pattern", pattern.pos);
        }
    }
}