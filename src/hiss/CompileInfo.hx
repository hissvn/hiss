package hiss;

using hiss.HaxeTools;

import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.io.Path;
import hiss.HaxeTools;

class CompileInfo {
    /**
        Based on https://code.haxe.org/category/macros/add-git-commit-hash-in-build.html
        but with bells and whistles for a nice Hiss versioning convention
    **/
    public static macro function version(): ExprOf<String> {
        #if !display
        var posInfos = Context.getPosInfos(Context.currentPos());
        var directory = Path.directory(posInfos.file);
        var branch = try {
            HaxeTools.shellCommand('cd "$directory" && git branch --show-current');
        } catch (err:Dynamic) {
            "[unknown branch]";
        }
        var revision = try {
            HaxeTools.shellCommand('cd "$directory" && git rev-list --count HEAD');
        } catch (err:Dynamic) {
            "[unknown revision#]";
        };
        var modified = try {
            if (HaxeTools.shellCommand('cd "$directory" && git status -s').length > 0) {
                "*";
            } else {
                "";
            }
        } catch (err:Dynamic) {
            "[unknown if modified]";
        }
        var target = Context.definedValue("target.name");
        if (target == "js") {
            #if hxnodejs
            target = "nodejs";
            #end
        }
        var hissVersion = '$branch-$revision$modified (target: $target)';
        return macro $v{hissVersion};
        #else
        return macro $v{""}; // Return empty string if running through a language server/in IDE
        #end
    }
}
