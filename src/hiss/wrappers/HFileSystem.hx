package hiss.wrappers;

import sys.FileSystem;

// Wraps functions from the Haxe FileSystem API that are required on all Hiss targets.
class HFileSystem {
    public static var absolutePath = FileSystem.absolutePath;
    public static var createDirectory_d = FileSystem.createDirectory;
    public static var deleteDirectory_d = FileSystem.deleteDirectory;
    public static var deleteFile_d = FileSystem.deleteFile;
    public static var exists = FileSystem.exists;
    public static var fullPath = FileSystem.fullPath;
    public static var isDirectory = FileSystem.isDirectory;
    public static var readDirectory = FileSystem.readDirectory;
    public static var rename_d = FileSystem.rename;
}
