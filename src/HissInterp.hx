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
        //trace(f);
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
        trace(code);
        var expr = Context.parse(code, Context.currentPos());
        trace(expr);
        return expr;
        return macro trace('pass');
    }

    public function new() {
        // The hiss standard library:
        variables['nil'] = null;
        variables['null'] = null;

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

        // many binary operators are required, but mostly shadowed by Hiss implementations. So they are prefixed with 'haxe'
        importBinops(true, "+", "-", "/", "*");
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

                var func = cast(funcInfo.value, HFunction);

                switch (func) {
                    case Haxe(t, func):
                        var args: HissList = evalHissList(exps.slice(1));
                        switch (t) {
                            case Var: args = [args];
                            case Fixed:
                        }
                        return Reflect.callMethod(funcInfo.scope, func, args);
                    
                    case Hiss(funDef):
                        return null;
                        
                    default:
                        throw 'The expression provided is not a function: $funcInfo';
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