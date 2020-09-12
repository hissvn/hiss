package hiss;

import haxe.macro.Expr;
import haxe.macro.ExprTools;

using StringTools;

#if sys
import sys.io.Process;
#elseif hxnodejs
import js.node.ChildProcess.spawnSync;
import js.node.Buffer;
import haxe.extern.EitherType;
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

    public static function shellCommand(cmd: String): String {
        #if sys
            var process = new Process(cmd);
            if (process.exitCode() != 0) {
                var message = process.stderr.readAll().toString();
                throw 'Shell command error from `$cmd`: $message';
            }

            var result = process.stdout.readAll();
            process.close();

            return result.toString().trim();
        // hxnodejs doesn't implement the Process class.
        #elseif hxnodejs
            function stringFromChildProcessOutput(output: EitherType<Buffer, String>): String {
                return try { 
                    cast(output, Buffer).toString();
                } catch (s: Dynamic) {
                    cast(output, String);
                };
            }

            // TODO file output redirection
            // To write to file, >> and > will need to manually call Haxe file operations.

            // TODO Also, &&, and || being ambiguous with the pipe, and nesting of parentheses, make this a headache.
            // This might literally be a case where we need to use reader macros in a clever way.

            // Making shell-command work with pipes and other shell features is more complicated than I thought.
            var input = "";
            var result = "";

            for (command in cmd.split("|")) {
                var parts = command.trim().split(" ");
                var bin = parts[0];
                var args = parts.slice(1);
                
                var options = if (input.length > 0) {
                    { "input": input };
                } else {
                    {};
                }

                var process = spawnSync(bin, args, options);

                if (process.error != null) {
                    throw 'child_process error from `$command`: ${process.error}';
                }

                if (process.status != 0) {
                    var message = stringFromChildProcessOutput(process.stderr);
                    throw 'Shell command error from `$command`: $message';
                }

                result = stringFromChildProcessOutput(process.stdout);
                input = result;
            }

            return result.trim();
        #else
            throw "Can't run shell command on non-sys platform.";
        #end
    }

    public static function readLine() {
        #if (sys || hxnodejs)
            return Sys.stdin().readLine();
        #else
            throw "Can't read input on non-sys platform.";
        #end
    }
}