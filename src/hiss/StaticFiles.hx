package hiss;

class StaticFiles {
    static var files: Map<String, String> = new Map<String, String>();
    
    public static function registerFileContent(path: String, content: String) {
        files[path] = content;
    }

    public static macro function compileWith(file: String) {
        var content = sys.io.File.getContent(file);
        return macro StaticFiles.registerFileContent($v{file}, $v{content});
    }

    public static function getContent(path: String) {
        return files[path];
    }
}