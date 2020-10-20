package hiss.wrappers;

import sys.io.File;

// Wraps functions from the Haxe File API that are required on all Hiss targets.
class HFile {
    public static function getContent(path:String):String {
        return File.getContent(path);
    }

    public static function saveContent_d(path:String, content: String):Void {
        File.saveContent(path, content);
    }
}