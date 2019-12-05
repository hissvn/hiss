enum HAtom {
    Int(value: Int);
    Double(value: Float);
    Symbol(name: String);
    String(value: String);
}

enum HExpression {
    Atom(a: HAtom);
    Cons(first: HExpression, ?rest: HExpression);
    List(exps: Array<HExpression>);
    Quote(exp: HExpression);
    Quasiquote(exp: HExpression);
    Unquote(exp: HExpression);
}

enum ArgType {
    Fixed;
    Var;
}

enum HFunction {
    Haxe(t: ArgType, f: Dynamic);
    Hiss(f: FunDef);
    Macro(f: HFunction);
}

typedef FunDef = {
    var argNames: Array<String>;
    var body: ExpList;
}

typedef VarInfo = {
    var value: Dynamic;
    var scope: Dynamic;
}

typedef HissList = Array<Dynamic>;
typedef ExpList = Array<HExpression>;