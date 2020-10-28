package hiss;

using hx.strings.Strings;

@:using(hiss.HissTools)
enum HValue {
    // Atoms used to be their own nested enum, but this way is better.
    Int(value:Int);
    Float(value:Float);
    Symbol(name:String);

    // Internal type for a string literal that hasn't been interpolated yet
    InterpString(value:String);
    String(value:String);
    Nil;
    Null;
    // yuck...
    T;
    List(l:HList);
    Dict(n:HDict);
    Function(f:HFunction, meta:CallableMeta);
    Macro(f:HFunction, meta:CallableMeta);
    SpecialForm(f:HFunction, meta:CallableMeta);
    // If you're going to store arbitrary objects in Hiss variables, do yourself a favor and give them a descriptive label because Haxe runtime type info can be squirrely on different platforms
    Object(t:String, v:Dynamic);
    Quote(exp:HValue);
    // Backend-only types. These are used internally but never returned by the interpreter
    Quasiquote(exp:HValue);
    Unquote(exp:HValue);
    UnquoteList(exp:HValue);
    Comment;
}

typedef CallableMeta = {
    var name:String;
    var ?docstring:String;
    var ?argNames:Array<String>;
    var ?deprecated:Bool;
    var ?async:Bool;
};

typedef ClassMeta = {
    var name:String;
    var ?omitMemberPrefixes:Bool;
    var ?omitStaticPrefixes:Bool;
    var ?convertNames:String->String;
    var ?getterPrefix:String;
    var ?setterPrefix:String;
    var ?sideEffectSuffix:String;
    var ?predicateSuffix:String;
    var ?conversionInfix:String;
};

class ClassMetaTools {
    public static function addDefaultFields(meta:ClassMeta) {
        if (meta.omitMemberPrefixes == null) {
            meta.omitMemberPrefixes = false;
        }
        if (meta.omitStaticPrefixes == null) {
            meta.omitStaticPrefixes = false;
        }
        // By default, convert names of functions and properties into the form name-to-lower-hyphen
        if (meta.convertNames == null) {
            meta.convertNames = Strings.toLowerHyphen;
        }

        if (meta.getterPrefix == null) {
            meta.getterPrefix = "get-";
        }
        if (meta.setterPrefix == null) {
            meta.setterPrefix = "set-";
        }
        if (meta.sideEffectSuffix == null) {
            meta.sideEffectSuffix = "!";
        }
        if (meta.predicateSuffix == null) {
            meta.predicateSuffix = "?";
        }
        if (meta.conversionInfix == null) {
            meta.conversionInfix = "->";
        }
    }
}

typedef Continuation = (HValue) -> Void;
typedef HFunction = (HValue, HValue, Continuation) -> Void;
typedef HList = Array<HValue>;

class RefBool {
    public var b:Bool = false;

    public function new() {}
}
