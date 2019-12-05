package;

import haxe.macro.Context;
import haxe.macro.Expr;
using haxe.macro.ExprTools;
using haxe.macro.Expr.Binop;

import sys.io.File;
import Reflect;
import Type;

import HissParser;
import HTypes;

using HissInterp;


class HissInterp {
    public var variables: Map<String, Dynamic> = [];
    private var scopes: Array<Dynamic> = [];

    // TODO import needs to turn camel case into lisp-case
    static function symbolName(symbol: HExpression): String {
        switch (symbol) {
            case HExpression.Atom(HAtom.Symbol(name)): return name;
            default: throw 'expected a symbol';
        };
    }

    // TODO optional docstrings lollll
    function defun(args: ExpList): HFunction {
        var name = symbolName(args[0]);

        var argNames = new Array<String>();
        switch (args[1]) {
            case HExpression.List(exps):
                for (argExp in exps) {
                    argNames.push(symbolName(argExp));
                }
            default: throw 'expected a list of arg names';
        }

        var expressions: ExpList = args.slice(2);
        var def: FunDef = { argNames: argNames, body: expressions};
        variables[name] = HFunction.Hiss(def);
        return variables[name];
    }

    public static macro function importFixed(f: Expr) {
        function findFunctionName(e:Expr) {
	        switch(e.expr) {
		        case EConst(CIdent(s)) | EField(_, s):
			        // handle s
                    return s;
		        case _:
			        throw 'improper expression for importing haxe function to interpreter';
            }
	    }
        var name = findFunctionName(f);
        //var name = "";
        return macro {
            variables[$v{name}] = HFunction.Haxe(ArgType.Fixed, $f);            
        };
    }

    public static macro function importBinops(prefix: Bool, rest: Array<ExprOf<String>>) {
        var block = [];
        for (e in rest) {
            var s = e.getValue();
            block.push(macro importBinop($v{s}, $v{prefix}));
        }
        return macro $b{block};
    }

    public static macro function importBinop(op: String, prefix: Bool) {
        var name = op;
        if (prefix) {
            name = 'haxe$name';
        }

        var code = 'variables["$name"] = HFunction.Haxe(ArgType.Fixed, (a,b) -> a $op b)';

        var expr = Context.parse(code, Context.currentPos());
        return expr;
    }

    public function new() {
        // The hiss standard library:
        variables['nil'] = null;
        variables['null'] = null;
        variables['true'] = true;
        variables['false'] = false;

        // Haxe std io
        importFixed(Sys.print);
        importFixed(Sys.println);
        
        // Haxe binops
        importFixed(HissParser.read);
        importFixed(eval);

        // Haxe math
        importFixed(Math.round);
        importFixed(Math.floor);
        importFixed(Math.ceil);

        // most haxe binary operators are non-binary (like me!) in most Lisps.
        // They can take any number of arguments.
        // Since we still need haxe to run the computations, Hiss imports those binary
        // operators, but hides them with the prefix 'haxe' to it can provide its own
        // lispy operator functions.
        importBinops(true, "+", "-", "/", "*", ">", ">=", "<", "<=");
        variables['haxe='] = HFunction.Haxe(ArgType.Fixed, (a, b) -> a == b); // = is for comparison by lisp conventions

        // Still more binary operators just don't exist in lisp because they are named functions like `and` or `or`
        importBinops(true, "&&", "||", "...");

        // Some binary operators are Lisp-compatible as-is
        importBinops(false, "%");  

        variables['defun'] = HFunction.Macro(HFunction.Haxe(ArgType.Var, defun));
    }

    public static function first(list: HissList): Dynamic {
        return list[0];
    }

    public static function rest(list: HissList): HissList {
        return list.slice(1);
    }

    function evalHissList(exps: Array<HExpression>): HissList {
        return [for (exp in exps) eval(exp)];
    }

    public function funcall(funcInfo: VarInfo, argExps: ExpList, evalArgs: Bool = true) {
        var args: ExpList = argExps;
        
        switch (funcInfo.value) {
            case Macro(func):
                var nestedInfo: VarInfo = { value: func, scope: funcInfo.scope };
                return funcall(nestedInfo, args, false);
            default:
                var argVals: HissList = argExps;
                if (evalArgs) {
                    argVals = evalHissList(argExps);
                }
                switch (funcInfo.value) {
                    case Haxe(t, func):
                        switch (t) {
                            case Var: argVals = [argVals];
                            case Fixed:
                        }
                        return Reflect.callMethod(funcInfo.scope, func, argVals);
            
                    case Hiss(funDef):
                        var oldScopes = scopes;

                        var argScope: Map<String, Dynamic> = [];
                        var idx = 0;
                        for (arg in funDef.argNames) {
                            argScope[arg] = argVals[idx++];
                        }

                        scopes = [argScope];
                        trace(argScope);
                        
                        var lastResult = null;
                        for (expression in funDef.body) {
                            lastResult = eval(expression);
                        }

                        scopes = oldScopes;

                        return lastResult;
                    default:
                        throw 'Nested macros?S?S?S?';
                }
        }
    }

    public function resolve(name: String): VarInfo {
        var idx = scopes.length-1;
        while (idx >= 0) {
            var scope = scopes[idx--];
            var potentialValue = Reflect.getProperty(scope, name);
            if (potentialValue != null) {
                return { value: potentialValue, scope: scope };
            }
            try {
                potentialValue = cast(scope, Map<String, Dynamic>)[name];
                if (potentialValue != null) {
                    return { value: potentialValue, scope: scope };
                }
            } catch (e: Dynamic) {
                // It's not a dict
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

                return funcall(funcInfo, exps.slice(1));
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