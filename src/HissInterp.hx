package;

import haxe.macro.Context;
import haxe.macro.Expr;
using haxe.macro.ExprTools;
using haxe.macro.Expr.Binop;

using Lambda;

import sys.io.File;
import Reflect;
import Type;

import HissParser;
import HTypes;

using HissInterp;
import HissTools;

class HissInterp {
    public var variables: HMap = [];
    private var stackFrames: Array<HMap> = [];

    // TODO import needs to turn camel case into lisp-case
    static function symbolName(v: HValue): HValue {
        return Atom(String(HissTools.extract(v, Atom(Symbol(name)) => name)));
    }

    public function load(file: HValue) {
        var contents = sys.io.File.getContent(HissTools.extract(file, Atom(String(s)) => s));
        eval(HissParser.read('(progn ${contents})'));
    }

    /**
     * Behind the scenes, this function evaluates the truthiness of an HValue
     **/
    public static function truthy(cond: HValue): Bool {
        return switch (cond) {
            case Nil: false;
            case Atom(Int(i)) if (i == 0): false;
            case List(l) if (l.length == 0): false;
            default: true;
        }
    }

    /**
     * Implementation of the `if` macro. Returns value of `thenExp` if condition is truthy, else * evaluates `elseExp`
     **/
    function hissIf(condExp: HValue, thenExp: HValue, elseExp: HValue) {
        var cond = eval(condExp);
        return if (truthy(cond)) {
            eval(thenExp);
        } else {
            eval(elseExp);
        }
    }

    static function length(arg:HValue): HValue {
        return switch (arg) {
            case Atom(String(s)): Atom(Int(s.length));
            case List(l): Atom(Int(l.length));
            default: throw 'HValue $arg has no length';
        }
    }

    function lambda(args: HValue): HValue {
        var argNames = first(args).toList().map(s -> symbolName(s).toString());
        
        var body: HList = rest(args).toList();
        var def: HFunDef = {
            argNames: argNames,
            body: body
        };

        return Function(Hiss(def));
    }

    static function toHFunction(hv: HValue) {
        return HissTools.extract(hv, Function(f) => f);
    }

    // TODO optional docstrings lollll
    function defun(args: HValue, isMacro: HValue = Nil) {
        var name = symbolName(first(args)).toString();
        var fun = lambda(rest(args));
        if (truthy(isMacro)) {
            fun = Function(Macro(fun.toHFunction()));
        }
        variables[name] = fun;
        return fun;
    }

    function defmacro(args: HValue): HValue {
        return defun(args, T);
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
            variables[$v{name}] = Function(Haxe(Fixed, $f));            
        };
    }

    public static function toInt(v: HValue): Int {
        return HissTools.extract(v, Atom(Int(i)) => i);
    }

    public static macro function importBinops(prefix: Bool, rest: Array<ExprOf<String>>) {
        var block = [];
        for (e in rest) {
            var s = e.getValue();
            block.push(macro importBinop($v{s}, $v{prefix}));
        }
        return macro $b{block};
    }

    /**
     * Behind the scenes function to HissTools.extract a haxe binop-compatible value from an HValue
     **/
    public static function valueOf(hv: HValue): Dynamic {
        return switch (hv) {
            case Atom(Int(v)):
                v;
            case Atom(Double(v)):
                v;
            case Atom(String(v)):
                v;
            default: throw 'hvalue $hv cannot be unwrapped for a binary operation';
        }
    }

    static function toHValue(v: Dynamic): HValue {
        return switch (Type.typeof(v)) {
            case TInt:
                Atom(Int(v));
            case TFloat:
                Atom(Double(v));
            case TBool:
                if (v) T else Nil;
            case TClass(c) if (Type.getClassName(c) == "String"):
                Atom(String(v));
            default:
                throw 'value $v cannot be wrapped as an HValue';
        }
    }

    // TODO -[int] literals are broken (parsing as symbols)
    public static macro function importBinop(op: String, prefix: Bool) {
        var name = op;
        if (prefix) {
            name = 'haxe$name';
        }

        var code = 'variables["$name"] = Function(Haxe(Fixed, (a,b) -> toHValue(valueOf(a) $op valueOf(b))))';

        var expr = Context.parse(code, Context.currentPos());
        return expr;
    }

    static function cons(hv: HValue, hl: HValue): HValue {
        var l = hl.toList().copy();
        l.insert(0, hv);
        return List(l);
    }

    static function toString(hv: HValue) {
        return HissTools.extract(hv, Atom(String(s)) => s);
    }

    public function new() {
        // The hiss standard library:
        variables['nil'] = Nil;
        variables['null'] = Nil;
        variables['false'] = Nil;
        variables['t'] = T;
        variables['true'] = T;

        // Control flow
        variables['if'] = Function(Macro(Haxe(Fixed, hissIf)));

        variables['progn'] = Function(Haxe(Var, (exps: HValue) -> {
            return exps.toList().pop();
        }));

        // Haxe std io
        function print(value: HValue) {
            try {
				var primitiveVal = HissInterp.valueOf(value);
				Sys.print(primitiveVal);
			} catch (e: Dynamic) {
				Sys.print(value);
			}
            return value;
        }
        function println(value: HValue) {
            print(value);
            Sys.print("\n");
        }
        importFixed(print);
        importFixed(println);
        
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

        variables['lambda'] = Function(Macro(Haxe(Var, lambda)));
        variables['defun'] = Function(Macro(Haxe(Var, defun)));
        variables['defmacro'] = Function(Macro(Haxe(Var, defmacro)));

        importFixed(length);

        importFixed(cons);

        importFixed(resolve);
        importFixed(funcall);
        importFixed(load);
        importFixed(sys.io.File.getContent);
        
        variables['split'] = Function(Haxe(Fixed, (s, d) -> {s.split(d);}));
        // TODO escape sequences aren't parsed so this needs its own function:
        variables['splitLines'] = Function(Haxe(Fixed, (s) -> {s.split("\n");}));

        variables['push'] = Function(Haxe(Fixed, (l, v) -> {l.toList().push(v); return l;}));

        variables['scope-in'] = Function(Haxe(Fixed, () -> {stackFrames.push(new HMap()); return null; }));
        variables['scope-out'] = Function(Haxe(Fixed, () -> {stackFrames.pop(); return null;}));
        
        
        function setq (l: HValue) {
            var list = l.toList();
            var name = symbolName(list[0]).toString();
            var value = eval(list[1]);
            variables[name] = value;
            if (list.length > 2) {
                setq(List(list.slice(2)));
            }
        };

        variables['setq'] = Function(Macro(Haxe(Var, setq)));
        
        

        variables['setlocal'] = Function(Macro(Haxe(Var, setlocal)));

        variables['set-nth'] = Function(Haxe(Fixed, (arr: HValue, idx: HValue, val: HValue) -> { arr.toList()[idx.toInt()] = val;}));

        /*variables['for'] = Function(Macro(Haxe(Fixed, (iterator: HValue, func: HValue) -> {
            var it: IntIterator = eval(iterator);
            var f = resolve(symbolName(func));
            for (v in it) {
                trace('innter funcall');
                funcall(f, [v]);
            }
        })));
        */

        variables['dolist'] = Function(Haxe(Fixed, (list: HValue, func, HValue) -> {
            for (v in list.toList()) {
                
                //trace('calling ${funcInfo} with arg ${v}');
                funcall(func, List([v]));
            }
        }));
        variables['map'] = Function(Haxe(Fixed, (arr: HValue, func: HValue) -> {
            return List([for (v in arr.toList()) funcall(func, List([v]))]);
        }));

        load(Atom(String('src/std.hiss')));
    }

    function setlocal (l: HValue) {
        //trace(list);
        var list = l.toList();
        var name = symbolName(list[0]).toString();
        var value = eval(list[1]);
        var stackFrame: HMap = variables;
        if (stackFrames.length > 0) {
            stackFrame = stackFrames[stackFrames.length-1];
        }
        stackFrame[name] = value;
        if (list.length > 2) {
            setlocal(List(list.slice(2)));
        }
    };


    public static function first(list: HValue): HValue {
        return list.toList()[0];
    }

    public static function rest(list: HValue): HValue {
        return List(list.toList().slice(1));
    }

    public static function nth(list: HValue, idx: HValue) {
        return list.toList()[idx.toInt()];
    }

    public static function slice(list: HValue, idx: HValue) {
        return HissTools.extract(list, List(l) => l).slice(idx.toInt());
    }

    public static function toList(list: HValue): HList {
        return HissTools.extract(list, List(l) => l);
    }

    function evalAll(hl: HValue): HValue {
        //trace(hl);
        return List([for (exp in hl.toList()) eval(exp)]);
    }

    public function funcall(funcOrPointer: HValue, args: HValue, evalArgs: HValue = T): HValue {
        var container = null;
        var name = "anonymous";
        var func = funcOrPointer;
        switch (funcOrPointer) {    
            case VarInfo(v):
                name = v.name;
                container = v.container;
                func = v.value;
            default:
        }

        // trace('calling function $name whose value is $func');

        switch (func) {
            case Function(Macro(func)):
                var macroExpansion = funcall(Function(func), args, Nil);

                return eval(macroExpansion);
            
                /*
                switch (func) {
                    case Haxe(_, _):
                        return val;
                    case Hiss(_):
                        trace('macro ${funcInfo.name} expanded to ${val}');
                        return eval(val);
                    case Macro(_):
                        throw 'eawerae';
                }*/      
            default:
        }
        
        var argVals = args;
        if (truthy(evalArgs)) {
            // trace('evaling args $args for $name');
            argVals = evalAll(args);
            // trace('they were $argVals');
        }

        var argList: HList = argVals.toList();

        // TODO trace the args

        //trace('convert $func to h function');
        var hfunc = func.toHFunction();

        switch (hfunc) {
            case Haxe(t, hxfunc):
                switch (t) {
                    case Var: 
                        // trace('varargs -- putting them in a list');
                        argList = [List(argList)];
                    case Fixed:
                }

                // trace('calling haxe function with $argList');
                var result: HValue = Reflect.callMethod(container, hxfunc, argList);

                // trace('returning ${result} from ${funcInfo.name}');

                return result;
    
            case Hiss(funDef):
                var oldStackFrames = stackFrames;

                var argStackFrame: HMap = [];
                var valIdx = 0;
                var nameIdx = 0;
                while (nameIdx < funDef.argNames.length) {
                    var arg = funDef.argNames[nameIdx];
                    if (arg == "&rest") {
                        argStackFrame[funDef.argNames[++nameIdx]] = List(argList.slice(valIdx));
                        break;
                    } else if (arg == "&optional") {
                        nameIdx++;
                        for (val in argList.slice(valIdx)) {
                            argStackFrame[funDef.argNames[nameIdx++]] = val;
                        }
                        break;
                    } else {
                        argStackFrame[arg] = argList[valIdx++];
                        nameIdx++;
                    }
                }

                stackFrames = [argStackFrame];
                
                var lastResult = null;
                for (expression in funDef.body) {
                    lastResult = eval(expression);
                }

                stackFrames = oldStackFrames;

                // trace('returning ${lastResult} from ${funcInfo.name}');

                return lastResult;
            default: throw 'cannot call $funcOrPointer as a function';
        }
    }

    /**
     * Behind the scenes function to retrieve the value and "address" of a variable,
     * using lexical scoping
     **/
    public function resolve(name: String): HVarInfo {
        var idx = stackFrames.length-1;
        var value = null;
        var frame = null;
        while (value == null && idx >= 0) {
            frame = stackFrames[idx--];
            value = frame[name];
        }
        if (value == null) value = variables[name];

        return { name: name, value: value, container: frame };
    }

    public function eval(expr: HValue, returnScope: HValue = Nil): HValue {
        return switch (expr) {
            case Atom(a):
                return switch (a) {
                    case Int(v):
                        expr;
                    case Double(v):
                        expr;
                    case String(v):
                        expr;
                    case Symbol(name):
                        var varInfo = resolve(name);
                        if (varInfo.value == null) {
                            throw 'Tried to access undefined variable $name with stackFrames $stackFrames';
                        }
                        if (truthy(returnScope)) {
                            VarInfo(varInfo);
                        } else {
                            varInfo.value;
                        }
                }
            case List([]):
                Nil;
            case List(exps):
                var funcInfo = eval(first(expr), T);
                var args = rest(expr);

                // trace('calling funcall $funcInfo with $args');
                return funcall(funcInfo, args);
            case Quote(exp):
                exp;
            case Quasiquote(List(exps)):
                var afterEvalUnquotes = exps.map((exp) -> switch (exp) {
                    case Quote(h):
                        Quote(eval(Quasiquote(h)));
                    case Unquote(innerExp):
                        eval(innerExp);
                    case List(exps):
                        eval(Quasiquote(List(exps)));
                    default:
                        exp;
                });
                List(afterEvalUnquotes);
            case Quasiquote(Unquote(h)):
                Quote(eval(h));
            case Quasiquote(exp):
                exp;
            case Unquote(exp):
                eval(exp);
            case Function(f):
                expr;
            default:
                throw 'Eval for type of expression ${expr} is not yet implemented';
        }
    }
}