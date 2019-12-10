@:using(HissTools.HissTools)
enum HAtom {
    Int(value: Int);
    Float(value: Float);
    Symbol(name: String);
    String(value: String);
}

@:using(HissTools.HissTools, HissInterp.HissInterp)
enum HValue {
    Atom(a: HAtom);
    List(l: HList);
    Quote(exp: HValue);
    Quasiquote(exp: HValue);
    Unquote(exp: HValue);
    // If you're going to store arbitrary objects in Hiss variables, do yourself a favor and give them a descriptive label because Haxe runtime type info can be squirrely on different platforms
    Object(t: String, v: Dynamic);
    Function(f: HFunction);
    Map(n: HMap);
    VarInfo(i: HVarInfo);
    Error(m: String);
    Nil;
    T;
    Comment;
}

enum HArgType {
    Fixed;
    Var;
}

@:using(HissTools.HissTools)
enum HFunction {
    Haxe(t: HArgType, f: Dynamic);
    Hiss(f: HFunDef);
    Macro(evalResult: Bool, f: HFunction);
}

typedef HMap = Map<String, HValue>;

typedef HFunDef = {
    var argNames: Array<String>;
    var body: HList;
}

typedef HVarInfo = {
    var name: String;
    var value: HValue;
    var container: Null<HMap>;
}

typedef HList = Array<HValue>;