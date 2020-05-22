package hiss;

@:using(hiss.HissTools.HissTools)
enum HValue {
    // Atoms used to be their own nested enum, but this way is better.
    Int(value: Int);
    Float(value: Float);
    Symbol(name: String);
    String(value: String);

    Nil;
    T;

    List(l: HList);
    Dict(n: HDict);
    Function(f: HFunction);
    // If you're going to store arbitrary objects in Hiss variables, do yourself a favor and give them a descriptive label because Haxe runtime type info can be squirrely on different platforms
    Object(t: String, v: Dynamic);

    Quote(exp: HValue);

    Error(m: String);

    // Backend-only types. These are used internally but never returned by the interpreter
    Quasiquote(exp: HValue);
    Unquote(exp: HValue);
    UnquoteList(exp: HValue);
    VarInfo(i: HVarInfo);
    
    Return(v: HValue);
    Break;
    Continue;

    Comment;
}

enum HArgType {
    Fixed;
    Var;
}

@:using(HissTools.HissTools)
enum HFunction {
    Haxe(t: HArgType, f: Dynamic, name: String);
    Hiss(f: HFunDef);
    Macro(evalResult: Bool, f: HFunction);
}

typedef HDict = Map<String, HValue>;

typedef HFunDef = {
    var argNames: Array<String>;
    var body: HList;
}

typedef HVarInfo = {
    var name: String;
    var value: HValue;
    var container: Null<HDict>;
}

typedef HList = Array<HValue>;