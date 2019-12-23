package;

import haxe.macro.Context;
import haxe.macro.Expr;
using haxe.macro.ExprTools;
using hx.strings.Strings;
using StringTools;

using Lambda;

import sys.io.File;
import Reflect;
import Type;

import HissParser;
import HTypes;

using HissInterp;
import HissTools;

class HissInterp {
    public var variables: HValue;
    private var stackFrames: HValue;
    var watchedVariables: HValue;
    var watchedFunctions: HValue;
    // TODO import needs to turn camel case into lisp-case
    static function symbolName(v: HValue): HValue {
        return Atom(String(HissTools.extract(v, Atom(Symbol(name)) => name)));
    }

    public function load(file: HValue, wrappedIn: String = '(progn * t)') {
        var contents = sys.io.File.getContent(HissTools.extract(file, Atom(String(s)) => s));
        return eval(HissParser.read(wrappedIn.replace('*', contents)));
    }

    /**
     * Behind the scenes, this function evaluates the truthiness of an HValue
     **/
    public static function truthy(cond: HValue): Bool {
        return switch (cond) {
            case Nil: false;
            //case Atom(Int(i)) if (i == 0): false; /* 0 being falsy will be useful for Hank read-counts */
            case List(l) if (l.length == 0): false;
            case Signal(Error(m)): false;
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

    static function toHFunction(hv: HValue): HFunction {
        return HissTools.extract(hv, Function(f) => f);
    }

    // TODO optional docstrings lollll
    function defun(args: HValue, isMacro: HValue = Nil) {
        var name = symbolName(first(args)).toString();
        var fun: HValue = lambda(rest(args));
        if (truthy(isMacro)) {
            fun = Function(Macro(true, fun.toHFunction()));
        }
        variables.toDict()[name] = fun;
        return fun;
    }

    function defmacro(args: HValue): HValue {
        return defun(args, T);
    }
    
    function intern(arg: HValue): HValue {
        return Atom(Symbol(arg.toString()));
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
            variables.toDict()[$v{name}.toLowerHyphen()] = Function(Haxe(Fixed, $f));            
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
            variables.toDict()[$v{name}.toLowerHyphen() + "?"] = Function(Haxe(Fixed, $f));            
        };
    }

    public static macro function importWrapped(interp: Expr, f: Expr) {
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
        return macro $interp.variables.toDict()[$v{name}.toLowerHyphen()] = Function(Haxe(Fixed, (v: HValue) -> {
            return $f(HissInterp.valueOf(v)).toHValue();
        }));
    }

    public static macro function importWrapped2(interp: Expr, f: Expr) {
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
        return macro $interp.variables.toDict()[$v{name}.toLowerHyphen()] = Function(Haxe(Fixed, (v: HValue, v2: HValue) -> {
            return $f(HissInterp.valueOf(v), HissInterp.valueOf(v2)).toHValue();
        }));
    }

    public static macro function importWrappedVoid(interp: Expr, f: Expr) {
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
        return macro $interp.variables.toDict()[$v{name}.toLowerHyphen()] = Function(Haxe(Fixed, (v: HValue) -> {
            $f(HissInterp.valueOf(v));
            return Nil;
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
        if (v == null) return Nil;
        return switch (Type.typeof(v)) {
            case TNull:
                Nil;
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

        var code = 'variables.toDict()["$name"] = Function(Haxe(Fixed, (a,b) -> toHValue(valueOf(a) $op valueOf(b))))';

        var expr = Context.parse(code, Context.currentPos());
        return expr;
    }

    static function cons(hv: HValue, hl: HValue): HValue {
        var l = hl.toList().copy();
        l.insert(0, hv);
        return List(l);
    }

    static function toString(hv: HValue): String {
        return HissTools.extract(hv, Atom(String(s)) => s);
    }

     // TODO allow other sorting algorithms, Reflect.compare, etc.
    function sort(args: HValue) {
        var argList = args.toList();
        var listToSort = argList[0].toList();
        var sortFunction: HValue = if (argList.length > 1 && argList[1] != Nil) argList[1] else variables.toDict()['compare'];
        
        var sorted = listToSort.copy();
        
        sorted.sort((v1:HValue, v2:HValue) -> {
            valueOf(funcall(sortFunction, List([v1, v2]), Nil));
        });
        return List(sorted);
    }

    function reverseSort(v: HValue) {
        // TODO implement better
        var sorted = v.toList().copy();
        sorted.sort((v1:HValue, v2:HValue) -> {
            Std.int(valueOf(v2) - valueOf(v1));
        });
        return List(sorted);
    }

    function readLine(args: HValue) {
        if (args.toList().length == 1) {
            Sys.print(first(args).toString());
        }
        return Atom(String(Sys.stdin().readLine()));
    }

    function getVariables() { return variables; }

    function not(v: HValue) {
        return if (truthy(v)) Nil else T;
    }

    function progn(exps: HValue) {
        var value = null;
        for (exp in exps.toList()) {
            value = eval(exp);
            switch (value) {
                case Signal(Return(v)):
                    return v;
                case Signal(_):
                    return value;
                default:
            }
        }
        return value;
    }

    function makeList(exps: HValue) {
        return exps;
    }

    function quote(exp: HValue) {
        return exp;
    }

    function isError(exp: HValue) {
        return switch (exp) {
            case Signal(Error(_)):
                T;
            default:
                Nil;
        };
    }

    function int(value: HValue) {
        try {
            value.toInt();
            return T;
        } catch (s: Dynamic) {
            return Nil;
        }
    }

    function bound(value: HValue) {
        return if (resolve(symbolName(value).toString()).value != null) T else Nil;
    }

    function list(value: HValue) {
        try {
            value.toList();
            return T;
        } catch (s: Dynamic) {
            return Nil;
        }
    }

    function hissReturn(value: HValue): HValue {
        return Signal(Return(value));
    }

    function hissContinue(): HValue {
        return Signal(Continue);
    }

    function hissBreak(): HValue {
        return Signal(Break);
    }

    function symbol(value: HValue) {
        try {
            symbolName(value);
            return T;
        } catch (s: Dynamic) {
            return Nil;
        }
    }

    function print(value: HValue) {
        Sys.println(value.toPrint());
        return value;
    }

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

    function or(args: HValue) {
        return if (args.toList().length == 0) {
            Nil;
        } else if (truthy(eval(first(args)))) {
            T;
        } else {
            or(rest(args));
        }
    }

    function split(s: HValue, d: HValue) {
        return s.toString().split(d.toString()).toHValue();
    }

    function splitLines(s: HValue) {
        return s.toString().split("\n").toHValue();
    }

    function scopeIn() {
        stackFrames.toList().push(Dict(new HDict()));
        return Nil;
    }

    function scopeOut() {
        stackFrames.toList().pop();
        return Nil;
    }

    function scopeReturn(v: HValue) {
        stackFrames.toList().pop();
        return v;
    }

    function error(message: HValue) {
        return Signal(Error(message.toString()));
    }

    function join(arr: HValue, sep: HValue) {
        var strings = [for (val in arr.toList()) string(val).toString()];
        return Atom(String(strings.join(sep.toString())));
    }

    public function new() {
        // The hiss standard library:
        variables = Dict([]);
        var vars: HDict = variables.toDict();

        vars['variables'] = Function(Haxe(Fixed, getVariables)); 

        vars['return'] = Function(Haxe(Fixed, hissReturn));
        vars['break'] = Function(Haxe(Fixed, hissBreak));
        vars['continue'] = Function(Haxe(Fixed, hissContinue));

        vars['nil'] = Nil;
        vars['null'] = Nil;
        vars['false'] = Nil;
        vars['t'] = T;
        vars['true'] = T;

        vars['not'] = Function(Haxe(Fixed, not));
       
        vars['sort'] = Function(Haxe(Var, sort));
        importWrapped2(this, Reflect.compare);
        
        importFixed(reverse);

        importFixed(intern);

        importFixed(join);
        importFixed(reverseSort);

        importFixed(indexOf);
        
        importFixed(contains);

        vars['read-line'] = Function(Haxe(Var, readLine));

        // Control flow
        vars['if'] = Function(Macro(false, Haxe(Fixed, hissIf)));

        vars['progn'] = Function(Macro(false, Haxe(Var, progn)));

        vars['list'] = Function(Haxe(Var, makeList));

        vars['quote'] = Function(Macro(false, Haxe(Fixed, quote)));

        importPredicate(bound);
        importPredicate(int);
        importPredicate(list);
        importPredicate(symbol);
        vars['error?'] = Function(Haxe(Fixed, isError));

        // Haxe std io
        importFixed(print);
        
        importWrapped(this, Std.parseInt);
        importWrapped(this, Std.parseFloat);

        // Haxe binops
        importFixed(HissParser.read);
        importFixed(eval);

        // Haxe math
        importWrapped(this, Math.round);
        importWrapped(this, Math.floor);
        importWrapped(this, Math.ceil);
        importWrapped(this, Math.abs);

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

        importFixed(eq);

        vars['or'] = Function(Macro(false, Haxe(Var, or)));

        // Some binary operators are Lisp-compatible as-is
        importBinops(false, "%");  

        vars['lambda'] = Function(Macro(false, Haxe(Var, lambda)));
        vars['defun'] = Function(Macro(false, Haxe(Var, defun)));
        vars['defmacro'] = Function(Macro(false, Haxe(Var, defmacro)));

        importFixed(length);

        importFixed(cons);

        importFixed(resolve);
        importFixed(funcall);
        importFixed(load);
        importWrapped(this, sys.io.File.getContent);
        
        vars['split'] = Function(Haxe(Fixed, split));
        // TODO escape sequences aren't parsed so this needs its own function:
        vars['split-lines'] = Function(Haxe(Fixed, splitLines));

        vars['scope-in'] = Function(Haxe(Fixed, scopeIn));
        vars['scope-out'] = Function(Haxe(Fixed, scopeOut));
        vars['scope-return'] = Function(Haxe(Fixed, scopeReturn));
        
        vars['error'] = Function(Haxe(Fixed, error));

        // TODO strings with interpolation

        importFixed(string);        

        vars['append'] = Function(Haxe(Var, append));

        vars['setq'] = Function(Macro(false, Haxe(Var, setq)));
        vars['setlocal'] = Function(Macro(false, Haxe(Var, setlocal)));

        vars['set-nth'] = Function(Haxe(Fixed, setNth));

        vars['for'] = Function(Macro(false, Haxe(Var, hissFor)));

        vars['do-for'] = Function(Macro(false, Haxe(Var, hissDoFor)));

        vars['while'] = Function(Macro(false, Haxe(Var, hissWhile)));

        vars['dolist'] = Function(Haxe(Fixed, doList));
        vars['map'] = Function(Haxe(Fixed, map));

        vars['dict'] = Function(Macro(false, Haxe(Var, dict)));

        vars['set-in-dict'] = Function(Haxe(Fixed, setInDict));

        vars['erase-in-dict'] = Function(Haxe(Fixed, eraseInDict));

        vars['get-in-dict'] = Function(Haxe(Fixed, getInDict));

        vars['keys'] = Function(Haxe(Fixed, keys));


        importFixed(charAt);
        
        vars['substr'] = Function(Haxe(Var, substr));

        watchedFunctions = List([]);
        watchedVariables = List([]);
        stackFrames = List([]);

        // TODO make these all imported getters
        vars['watched-functions'] = watchedFunctions;
        vars['watched-vars'] = watchedVariables;
        vars['stack-frames'] = stackFrames;

        try {
            load(Atom(String('src/stdlib.hiss')));
        }/* catch (s: Dynamic) {
            trace('Error loading the standard library: $s');
        }*/
    }

    function string(l: HValue): HValue {
        return Atom(String(try {
            valueOf(l).toString();
        } catch (s: Dynamic) {
            Std.string(valueOf(l));
        }));
    }

    function setq(l: HValue): HValue {
        var list = l.toList();
        var name = symbolName(list[0]).toString();
        //trace(list[1]);
        var value = eval(list[1]);
        
        var watched = truthy(contains(watchedVariables, Atom(String(name))));
        if (watched) trace('calling setq for $name. New value ${value.toPrint()}');

        try {
            if (value.toList().length == 0 && variables.toDict()[name].toList().length != 0) {
                while (!variables.toDict()[name].toList().empty()) variables.toDict()[name].toList().pop();
            } else {
                throw 'incorrect call to setq';
            }
        } catch (s: Dynamic) {
            variables.toDict()[name] = value;
        }
        if (list.length > 2) {
            return setq(List(list.slice(2)));
        } else {
            return value;
        }
    }

    function setlocal (l: HValue) {
        var list = l.toList();
        var name = symbolName(list[0]).toString();
        var watched = truthy(contains(watchedVariables, Atom(String(name))));

        if (watched) trace(l.toPrint());

        var value = eval(list[1]);
        var stackFrame: HDict = variables.toDict();
        if (stackFrames.toList().length > 0) {
            // By default, setlocal binds the variable at the current scope
            stackFrame = stackFrames.toList()[stackFrames.toList().length-1].toDict();
            // But if a higher scope already binds the variable, it will be modified instead. TODO or not??!?!?!
        }
        if (watched) trace('calling setlocal for $name on frame ${Dict(stackFrame).toPrint()} with ${stackFrames.length} frames and new value ${value.toPrint()} evaluated from ${list[1].toPrint()}');
        stackFrame[name] = value;
        if (list.length > 2) {
            return setlocal(List(list.slice(2)));
        } else {
            return value;
        }
    }

    function setNth(arr: HValue, idx: HValue, val: HValue) { 
        arr.toList()[idx.toInt()] = val; return arr;
    }

    function hissFor(args: HValue): HValue {
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
                    setlocal(List([name, Quote(v)]));

                    //trace('innter funcall');
                    eval(cons(Atom(Symbol("progn")), body));
                }]);
            default:
                Signal(Error('cannot call for loop on ${coll.toPrint()}'));
        }

        
        //return Nil;
    }

    function hissDoFor(args: HValue): HValue {
        var argList = args.toList();
        var name = argList[0];
        var coll = eval(argList[1]);
        //var coll = argList[1];


        var body: HValue = List(argList.slice(2));
        switch (coll) {
            case Object("IntIterator", o):
                var it: IntIterator = cast(eval(argList[1]).toObject(), IntIterator);
        
                for (v in it) {
                    setlocal(List([name, Atom(Int(v))]));

                    //trace('innter funcall');
                    var value = eval(cons(Atom(Symbol("progn")), body));
                    switch (value) {
                        case Signal(Continue):
                            continue;
                        case Signal(Break):
                            return Nil;
                        default:
                    }
                }
            case List(l):
                for (v in l) {
                    setlocal(List([name, Quote(v)]));

                    //trace('innter funcall');
                    var value = eval(cons(Atom(Symbol("progn")), body));
                    switch (value) {
                        case Signal(Continue):
                            continue;
                        case Signal(Break):
                            return Nil;
                        default:
                    }
                }
            default:
                Error('cannot call for loop on ${coll.toPrint()}');
        }

        
        return Nil;
    }

    function hissWhile(args: HValue){
        var argList = args.toList();
        var cond = argList[0];
        var body: HValue = List(argList.slice(1));
        
        while (truthy(eval(cond))) {
            //trace('innter funcall');
            var value = eval(cons(Atom(Symbol("progn")), body));
            switch (value) {
                case Signal(Break):
                    break;
                case Signal(Continue):
                    continue;
                default:
            }
        }
        return Nil;
    }

    function doList(list: HValue, func: HValue) {
        for (v in list.toList()) {
            
            //trace('calling ${funcInfo} with arg ${v}');
            funcall(func, List([v]), Nil);
        }
        return Nil;
    }

    function map(arr: HValue, func: HValue) {
        return List([for (v in arr.toList()) funcall(func, List([v]), Nil)]);
    }

    function dict(pairs: HValue) {
        var dict = new HDict();
        for (pair in pairs.toList()) {
            var key = nth(pair, Atom(Int(0))).toString();
            var value = eval(nth(pair, Atom(Int(1))));
            dict[key] = value;
        }
        return Dict(dict);
    }

    function setInDict(dict: HValue, key: HValue, value: HValue) {
        var dictObj: HDict = dict.toDict();
        dictObj[key.toString()] = value;
        return dict;
    }

    function eraseInDict(dict: HValue, key: HValue, value: HValue) {
        var dictObj: HDict = dict.toDict();
        dictObj.remove(key.toString());
        return dict;
    }

    function getInDict(dict: HValue, key: HValue) {
        var dictObj: HDict = dict.toDict();
        return if (dictObj[key.toString()] != null) dictObj[key.toString()] else Nil;
    }

    function keys(dict: HValue) {
        var dictObj: HDict = dict.toDict();
        return List([for (key in dictObj.keys()) Atom(String(key))]);
    }

    function charAt (str: HValue, idx: HValue) {
        return Atom(String(str.toString().charAt(idx.toInt())));
    }

    function substr(args: HValue){
        var l = args.toList();
        var str = l[0].toString();
        var start = l[1].toInt();
        var len: Null<Int> = null;
        if (l.length > 2) len = l[2].toInt();
        return Atom(String(str.substr(start, len)));
    }

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

    function indexOf(l: HValue, v: HValue): HValue {
        var list = l.toList();
        var idx = 0;
        for (lv in list) {
            if (Type.enumEq(v, lv)) return Atom(Int(idx));
            idx++;
        }
        return Nil;
    }

    function contains(l: HValue, v: HValue):HValue {
        return if (truthy(indexOf(l, v))) T else Nil;
    }

    public static function toDict(dict: HValue): HDict {
        return HissTools.extract(dict, Dict(h) => h);
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

    public static function reverse(list: HValue): HValue {
        var copy = list.toList().copy();
        copy.reverse();
        return List(copy);
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

        // watchedFunctions = ["filter"];
        //watchedFunctions = ["nth", "set-nth", "+", "progn"];
        //watchedFunctions = ["distance", "anonymous"];
        // watchedFunctions = ["intersection", "and", "not"];
        //watchedFunctions = ["dolist"];

        //var watchedFunctions = ['=', 'haxe=='];
        //var watchedFunctions = ["variadic-binop", "-", "haxe-", "funcall"];
        var watched = truthy(contains(variables.toDict()["watched-functions"], Atom(String(name))));

        var oldStackFrames = List(stackFrames.toList().copy());

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
            default:
        }
        

        if (watched) trace ('args before evalAll of $name are $args');
        var argVals = args;
        if (truthy(evalArgs)) {
            // trace('evaling args ${argVals.toPrint()} for $name');
            argVals = evalAll(args);
        }
        if (watched) trace ('args after evalAll are ${argVals.toPrint()}');

        var argList: HList = argVals.toList().copy();

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
                    var argStackFrame: HDict = [];
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
                            while (nameIdx < funDef.argNames.length) {
                                argStackFrame[funDef.argNames[nameIdx++]] = Nil;
                            }
                            break;
                        } else {
                            argStackFrame[arg] = argList[valIdx++];
                            nameIdx++;
                        }
                    }

                    // Functions bodies should be executed in their own cut-off stack frame without access to locals at the callsite
                    if (truthy(evalArgs)) {
                        while (!stackFrames.toList().empty()) stackFrames.toList().pop();
                        stackFrames.toList().push(Dict(argStackFrame));
                    } 
                    //  Macros should not!
                    else {
                        stackFrames.toList().push(Dict(argStackFrame));
                    }
                    
                    var lastResult = null;
                    for (expression in funDef.body) {
                        try {
                            if (watched) {
                                //trace('there are ${stackFrames.toList().length} stack frames when calling $name');
                                //trace('top stack frame:');
                                //trace(stackFrames.toList()[stackFrames.toList().length-1].toPrint());
                                //trace('variables:');
                                //trace(variables.toPrint());
                            } 
                            lastResult = eval(expression);
                        }/* catch (e: Dynamic) {
                            stackFrames = oldStackFrames;
                            throw e;
                        }*/
                    }

                    if (watched) trace('restoring stack frames from ${stackFrames.toPrint()} to ${oldStackFrames.toPrint()}');
                    while (!stackFrames.toList().empty()) stackFrames.toList().pop();
                    while (!oldStackFrames.toList().empty()) stackFrames.toList().push(oldStackFrames.toList().pop());
                    stackFrames.toList().reverse();
                    if (watched) trace('stack frames are ${stackFrames}');

                    //trace('returning ${lastResult.toPrint()} from ${func.toPrint()}');

                    return lastResult;
                default: throw 'cannot call $funcOrPointer as a function';
            }
        } catch (s: Dynamic) {
            trace('error $s while $message');
            stackFrames = oldStackFrames;
            throw s;
        }
    }

    /**
     * Behind the scenes function to retrieve the value and "address" of a variable,
     * using lexical scoping
     **/
    public function resolve(name: String): HVarInfo {
        var idx = stackFrames.toList().length-1;
        var value = null;
        var frame = null;
        while (value == null && idx >= 0) {
            frame = stackFrames.toList()[idx--].toDict();
            value = frame[name];
        }
        if (value == null) {
            value = variables.toDict()[name];
            frame = null;
        }

        var info =  { name: name, value: value, container: frame }

        var watched = truthy(contains(watchedVariables, Atom(String(name))));
        if (watched) {
            trace('var $name resolved with info ${VarInfo(info).toPrint()}');
        }

        return info;
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
        //trace('eval called on ${expr.toPrint()}');
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
                            trace('Tried to access undefined variable $name with stackFrames ${stackFrames.toPrint()}');
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
                    default: return Signal(Error('${expr.toPrint()}: ${funcInfo.toPrint()} is not a function pointer'));
                }
                if (funcInfo == null || value == null) { trace(funcInfo); }
                var args = rest(expr);

                // trace('calling funcall $funcInfo with args (before evaluation): $args');
                funcall(funcInfo, List(args.toList().copy()));
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
            case Signal(Error(m)):
                // TODO make a modifiable variable for whether to throw errors or return them
                expr;
                //throw m;
            case Signal(_):
                expr;
            default:
                throw 'Eval for type of expression ${expr} is not yet implemented';
        };
        if (value == null) {
            throw('Expression evaluated null: ${expr.toPrint()}');
        }
        //trace(expr);
        //trace(value);
        // trace('${expr.toPrint()} -> ${value.toPrint()}'); // Good for debugging crazy stuff
        //trace(value);
        return value;
    }
}