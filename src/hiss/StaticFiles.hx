package hiss;

import haxe.io.Path;
import haxe.macro.Context;
#if (sys || hxnodejs)
import sys.io.File;
import sys.FileSystem;
#end

using StringTools;

class StaticFiles {
    static var files:Map<String, String> = new Map();
    static var groups:Map<String, Array<String>> = new Map();

    // These underscore functions are public because they have to be. You shouldn't use them
    public static function _registerFileContent(path:String, content:String) {
        files[path] = content;
    }

    public static function _registerFileWithGroup(path:String, group:String) {
        if (!groups.exists(group))
            groups[group] = [];
        groups[group].push(path);
    }

    public static macro function compileWith(file:String, directory:String = "") {
        // Search for the file relative to module root.
        var posInfos = Context.getPosInfos(Context.currentPos());
        if (directory.length == 0)
            directory = FileSystem.absolutePath(Path.directory(posInfos.file));
        #if sys
        var content = File.getContent(Path.join([directory, file]));
        #else
        var content = "";
        #end
        return macro StaticFiles._registerFileContent($v{file}, $v{content});
    }

    public static macro function compileWithAll(directory:String) {
        var posInfos = Context.getPosInfos(Context.currentPos());
        var dir = FileSystem.absolutePath(Path.directory(posInfos.file));
        var files = recursiveLoop(Path.join([dir, directory]));
        files = [for (file in files) file.replace(dir + "/", "")];

        var exprs = [];
        for (file in files) {
            exprs.push(macro StaticFiles.compileWith($v{file}, $v{dir}));
            exprs.push(macro StaticFiles._registerFileWithGroup($v{file}, $v{directory}));
        }

        return macro $b{exprs}
    }

    public static function getContent(path:String) {
        if (files.exists(path)) {
            return files[path];
        } else {
            #if (sys || hxnodejs)
            return File.getContent(path);
            #end
            throw 'File was not compiled into the program: $path';
        }
    }

    public static function getDirectoryFiles(directory:String) {
        return groups[directory];
    }

    /** 
        this function is nabbed from https://code.haxe.org/category/beginner/using-filesystem.html

        It returns an array of every file path in the given directory (searched recursively)
    **/
    static function recursiveLoop(directory:String, ?files:Array<String>):Array<String> {
        if (files == null)
            files = [];
        #if sys
        if (sys.FileSystem.exists(directory)) {
            // trace("directory found: " + directory);
            for (file in sys.FileSystem.readDirectory(directory)) {
                if (file.startsWith("."))
                    continue; // Avoid stat errors on Emacs and vim swap files ¯\_(ツ)_/¯
                var path = haxe.io.Path.join([directory, file]);
                if (!sys.FileSystem.isDirectory(path)) {
                    // trace("file found: " + path);
                    // do something with file
                    files.push(path.toString());
                } else {
                    var directory = haxe.io.Path.addTrailingSlash(path);
                    // trace("directory found: " + directory);
                    files = recursiveLoop(directory, files);
                }
            }
        } else {
            // trace('"$directory" does not exist');
        }
        #end

        return files;
    }
}
