package hiss.wrappers;

import Type;

// Wraps functions from the Haxe Type API that are required on all Hiss targets.
// Not to be confused with the file HTypes.hx, which is unrelated!
class HType {
    public static function createInstance(cl: Class<Dynamic>, args: Array<Dynamic>): Dynamic {
        return Type.createInstance(cl, args);
    }
}