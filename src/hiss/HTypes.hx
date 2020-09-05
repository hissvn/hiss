package hiss;

@:using(hiss.HissTools)
enum HValue {
    // Atoms used to be their own nested enum, but this way is better.
    Int(value: Int);
    Float(value: Float);
    Symbol(name: String);
    
    // Internal type for a string literal that hasn't been interpolated yet
    InterpString(value: String);
    String(value: String);

    Nil;
    T;

    List(l: HList);
    Dict(n: HDict);
    Function(f: HFunction, name: String, ?args: Array<String>);
    Macro(f: HFunction, name: String);
    SpecialForm(f: HFunction, name: String);
    // If you're going to store arbitrary objects in Hiss variables, do yourself a favor and give them a descriptive label because Haxe runtime type info can be squirrely on different platforms
    Object(t: String, v: Dynamic);

    Quote(exp: HValue);

    // Backend-only types. These are used internally but never returned by the interpreter
    Quasiquote(exp: HValue);
    Unquote(exp: HValue);
    UnquoteList(exp: HValue);

    Comment;
}

typedef Continuation = (HValue) -> Void;

typedef HFunction = (HValue, HValue, Continuation) -> Void;

enum HSignal {
    Quit;
}

typedef HList = Array<HValue>;

class RefBool {
    public var b: Bool = false;
    public function new() { }
}