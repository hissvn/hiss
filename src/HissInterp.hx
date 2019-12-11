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
            //case Atom(Int(i)) if (i == 0): false; /* 0 being falsy will be useful for Hank read-counts */
            case List(l) if (l.length == 0): false;
            case Error(m): false;
            default: true;
        }
    }

    /**
     * Implementation of the `if` macro. Returns value of `thenExp` if condition is truthy, else * evaluates `elseExp`
     **/
    function hissIf(condExp: HValue, thenExp: HValue, elseExp: Null<HValue>) {
        var cond = eval(condExp);
        return if (truthy(cond)) {
            eval(thenExp);
        } else if (elseExp != null) {
            //trace('else exp is $elseExp');
            eval(elseExp);
        } else {
            Nil;
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
            fun = Function(Macro(true, fun.toHFunction()));
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

    public static macro function importPredicate(f: Expr) {
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
            variables[$v{name} + "?"] = Function(Haxe(Fixed, $f));            
        };
    }

    public static macro function importWrapped(f: Expr) {
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
        return macro variables[$v{name}] = Function(Haxe(Fixed, (v: HValue) -> {
            return $f(valueOf(v)).toHValue();
        }));            
        
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
            case Nil: false;
            case T: true;
            case Atom(Int(v)):
                v;
            case Atom(Float(v)):
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
                Atom(Float(v));
            case TBool:
                if (v) T else Nil;
            case TClass(c):
                var name = Type.getClassName(c);
                return switch (name) {
                    case "String":
                        Atom(String(v));
                    case "Array":
                        var va = cast(v, Array<Dynamic>);
                        List([for (e in va) e.toHValue()]);
                    default:
                        Object(name, v);
                }
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

        variables['not'] = Function(Haxe(Fixed, (v: HValue) -> if (truthy(v)) Nil else T));

        // TODO allow other sorting algorithms, Reflect.compare, etc.
        function sort(v: HValue) {
            var sorted = v.toList().copy();
            sorted.sort((v1:HValue, v2:HValue) -> {
                Std.int(valueOf(v1) - valueOf(v2));
            });
            return List(sorted);
        }
        importFixed(sort);
        function reverseSort(v: HValue) {
            var sorted = v.toList().copy();
            sorted.sort((v1:HValue, v2:HValue) -> {
                Std.int(valueOf(v2) - valueOf(v1));
            });
            return List(sorted);
        }
        importFixed(reverseSort);

        function indexOf(l: HValue, v: HValue): HValue {
            var list = l.toList();
            var idx = 0;
            for (lv in list) {
                if (Type.enumEq(v, lv)) return Atom(Int(idx));
                idx++;
            }
            return Nil;
        }
        importFixed(indexOf);
        
        function contains(l: HValue, v: HValue):HValue {
            return if (truthy(indexOf(l, v))) T else Nil;
        }
        importFixed(contains);

        variables['read-line'] = Function(Haxe(Var, (args: HValue) -> {
            if (args.toList().length == 1) {
                Sys.print(first(args).toString());
            }
            return Atom(String(Sys.stdin().readLine()));
        }));

        // Control flow
        variables['if'] = Function(Macro(false, Haxe(Fixed, hissIf)));

        variables['progn'] = Function(Haxe(Var, (exps: HValue) -> {
            return exps.toList().pop();
        }));

        variables['list'] = Function(Haxe(Var, (exps: HValue) -> {
            return exps;
        }));

        variables['quote'] = Function(Macro(false, Haxe(Fixed, (exp: HValue) -> {
            return exp;
        })));

        function int(value: HValue) {
            try {
                value.toInt();
                return T;
            } catch (s: Dynamic) {
                return Nil;
            }
        }
        importPredicate(int);

        function list(value: HValue) {
            try {
                value.toList();
                return T;
            } catch (s: Dynamic) {
                return Nil;
            }
        }
        importPredicate(list);

        function symbol(value: HValue) {
            try {
                symbolName(value);
                return T;
            } catch (s: Dynamic) {
                return Nil;
            }
        }
        importPredicate(symbol);

        // Haxe std io
        function print(value: HValue) {
            Sys.println(value.toPrint());
            return value;
        }
        importFixed(print);
        
        importWrapped(Std.parseInt);
        importWrapped(Std.parseFloat);

        // Haxe binops
        importFixed(HissParser.read);
        importFixed(eval);

        // Haxe math
        importWrapped(Math.round);
        importWrapped(Math.floor);
        importWrapped(Math.ceil);
        importWrapped(Math.abs);

        importFixed(first);
        importFixed(rest);
        importFixed(nth);
        importFixed(slice);
        importFixed(take);

        importFixed(symbolName);

        // most haxe binary operators are non-binary (like me!) in most Lisps.
        // They can take any number of arguments.
        // Since we still need haxe to run the computations, Hiss imports those binary
        // operators, but hides them with the prefix 'haxe' to it can provide its own
        // lispy operator functions.
        importBinops(true, "+", "-", "/", "*", ">", ">=", "<", "<=", "==");

        // Still more binary operators just don't exist in lisp because they are named functions like `and` or `or`
        importBinops(true, /* "&&",*/ "||", "...");

        /* variables['haxe&&'] = Function(Haxe(Fixed, (a: HValue, b: HValue) -> {
            if (truthy(a) && truthy(b)) T else Nil;
        })); */

        function eq(a: HValue, b: HValue): HValue {
            try {
                var l1 = a.toList();
                var l2 = b.toList();
                if (l1.length != l2.length) return Nil;
                var i = 0;
                while (i < l1.length) {
                    if (!truthy(eq(l1[i], l2[i]))) return Nil;
                    i++;
                }
                return T;
            } catch (s: Dynamic) {
                return if (Type.enumEq(a, b)) T else Nil;
            }
        }
        importFixed(eq);

        function or(args: HValue) {
            return if (args.toList().length == 0) {
                Nil;
            } else if (truthy(eval(first(args)))) {
                T;
            } else {
                or(rest(args));
            }
        }
        variables['or'] = Function(Macro(false, Haxe(Var, or)));

        // Some binary operators are Lisp-compatible as-is
        importBinops(false, "%");  

        variables['lambda'] = Function(Macro(false, Haxe(Var, lambda)));
        variables['defun'] = Function(Macro(false, Haxe(Var, defun)));
        variables['defmacro'] = Function(Macro(false, Haxe(Var, defmacro)));

        importFixed(length);

        importFixed(cons);

        importFixed(resolve);
        importFixed(funcall);
        importFixed(load);
        importWrapped(sys.io.File.getContent);
        
        variables['split'] = Function(Haxe(Fixed, (s: HValue, d: HValue) -> {s.toString().split(d.toString()).toHValue();}));
        // TODO escape sequences aren't parsed so this needs its own function:
        variables['split-lines'] = Function(Haxe(Fixed, (s: HValue) -> {s.toString().split("\n").toHValue();}));

        variables['push'] = Function(Haxe(Fixed, (l:HValue, v:HValue) -> {l.toList().push(v); return l;}));

        variables['scope-in'] = Function(Haxe(Fixed, () -> {stackFrames.push(new HMap()); return Nil; }));
        variables['scope-out'] = Function(Haxe(Fixed, () -> {stackFrames.pop(); return Nil;}));
        variables['scope-return'] = Function(Haxe(Fixed, (v: HValue) -> { stackFrames.pop(); return v;}));
        
        variables['error'] = Function(Haxe(Fixed, (message: HValue) -> {return Error(message.toString());}));

        // TODO strings with interpolation

        function string(l: HValue): HValue {
            return Atom(String(try {
                valueOf(l).toString();
            } catch (s: Dynamic) {
                Std.string(valueOf(l));
            }));
        }
        importFixed(string);

        function setq (l: HValue): HValue {
            var list = l.toList();
            var name = symbolName(list[0]).toString();
            var value = eval(list[1]);
            // trace('done evaling the list');
            // trace('setting $name to $value');
            variables[name] = value;
            if (list.length > 2) {
                return setq(List(list.slice(2)));
            } else {
                return value;
            }
        };

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
                return setlocal(List(list.slice(2)));
            } else {
                return value;
            }
        };

        function append(args: HValue) {
            var firstList: HList = first(args).toList();

            return if (truthy(rest(args))) {
                var nextList = first(rest(args)).toList();
                var newFirst = firstList.concat(nextList);
                var newArgs = rest(rest(args)).toList();
                newArgs.insert(0, List(newFirst));
                append(List(newArgs));
            } else {
                List(firstList);
            }
        };

        variables['append'] = Function(Haxe(Var, append));

        variables['setq'] = Function(Macro(false, Haxe(Var, setq)));
        variables['setlocal'] = Function(Macro(false, Haxe(Var, setlocal)));

        variables['set-nth'] = Function(Haxe(Fixed, (arr: HValue, idx: HValue, val: HValue) -> { 
            arr.toList()[idx.toInt()] = val; return arr;
        }));

        variables['for'] = Function(Macro(false, Haxe(Var, (args: HValue) -> {
            var argList = args.toList();
            var name = argList[0];
            var coll = eval(argList[1]);
            //var coll = argList[1];


            var body: HValue = List(argList.slice(2));
            return switch (coll) {
                case Object("IntIterator", o):
                    var it: IntIterator = cast(eval(argList[1]).toObject(), IntIterator);
            
                    List([for (v in it) {
                        setlocal(List([name, Atom(Int(v))]));

                        //trace('innter funcall');
                        eval(cons(Atom(Symbol("progn")), body));
                    }]);
                case List(l):
                    List([for (v in l) {
                        setlocal(List([name, v]));

                        //trace('innter funcall');
                        eval(cons(Atom(Symbol("progn")), body));
                    }]);
                default:
                    Error('cannot call for loop on ${coll.toPrint()}');
            }

            
            //return Nil;
        })));

        variables['while'] = Function(Macro(false, Haxe(Var, (args: HValue) -> {
            var argList = args.toList();
            var cond = argList[0];
            var body: HValue = List(argList.slice(1));
            
            while (truthy(eval(cond))) {
                //trace('innter funcall');
                eval(cons(Atom(Symbol("progn")), body));
            }
            return Nil;
        })));

        variables['dolist'] = Function(Haxe(Fixed, (list: HValue, func: HValue) -> {
            for (v in list.toList()) {
                
                //trace('calling ${funcInfo} with arg ${v}');
                funcall(func, List([v]), Nil);
            }
            return Nil;
        }));
        variables['map'] = Function(Haxe(Fixed, (arr: HValue, func: HValue) -> {
            return List([for (v in arr.toList()) funcall(func, List([v]))]);
        }));

        try {
            load(Atom(String('src/std.hiss')));
        } catch (s: Dynamic) {
            trace('Error loading the standard library: $s');
        }
    }


    public static function first(list: HValue): HValue {
        //trace('calling first on ${list.toPrint()}');
        var v = list.toList()[0];
        if (v == null) v = Nil;
        return v;
    }

    public static function rest(list: HValue): HValue {
        return List(list.toList().slice(1));
    }

    public static function nth(list: HValue, idx: HValue):HValue {
        return list.toList()[idx.toInt()];
    }

    public static function slice(list: HValue, idx: HValue):HValue {
        return List(list.toList().slice(idx.toInt()));
    }

    public static function take(list: HValue, n: HValue):HValue {
        return List(list.toList().slice(0, n.toInt()));
    }

    public static function toList(list: HValue): HList {
        return HissTools.extract(list, List(l) => l);
    }

    public static function toObject(obj: HValue): Dynamic {
        return HissTools.extract(obj, Object(_, o) => o);
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

        var watchedFunctions = [];
        //watchedFunctions = ["nth", "set-nth", "+", "progn"];
        //watchedFunctions = ["distance", "anonymous"];
        // watchedFunctions = ["intersection", "and", "not"];
        //watchedFunctions = ["dolist"];


        function charAt (str: HValue, idx: HValue) {
            return Atom(String(str.toString().charAt(idx.toInt())));
        }
        importFixed(charAt);
        
        variables['substr'] = Function(Haxe(Var, (args: HValue) -> {
            var l = args.toList();
            var str = l[0].toString();
            var start = l[1].toInt();
            var len = null;
            if (l.length > 2) len = l[2].toInt();
            return Atom(String(str.substr(start, len)));
        }));


        //var watchedFunctions = ['=', 'haxe=='];
        //var watchedFunctions = ["variadic-binop", "-", "haxe-", "funcall"];
        var watched = watchedFunctions.indexOf(name) != -1;

        // trace('calling function $name whose value is $func');

        switch (func) {
            case Function(Macro(e, m)):
                //trace('macroexpanding $m');
                var macroExpansion = funcall(Function(m), args, Nil);
                if (watched) trace('macroexpansion $name ${func.toPrint()} -> ${macroExpansion.toPrint()}');
                return if (e) {
                    eval(macroExpansion);
                } else {
                    macroExpansion;
                };
            
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
            // trace('evaling args ${argVals.toPrint()} for $name');
            argVals = evalAll(args);
        }
        
        var argList: HList = argVals.toList();

        // TODO trace the args

        //trace('convert $name: ${func} to h function');
        var hfunc = func.toHFunction();

        var message = 'calling $name: $hfunc with args ${argVals.toPrint()}';
        if (watched) trace(message);

        try {
            switch (hfunc) {
                case Haxe(t, hxfunc):
                    switch (t) {
                        case Var: 
                            // trace('varargs -- putting them in a list');
                            argList = [List(argList)];
                        case Fixed:
                    }

                    // trace('calling haxe function $name with $argList');
                    var result: HValue = Reflect.callMethod(container, hxfunc, argList);

                    if (watched) trace('returning ${result.toPrint()} from ${name}');

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
                                if (nameIdx > funDef.argNames.length-1) throw 'Supplied too many arguments for ${funDef.argNames}: $argList';
                                argStackFrame[funDef.argNames[nameIdx++]] = val;
                            }
                            break;
                        } else {
                            argStackFrame[arg] = argList[valIdx++];
                            nameIdx++;
                        }
                    }

                    // Functions bodies should be executed in their own cut-off stack frame.
                    stackFrames = if (truthy(evalArgs)) {
                        [argStackFrame];
                    } 
                    //  Macros should not!
                    else {
                        var copy = stackFrames.copy();
                        copy.push(argStackFrame);
                        copy;
                    }
                    
                    var lastResult = null;
                    for (expression in funDef.body) {
                        try {
                            lastResult = eval(expression);
                        }/* catch (e: Dynamic) {
                            stackFrames = oldStackFrames;
                            throw e;
                        }*/
                    }

                    stackFrames = oldStackFrames;

                    //trace('returning ${lastResult.toPrint()} from ${func.toPrint()}');

                    return lastResult;
                default: throw 'cannot call $funcOrPointer as a function';
            }
        } catch (s: Dynamic) {
            trace('error $s while $message');
            throw s;
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

    public function evalUnquotes(expr: HValue): HValue {
        return switch (expr) {
            case List(exps):
                List(exps.map((exp) -> evalUnquotes(exp)));
            case Quote(exp):
                Quote(evalUnquotes(exp));
            case Unquote(h):
                eval(h);
            case Quasiquote(exp):
                evalUnquotes(exp);
            default: expr;
        };
    }

    public function eval(expr: HValue, returnScope: HValue = Nil): HValue {
        // trace('eval called on $expr');
        var value = switch (expr) {
            case Atom(a):
                switch (a) {
                    case Int(v):
                        expr;
                    case Float(v):
                        expr;
                    case String(v):
                        expr;
                    case Symbol(name):
                        var varInfo = resolve(name);
                        if (varInfo.value == null) {
                            //trace('Tried to access undefined variable $name with stackFrames $stackFrames');
                            return Nil;
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
                var value = switch (funcInfo) {
                    case VarInfo(v):
                        v.value;
                    default: return Error('${expr.toPrint()}: ${funcInfo.toPrint()} is not a function pointer');
                }
                if (funcInfo == null || value == null) { trace(funcInfo); }
                var args = rest(expr);

                // trace('calling funcall $funcInfo with args (before evaluation): $args');
                funcall(funcInfo, args);
            case Quote(exp):
                exp;
            case Quasiquote(exp):
                evalUnquotes(exp);
            case Unquote(exp):
                eval(exp);
            case Function(f):
                expr;
            case Nil | T:
                expr;
            case Error(m):
                expr;
            default:
                throw 'Eval for type of expression ${expr} is not yet implemented';
        };
        if (value == null) {
            throw('Expression evaluated null: ${expr.toPrint()}');
        }
        //trace(value);
        switch (value) {
            case Error(m):
                throw '$m';
            default: return value;
        }
    }
}