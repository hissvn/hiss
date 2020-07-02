package hiss;

using hiss.HaxeTools;
import haxe.macro.Expr;
import haxe.macro.Context;

import hiss.HaxeTools;

class CompileInfo {
    /**
        Based on https://code.haxe.org/category/macros/add-git-commit-hash-in-build.html
        but with bells and whistles for a nice Hiss versioning convention
    **/
    public static macro function version(): ExprOf<String> {
        #if (!display && sys)
            var hissVersion = "";
            try {
                var branch = HaxeTools.shellCommand("git branch --show-current");
                var untrackedFiles = HaxeTools.shellCommand("git ls-files -o --exclude-standard");
                var diff = HaxeTools.shellCommand("git diff | head -c1");
                var revision = HaxeTools.shellCommand("git rev-list --count HEAD");
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