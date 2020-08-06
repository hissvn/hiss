package hiss;

import haxe.macro.Expr;
import haxe.macro.ExprTools;

using StringTools;

#if sys
import sys.io.Process;
#end

class HaxeTools {
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

    public static function print(str: String) {
        #if (sys || hxnodejs)
            Sys.print(str);
        #else
            trace(str); // TODO this will have an unwanted newline
        #end
    }

    public static function println(str: String) {
        #if (sys || hxnodejs)
            Sys.println(str);
        #else
            trace(str);
        #end
    }

    public static function shellCommand(cmd: String) {
        // hxnodejs doesn't implement the Process class.
        #if sys
            var process = new Process(cmd);
            if (process.exitCode() != 0) {
                var message = process.stderr.readAll().toString();
                throw 'Shell command error from `$cmd`: $message';
            }

            var result = process.stdout.readAll();
            process.close();

            return result.getString(0, result.length).trim();
        #else
            return "Can't run shell command on non-sys platform.";
        #end
    }

    public static function readLine() {
        #if (sys || hxnodejs)
            return Sys.stdin().readLine();
        #else
            return "Can't read input on non-sys platform.";
        #end
    }
}