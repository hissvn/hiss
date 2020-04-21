package hiss;

@:using(hiss.HissTools.HissTools)
enum HAtom {
    Int(value: Int);
    Float(value: Float);
    Symbol(name: String);
    String(value: String);
}

@:using(hiss.HissTools.HissTools, hiss.HissInterp.HissInterp)
enum HValue {
    Atom(a: HAtom);
    List(l: HList);
    Quote(exp: HValue);
    Quasiquote(exp: HValue);
    Unquote(exp: HValue);
    // If you're going to store arbitrary objects in Hiss variables, do yourself a favor and give them a descriptive label because Haxe runtime type info can be squirrely on different platforms
    Object(t: String, v: Dynamic);
    Function(f: HFunction);
    Dict(n: HDict);
    VarInfo(i: HVarInfo);
    Signal(s: HSignal);
    Nil;
    T;
    Comment;
}

enum HSignal {
    Error(m: String);
    Return(v: HValue);
    Break;
    Continue;
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