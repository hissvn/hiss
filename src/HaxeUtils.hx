package;

import haxe.macro.Expr;

class HaxeUtils {
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
}