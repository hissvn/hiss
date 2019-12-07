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

    public function load(file: String) {
        var fileLines = sys.io.File.getContent(file).split('\n---\n');
        for (line in fileLines) {
            eval(HissParser.read(line));
        }
    }

    static function toHissList(v: Dynamic): HissList {
        if (!truthy(v)) return new HissList();
        try {
            var exp = cast(v, HExpression);
            switch (exp) {
                case HExpression.List(l):
                    return l;
                default:
                    throw "it's an expression but not a list expression";
            } 
        } catch (s: Dynamic) {
            try {
                var list = cast(v, HissList);
                return list;
            }
            catch (s: Dynamic) {
                return [v];
                throw 'value $v cannot be coerced';
            }
        }
    }

    static function truthy(cond: Dynamic) {
        if (cond != null) {
            var truthy = true;
            switch (Type.typeof(cond)) {
                case TBool:
                    truthy = cond;
                // 0 is usually truthy in lisps, but for use in Hank, we want a read-count of 0 to yield false
                case TInt:
                    truthy = (cond != 0);
                case TEnum(e):
                    switch (cond) {
                        case HExpression.List(l) if (l.length == 0):
                            truthy = false;
                        default:
                            
                    }
                default:
                    try {
                        if (length(cond) == 0) {
                            truthy = false;
                        }
                    } catch (s: Dynamic) {
                                
                    }
            }
            return truthy;
        }
        return false;
    }

    function hissIf(condition, thenExp, elseExp) {
        var cond: Dynamic = eval(condition);
        //trace(cond);
        if (truthy(cond)) {
            return eval(thenExp);
        }
        return eval(elseExp);
    }

    static function length(arg:Dynamic): Int {
        try { 
            cast(arg, HExpression);
        
            switch (arg) {
                case HExpression.List(l):
                    return l.length;
                default:
                    throw "can't take length of non-list HExpression";
            }
        } catch (e: Dynamic) {
            return Reflect.getProperty(arg, "length");
            //return arg.length;
        }
    }

    // TODO optional docstrings lollll
    function defun(args: ExpList, isMacro = false): HFunction {
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
        if (isMacro) {
            variables[name] = HFunction.Macro(variables[name]);
        }
        return variables[name];
    }

    function defmacro(args: ExpList): HFunction {
        return defun(args, true);
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

// TODO -[int] literals are broken (parsing as symbols)
    public static macro function importBinop(op: String, prefix: Bool) {
        var name = op;
        if (prefix) {
            name = 'haxe$name';
        }

        var code = 'variables["$name"] = HFunction.Haxe(ArgType.Fixed, (a,b) -> a $op b)';

        var expr = Context.parse(code, Context.currentPos());
        return expr;
    }

    static function cons(v: Dynamic, h: HissList) {
        var copy = h.copy();
        copy.insert(0, v);
        return copy;
    }

    public function new() {
        // The hiss standard library:
        variables['nil'] = null;
        variables['null'] = null;
        variables['false'] = null;
        variables['t'] = true;
        variables['true'] = true;

        // Control flow
        variables['if'] = HFunction.Macro(HFunction.Haxe(ArgType.Fixed, hissIf));

        // Haxe std io
        importFixed(Sys.print);
        importFixed(Sys.println);
        
        importFixed(Std.parseInt);
        importFixed(Std.parseFloat);

        // Haxe binops
        importFixed(HissParser.read);
        importFixed(eval);

        // Haxe math
        importFixed(Math.round);
        importFixed(Math.floor);
        importFixed(Math.ceil);

        importFixed(first);
        importFixed(rest);
        importFixed(nth);
        importFixed(slice);

        // most haxe binary operators are non-binary (like me!) in most Lisps.
        // They can take any number of arguments.
        // Since we still need haxe to run the computations, Hiss imports those binary
        // operators, but hides them with the prefix 'haxe' to it can provide its own
        // lispy operator functions.
        importBinops(true, "+", "-", "/", "*", ">", ">=", "<", "<=", "==");

        // Still more binary operators just don't exist in lisp because they are named functions like `and` or `or`
        importBinops(true, "&&", "||", "...");

        // Some binary operators are Lisp-compatible as-is
        importBinops(false, "%");  

        variables['defun'] = HFunction.Macro(HFunction.Haxe(ArgType.Var, defun));
        variables['defmacro'] = HFunction.Macro(HFunction.Haxe(ArgType.Var, defmacro));

        importFixed(length);

        importFixed(cons);

        importFixed(resolve);
        importFixed(funcall);
        importFixed(load);
        importFixed(sys.io.File.getContent);
        
        variables['split'] = HFunction.Haxe(ArgType.Fixed, (s, d) -> {s.split(d);});
        // TODO escape sequences aren't parsed so this needs its own function:
        variables['splitLines'] = HFunction.Haxe(ArgType.Fixed, (s) -> {s.split("\n");});


        variables['push'] = HFunction.Haxe(ArgType.Fixed, (l, v) -> {l.push(v); return l;});

        variables['scope-in'] = HFunction.Haxe(ArgType.Fixed, () -> {scopes.push(new Map<String, Dynamic>());});
        variables['scope-out'] = HFunction.Haxe(ArgType.Fixed, () -> {scopes.pop();});
        function setq (list) {
            var name = symbolName(list[0]);
            var value = eval(list[1]);
            variables[name] = value;
            if (list.length > 2) {
                setq(list.slice(2));
            }
        };

        variables['setq'] = HFunction.Macro(HFunction.Haxe(ArgType.Var, setq));
        
        function setlocal (list) {
            //trace(list);
            var name = symbolName(list[0]);
            var value = eval(list[1]);
            var scope = if (scopes.length > 0) {
                cast(scopes[scopes.length-1], Map<String,Dynamic>);
            } else {
                variables;
            }
            scope[name] = value;
            if (list.length > 2) {
                setlocal(list.slice(2));
            }
        };

        variables['setlocal'] = HFunction.Macro(HFunction.Haxe(ArgType.Var, setlocal));
        variables['dolist'] = HFunction.Macro(HFunction.Haxe(ArgType.Fixed, (arr, func) -> {
            trace(arr);
            var arrr = eval(arr);
            trace(arrr);
            var arrrr: HissList = toHissList(arrr);
            trace (arrrr);
            for (v in arrrr) {
                var funcInfo = resolve(symbolName(func));
                //trace('calling ${funcInfo} with arg ${v}');
                funcall(funcInfo, [v.toHissList()]);
            }
        }));
        variables['map'] = HFunction.Macro(HFunction.Haxe(ArgType.Fixed, (arr, func) -> {
            var arrrr = cast(eval(arr), HissList);            
            //trace(arrrr);
            var mappedValues = [];
            // trace('fuck me ${arrrr}');
            for (v in arrrr) {
                // trace(v);
                mappedValues.push(funcall(resolve(symbolName(func)), v.toHissList()));
                // trace(mappedValues);
            }
            // trace(mappedValues);
            return mappedValues;
        }));

        load('src/std.hiss');
    }

    public static function first(list: Dynamic): Dynamic {
        return list.toHissList()[0];
    }

    public static function rest(list: HissList): HissList {
        return list.toHissList().slice(1);
    }

    public static function nth(list: Dynamic, idx: Int) {
        return list.toHissList()[idx];
    }

    public static function slice(list: Dynamic, idx: Int) {
        return list.toHissList()[idx];
    }

    function evalHissList(exps: Array<HExpression>): HissList {
        return [for (exp in exps) eval(exp)];
    }

    public function funcall(funcInfo: VarInfo, args: Dynamic, evalArgs: Bool = true) {
        if (funcInfo.value == null) {
            throw 'Tried to call undefined function ${funcInfo.name}';
        }
        switch (funcInfo.value) {
            case Macro(func):
                var nestedInfo: VarInfo = { name: 'macroexpansion of $funcInfo.name', value: func, scope: funcInfo.scope };
                var val = funcall(nestedInfo, args, false);
                switch (func) {
                    case Haxe(_, _):
                        return val;
                    case Hiss(_):
                        trace('macro ${funcInfo.name} expanded to ${val}');
                        return eval(val);
                    case Macro(_):
                        throw 'eawerae';
                }       
            default:
        }
        var argVals: HissList = null;
        try {
            cast(args, HExpression);
            switch (args) {
                case HExpression.List(l):
                    argVals = l;
                default:
                    throw 'funcall on $args';
            }
        } catch (s: Dynamic) {
            argVals = args;
        }
        var areTheyExpressions = try {
            cast(args[0], HExpression);
            true;
        } catch (s: Dynamic) {
            false;
        }
        if (evalArgs && areTheyExpressions) {
            argVals = evalHissList(args);
        }

        //trace('calling ${funcInfo.name} with args ${argVals}');

        switch (funcInfo.value) {
            case Haxe(t, func):
                switch (t) {
                    case Var: argVals = [argVals];
                    case Fixed:
                }//trace(
                // trace(argVals);trace(
                var result = Reflect.callMethod(funcInfo.scope, func, argVals);

                // trace('returning ${result} from ${funcInfo.name}');

                return result;
    
            case Hiss(funDef):
                var oldScopes = scopes;

                var argScope: Map<String, Dynamic> = [];
                var valIdx = 0;
                var nameIdx = 0;
                while (nameIdx < funDef.argNames.length) {
                    var arg = funDef.argNames[nameIdx];
                    if (arg == "&rest") {
                        //trace(argVals);
                        argScope[funDef.argNames[++nameIdx]] = argVals.slice(valIdx);
                        break;
                    } else if (arg == "&optional") {
                        nameIdx++;
                        for (val in argVals.slice(valIdx)) {
                            argScope[funDef.argNames[nameIdx++]] = val;
                        }
                        break;
                    } else {
                        argScope[arg] = argVals[valIdx++];
                        nameIdx++;
                    }
                }

                scopes = [argScope];
                
                var lastResult = null;
                for (expression in funDef.body) {
                    lastResult = eval(expression);
                }

                scopes = oldScopes;

                // trace('returning ${lastResult} from ${funcInfo.name}');

                return lastResult;
            default:
                throw 'Nested macros?S?S?S?';
        }
    }

    public function resolve(name: String): VarInfo {
        var idx = scopes.length-1;
        while (idx >= 0) {
            var scope = scopes[idx--];
            var potentialValue = Reflect.getProperty(scope, name);
            if (potentialValue != null) {
                return { name: name, value: potentialValue, scope: scope };
            }
            try {
                potentialValue = cast(scope, Map<String, Dynamic>)[name];
                if (potentialValue != null) {
                    return { name: name, value: potentialValue, scope: scope };
                }
            } catch (e: Dynamic) {
                // It's not a dict
            }
            //trace("in this loop");
        }

        return { name: name, value: variables[name], scope: null };
    }

    public function eval(exprOrList: Dynamic, returnScope: Bool = false): Dynamic {
        var expr = null;
        try {
            expr = cast(exprOrList, HExpression);
        } catch (s: Dynamic) {
            expr = HExpression.List(exprOrList);
        }
        //trace(expr);
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
            case List([]):
                return null;
            case List(exps):
                var funcInfo = eval(exps[0], true);

                return funcall(funcInfo, exps.slice(1));
            case Quote(exp):
                try {
                    var e = cast (exp, HExpression);
                    switch (e) {
                        case HExpression.List(l): return l;
                        default: throw 'not a list';
                    }
                } catch (d: Dynamic) {
                    return exp;
                }
            case Quasiquote(HExpression.List(exps)):
                var afterEvalUnquotes = exps.map((exp) -> switch (exp) {
                    case HExpression.Quote(h):
                        return Quote(eval(HExpression.Quasiquote(h)));
                    case HExpression.Unquote(innerExp):
                        return eval(innerExp);
                    case HExpression.List(exps):
                        return eval(HExpression.Quasiquote(HExpression.List(exps)));
                    default:
                        return exp;
                });
                return HExpression.List(afterEvalUnquotes);
            case Quasiquote(HExpression.Unquote(h)):
                return HExpression.Quote(eval(h));
            case Quasiquote(exp):
                return exp;
            case Unquote(exp):
                return eval(exp);
            default:
                return 'Eval for type of expression ${expr} is not yet implemented';
        }
    }
}