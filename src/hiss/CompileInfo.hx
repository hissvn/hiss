package hiss;

using StringTools;
using hiss.HaxeTools;
import haxe.macro.Expr;
import haxe.macro.Context;
#if sys
import sys.io.Process;
#end

class CompileInfo {
    static function shellCommand(cmd: String) {
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

    /**
        Based on https://code.haxe.org/category/macros/add-git-commit-hash-in-build.html
        but with bells and whistles for a nice Hiss versioning convention
    **/
    public static macro function version(): ExprOf<String> {
        #if (!display && sys)
            var hissVersion = "";
            try {
                var branch = shellCommand("git branch --show-current");
                var untrackedFiles = shellCommand("git ls-files -o --exclude-standard");
                var diff = shellCommand("git diff | head -c1");
                var revision = shellCommand("git rev-list --count HEAD");
                var hissVersion = '$branch-$revision';
                if ((diff + untrackedFiles).length > 0) {
                    hissVersion += '*';
                }
                return macro $v{hissVersion};
            } catch (err: Dynamic) {
                trace(err);
                return macro $v{"ERROR GETTING VERSION"};
            }
        #else
            return macro $v{"CAN'T GET VERSION ON THIS TARGET"};
        #end
    }
}