package;

import Reflect;
import Type;

import HissParser;
import HissFunction;

typedef VarInfo = {
    var value: Dynamic;
    var scope: Dynamic;
}

class HissInterp {
    public var variables: Map<String, Dynamic> = [];
    private var scopes: Array<Dynamic> = [];

    public function new() {
        // The hiss standard library:
        variables['nil'] = null;
        variables['null'] = null;
        variables['trace'] = Sys.println;
        // TODO make arithmetic functions vararg list-eaters
        variables['+'] = (a, b) -> a + b;
        variables['-'] = (a, b) -> a - b;
        variables['*'] = (a, b) -> a * b;
        variables['/'] = (a, b) -> a / b;
        variables['floor'] = Math.floor;
    }

    public function haxeFuncall(fun: String, args: Dynamic) {

    }

    public function hissFuncall() {

    }

    public function resolve(name: String): VarInfo {
        var idx = scopes.length-1;
        while (idx >= 0) {
            var scope = scopes[idx--];
            var potentialValue = Reflect.getProperty(scope, name);
            if (potentialValue != null) {
                return { value: potentialValue, scope: scope };
            }
        }

        return { value: variables[name], scope: null };
    }

    public function eval(expr: HExpression, returnScope: Bool = false): Dynamic {
        switch (expr) {
            case Atom(a):
                switch (a) {
                    case Int(v):
                        return v;
                    case Double(v):
                        return v;
                    case String(v):
                        return v;
                    case Symbol(v):
                        var varInfo = resolve(v);
                        if (returnScope) {
                            return varInfo;
                        } else {
                            return varInfo.value;
                        }
                }
            case List(exps):
                var funcInfo = eval(exps[0], true);

                switch (Type.typeof(funcInfo.value)) {
                    case TClass(c) /*if (c == Class<HissFunction>)*/:
                        trace("eval hiss function");
                        return null;
                    case TFunction:
                        return Reflect.callMethod(funcInfo.scope, funcInfo.value, [for (argExp in exps.slice(1)) eval(argExp)]);
                    default:
                        trace("The expression provided is not a function");
                }

                //Reflect.callMethod()

                //return eval(cons);
                return null;
            case Quote(exp):
                return exp;
            case Quasiquote(HExpression.List(exps)):
                var afterEvalUnquotes = exps.map((exp) -> switch (exp) {
                    case HExpression.Unquote(innerExp):
                        return eval(innerExp);
                    default:
                        return exp;
                });
                return HExpression.List(afterEvalUnquotes);
            case Quasiquote(exp):
                return exp;
            default:
                return "Eval for that type is not yet implemented";
        }
    }
}