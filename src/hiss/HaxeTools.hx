package hiss;

import haxe.macro.Expr;
import haxe.macro.ExprTools;
import haxe.Constraints.Function;
import Reflect;

using StringTools;

#if sys
import sys.io.Process;
#elseif hxnodejs
import js.node.ChildProcess.spawnSync;
import js.node.Buffer;
import haxe.extern.EitherType;
#end

class HaxeTools {
    public static function callMethod(object:Dynamic, method:Dynamic, args:Array<Dynamic>, onError:(Dynamic) -> Void) {
        try {
            return Reflect.callMethod(object, method, args);
        } catch (err:Dynamic) {
            trace(err);
            onError(err);
            return null;
        }
    }

    public static macro function extract(value:ExprOf<EnumValue>, pattern:Expr, ?hint:ExprOf<String>):Expr {
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

    public static function print(str:String) {
        #if (sys || hxnodejs)
        Sys.print(str);
        #else
        trace(str); // TODO this will have an unwanted newline
        #end
    }

    public static function println(str:String) {
        #if (sys || hxnodejs)
        Sys.println(str);
        #else
        trace(str);
        #end
    }

    public static function shellCommand(cmd:String):String {
        #if sys
        var process = new Process(cmd);
        if (process.exitCode() != 0) {
            var message = process.stderr.readAll().toString();
            throw 'Shell command error from `$cmd`: $message';
        }

        var result = process.stdout.readAll();
        process.close();

        return result.toString().trim();
        #else
        throw "Can't run shell command on non-sys platform.";
        #end
    }
}
