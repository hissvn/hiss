package hiss;

import haxe.io.Path;
import haxe.macro.Context;
import sys.FileSystem;

class StaticFiles {
    static var files: Map<String, String> = new Map<String, String>();
    
    public static function registerFileContent(path: String, content: String) {
        files[path] = content;
    }

    public static macro function compileWith(file: String) {
        // Search for the file relative to module root.

        var posInfos = Context.getPosInfos(Context.currentPos());
        var directory = FileSystem.absolutePath(Path.directory(posInfos.file));
        var content = sys.io.File.getContent(Path.join([directory, file]));
        return macro StaticFiles.registerFileContent($v{file}, $v{content});
    }

    public static function getContent(path: String) {
        return files[path];
    }
}