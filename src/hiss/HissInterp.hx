package hiss;

import haxe.macro.Context;

import hiss.HStream.HPosition;
import haxe.ds.ListSort;
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr;
using haxe.macro.ExprTools;
using hx.strings.Strings;
import hx.strings.StringBuilder;
import StringTools;
using StringTools;
import StringBuf;

import haxe.Resource;

using Lambda;

#if sys
import sys.io.File;
import sys.io.Process;
#end
import Reflect;
import Type;
using Type;

import hiss.HissReader;
import hiss.HTypes;

using hiss.HissInterp;
import hiss.HissTools;
using hiss.HissTools;
import hiss.HaxeTools;
using hiss.HaxeTools;

import uuid.Uuid;

class HissInterp {
    var stackFrames: HValue;
    public var variables: HValue;

    /** Debugging **/
    var watchedVariables: HValue;
    var watchedFunctions: HValue;

    public var functionStats: Map<String, Int> = new Map<String, Int>();

    // *
    static function symbolName(v: HValue): HValue {
        return Atom(String(HaxeTools.extract(v, Atom(Symbol(name)) => name, "symbol name")));
    }

    // Keep
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
    // Keep
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

    // Keep
    function lambda(args: HValue): HValue {
        var argNames = first(args).toList().map(s -> symbolName(s).toString());
        
        var body: HList = rest(args).toList();

        var def: HFunDef = {
            argNames: argNames,
            body: body
        };

        return Function(Hiss(def));
    }

    // *
    // TODO optional docstrings lollll
    function defun(args: HValue, isMacro: HValue = Nil) {
        var name = symbolName(first(args)).toString();
        functionStats[name] = 0;
        var fun: HValue = lambda(rest(args));
        if (truthy(isMacro)) {
            fun = Function(Macro(true, fun.toHFunction()));
        }
        variables.toDict()[name] = fun;
        return fun;
    }

    // *
    function defmacro(args: HValue): HValue {
        return defun(args, T);
    }
    
    // *
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
            variables.toDict()[$v{name}.toLowerHyphen()] = Function(Haxe(Fixed, $f, $v{name}.toLowerHyphen()));            
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
            variables.toDict()[$v{name}.toLowerHyphen() + "?"] = Function(Haxe(Fixed, $f, $v{name}));            
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
            return HissTools.toHValue($f(HissTools.valueOf(v)));
        }, $v{name}));
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
            return HissTools.toHValue($f(HissTools.valueOf(v), HissTools.valueOf(v2)));
        }, $v{name}));
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
            $f(HissTools.valueOf(v));
            return Nil;
        }));
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

        var code = 'variables.toDict()["$name"] = Function(Haxe(Fixed, (a,b) -> HissTools.toHValue(HissTools.valueOf(a) $op HissTools.valueOf(b)), "$name"))';

        var expr = Context.parse(code, Context.currentPos());
        return expr;
    }

    // *
    static function cons(hv: HValue, hl: HValue): HValue {
        var l = hl.toList().copy();
        l.insert(0, hv);
        return List(l);
    }

    // *
    function sort(args: HValue) {
        var argList = args.toList();
        var listToSort = argList[0].toList();
        var sortFunction: HValue = if (argList.length > 1 && argList[1] != Nil) argList[1] else variables.toDict()['compare'];
        
        var sorted = listToSort.copy();
        
        sorted.sort((v1:HValue, v2:HValue) -> {
            HissTools.valueOf(funcall(Nil, sortFunction, List([v1, v2])));
        });
        return List(sorted);
    }

    // *
    function readLine(args: HValue) {
        if (args.toList().length == 1) {
            HaxeTools.print(first(args).toString());
        }
        #if sys
            return Atom(String(Sys.stdin().readLine()));
        #else
            return Atom(String(""));
        #end
    }

    // *
    function getVariables() { return variables; }

    // *
    function progn(exps: HValue) {
        var value = null;
        for (exp in exps.toList()) {
            value = eval(exp);
            switch (value) {
                case Signal(Return(v)):
                    return v;
                // This block breaks `let` expressions where the expression is an error:
                /*case Signal(_):
                    return value;*/
                default:
            }
        }
        return value;
    }

    // *
    function makeList(exps: HValue) {
        return exps;
    }

    // *
    function quote(exp: HValue) {
        return exp;
    }

    // *
    function isError(exp: HValue) {
        return switch (exp) {
            case Signal(Error(_)):
                T;
            default:
                Nil;
        };
    }

    // *
    function int(value: HValue) {
        try {
            value.toInt();
            return T;
        } catch (s: Dynamic) {
            return Nil;
        }
    }

    // *
    function nil(value: HValue) {
        return if (value == Nil) T else Nil;
    }

    // *
    function bound(value: HValue) {
        return if (resolve(symbolName(value).toString()).value != null) T else Nil;
    }

    // *
    function list(value: HValue) {
        try {
            value.toList();
            return T;
        } catch (s: Dynamic) {
            return Nil;
        }
    }

    // *
    function hissReturn(value: HValue): HValue {
        return Signal(Return(value));
    }

    // *
    function hissContinue(): HValue {
        return Signal(Continue);
    }

    // *
    function hissBreak(): HValue {
        return Signal(Break);
    }

    // *
    function symbol(value: HValue) {
        try {
            symbolName(value);
            return T;
        } catch (s: Dynamic) {
            return Nil;
        }
    }

    // *
    function isString(value: HValue) {
        try {
            value.toString();
            return T;
        } catch (s: Dynamic) {
            return Nil;
        }
    }

    // *
    public function print(value: HValue) {
        HaxeTools.println(value.toPrint());
        return value;
    }

    // *
    public function uglyPrint(value: HValue) {
        HaxeTools.println(Std.string(value));
        return value;
    }

    // *
    public static function eq(a: HValue, b: HValue): HValue {
        if (Type.enumIndex(a) != Type.enumIndex(b)) {
            return Nil;
        }
        switch (a) {
            case Atom(_) | T | Nil:
                return if (Type.enumEq(a, b)) T else Nil;
            case List(_):
                var l1 = a.toList();
                var l2 = b.toList();
                if (l1.length != l2.length) return Nil;
                var i = 0;
                while (i < l1.length) {
                    if (!truthy(eq(l1[i], l2[i]))) return Nil;
                    i++;
                }
                return T;
            case Quote(aa) | Quasiquote(aa) | Unquote(aa) | UnquoteList(aa):
                var bb = HaxeTools.extract(b, Quote(e) | Quasiquote(e) | Unquote(e) | UnquoteList(e) => e);
                return eq(aa, bb);
            default:
                return Nil;
        }
    }

    // *
    function scopeIn(s: HValue = Nil) {
        if (s == Nil) {
            s = Dict(new HDict());
        }
        stackFrames.toList().push(s);
        return Nil;
    }

    // *
    function scopeOut() {
        stackFrames.toList().pop();
        return Nil;
    }

    // *
    function scopeReturn(v: HValue) {
        stackFrames.toList().pop();
        return v;
    }

    // *
    function error(message: HValue) {
        return Signal(Error(message.toString()));
    }

    public function importObject(name: String, obj: Dynamic) {
        variables.toDict()[name] = Object(Type.getClassName(Type.getClass(obj)), obj);
    }

    public function set(varName: String, value: Dynamic) {
        variables.toDict()[varName] = HissTools.toHValue(value);
    }

    public function new() {
        // Load the standard library and test files:
        StaticFiles.compileWith("stdlib.hiss");
        StaticFiles.compileWith("../../test/test-std.hiss");

        // The hiss standard library:
        variables = Dict([]);
        var vars: HDict = variables.toDict();

        vars['variables'] = Function(Haxe(Fixed, getVariables, "variables"));
        
        vars['Type'] = Object("Class", Type);
        vars['Strings'] = Object("Class", Strings);
        vars['empty-dict'] = Function(Haxe(Fixed, function() { return Dict([]); }, "empty-dict"));

        vars['return'] = Function(Haxe(Fixed, hissReturn, "return"));
        vars['break'] = Function(Haxe(Fixed, hissBreak, "break"));
        vars['continue'] = Function(Haxe(Fixed, hissContinue, "continue"));

        vars['nil'] = Nil;
        vars['null'] = Nil;
        vars['false'] = Nil;
        vars['t'] = T;
        vars['true'] = T;
               
        vars['sort'] = Function(Haxe(Var, sort, "sort"));

        //vars['import'] = Function(Haxe(Fixed, resolveClass, "import"));
        importWrapped2(this, Reflect.compare);
        
        //importWrapped(this, toUpperHyphen);
        importFixed(intern);
        
        importFixed(getProperty);
        importFixed(callMethod);

        vars['read-line'] = Function(Haxe(Var, readLine, "read-line"));

        // Control flow
        vars['if'] = Function(Macro(false, Haxe(Fixed, hissIf, "if")));

        vars['progn'] = Function(Macro(false, Haxe(Var, progn, "progn")));

        vars['list'] = Function(Haxe(Var, makeList, "list"));

        vars['quote'] = Function(Macro(false, Haxe(Fixed, quote, "quote")));

        importPredicate(nil);
        importPredicate(bound);
        importPredicate(int);
        importPredicate(list);
        importPredicate(symbol);
        vars['string?'] = Function(Haxe(Fixed, isString, "string?"));
        vars['error?'] = Function(Haxe(Fixed, isError, "error?"));

        // Haxe std io
        importFixed(print);
        importFixed(uglyPrint);

        importFixed(HissReader.read);
        importFixed(HissReader.readAll);
        importFixed(HissReader.readString);
        importFixed(HissReader.readNumber);
        importFixed(HissReader.readSymbol);
        importFixed(HissReader.readDelimitedList);
        importFixed(HissReader.setMacroString);
        importFixed(HissReader.setDefaultReadFunction);

        importFixed(eval);

        importFixed(first);
        importFixed(rest);
        importFixed(nth);

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

        // Some binary operators are Lisp-compatible as-is
        importBinops(false, "%");  

        vars['lambda'] = Function(Macro(false, Haxe(Var, lambda, "lambda")));
        vars['defun'] = Function(Macro(false, Haxe(Var, defun, "defun")));
        vars['defmacro'] = Function(Macro(false, Haxe(Var, defmacro, "defmacro")));

        importFixed(cons);

        importFixed(resolve);
        vars['funcall'] = Function(Haxe(Fixed, funcall.bind(Nil), "funcall"));
        
        vars['scope-in'] = Function(Haxe(Fixed, scopeIn, "scope-in"));
        vars['scope-out'] = Function(Haxe(Fixed, scopeOut, "scope-out"));
        vars['scope-return'] = Function(Haxe(Fixed, scopeReturn, "scope-return"));
        
        vars['error'] = Function(Haxe(Fixed, error, "error"));

        // TODO strings with interpolation

        //importFixed(string);        
        vars['setq'] = Function(Macro(false, Haxe(Var, setq, "setq")));
        vars['setlocal'] = Function(Macro(false, Haxe(Var, setlocal, "setlocal")));

        vars['set-nth'] = Function(Haxe(Fixed, setNth, "set-nth"));

        vars['for'] = Function(Macro(false, Haxe(Var, hissFor, "for")));

        vars['do-for'] = Function(Macro(false, Haxe(Var, hissDoFor, "do-for")));

        vars['while'] = Function(Macro(false, Haxe(Var, hissWhile, "while")));
        
        watchedFunctions = List([]);
        watchedVariables = List([]);
        stackFrames = List([]);

        // TODO make these all imported getters
        vars['*watched-functions*'] = watchedFunctions;
        vars['*watched-vars*'] = watchedVariables;
        vars['*stack-frames*'] = stackFrames;

        // Import enums and stuff
        //importEnum(haxe.ds.Option);

        //try {
            // TODO obviously this needs to happen
        //} catch (s: Dynamic) {
            // This catch expression makes things unsafe, and even if it is there, this trace should be uncommented eventually:
            // trace('Error loading the standard library: $s');
        //}
    }

    /** Get a field out of a container (object/class) **/
    function getProperty(container: HValue, field: HValue, byReference: HValue = Nil) {
        try {
            return HissTools.toHValue(Reflect.getProperty(HissTools.valueOf(container, truthy(byReference)), field.toString()));
        } catch (s: Dynamic) {
            throw 'Cannot retrieve field `${field.toString()}` from object $container because $s';
        }
    }

    function callMethod(container: HValue, method: HValue, ?args: HValue, ?callOnReference: HValue = Nil, ?keepArgsWrapped: HValue = Nil) {
        if (args == null) args = List([]);
        if (callOnReference == null) callOnReference = Nil;
        if (keepArgsWrapped == null) keepArgsWrapped = Nil;
        var callArgs: Array<Dynamic> = args.toList();
        if (!truthy(keepArgsWrapped)) {
            callArgs = HissTools.unwrapList(args);
        }
        try {
            return HissTools.toHValue(Reflect.callMethod(HissTools.valueOf(container, truthy(callOnReference)), HissTools.toFunction(getProperty(container, method, callOnReference)), callArgs));
        } catch (s: Dynamic) {
            return Signal(Error('Cannot call method `${method.toString()}` from object $container because $s'));
        }
    }

    function contains(list: HValue, v: HValue): HValue {
        for (val in list.toList()) {
            if (eq(v, val) != Nil) return T;
        }

        return Nil;
    }

    // *
    function setq(l: HValue): HValue {
        var list = l.toList();
        var name = HissTools.toString(symbolName(list[0]));
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

    // *
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
        if (watched) trace('calling setlocal for $name on frame ${Dict(stackFrame).toPrint()} with ${stackFrames.toList().length} frames and new value ${value.toPrint()} evaluated from ${list[1].toPrint()}');
        stackFrame[name] = value;
        if (list.length > 2) {
            return setlocal(List(list.slice(2)));
        } else {
            return value;
        }
    }

    // *
    function setNth(arr: HValue, idx: HValue, val: HValue) { 
        arr.toList()[idx.toInt()] = val; return arr;
    }

    // *
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

                    eval(cons(Atom(Symbol("progn")), body));
                }]);
            case List(l):
                List([for (v in l) {
                    setlocal(List([name, Quote(v)]));

                    eval(cons(Atom(Symbol("progn")), body));
                }]);
            default:
                Signal(Error('cannot call for loop on ${coll.toPrint()}'));
        }

        
        //return Nil;
    }

    // *
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

    // *
    function hissWhile(args: HValue){
        var argList = args.toList();
        var cond = argList[0];
        var body: HValue = List(argList.slice(1));
        
        while (truthy(eval(cond))) {
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

    // *
    public static function first(list: HValue): HValue {
        var v = list.toList()[0];
        if (v == null) v = Nil;
        return v;
    }

    // *
    public static function rest(list: HValue): HValue {
        return List(list.toList().slice(1));
    }

    // keep
    public static function nth(list: HValue, idx: HValue):HValue {
        return list.toList()[idx.toInt()];
    }

    // *
    function evalAll(hl: HValue): HValue {
        return List([for (exp in hl.toList()) eval(exp)]);
    }

    public function funcall(evalArgs: HValue, funcOrPointer: HValue, args: HValue): HValue {
        var container = null;
        var name = "anonymous";
        var func = funcOrPointer;
        //trace(func);
        switch (funcOrPointer) {    
            case VarInfo(v):
                name = v.name;
                container = v.container;
                func = v.value;
            case Function(Haxe(_, _, fname)):
                name = fname;
            case Function(Macro(_, Haxe(_, _, fname))):
                name = fname;
            default:
        }

        if (!functionStats.exists(name)) functionStats[name] = 0;
        functionStats[name] = functionStats[name] + 1;

        var watched = truthy(contains(variables.toDict()["*watched-functions*"], Atom(String(name))));

        var oldStackFrames = List(stackFrames.toList().copy());

        switch (func) {
            case Function(Macro(e, m)):
                var macroExpansion = funcall(Nil, Function(m), args);
                if (watched)
                     trace('macroexpansion $name ${func.toPrint()} -> ${macroExpansion.toPrint()}');
                return if (e) {
                    eval(macroExpansion);
                } else {
                    macroExpansion;
                };
            default:
        }
        

        
        var argVals = args;
        if (truthy(evalArgs)) {
            argVals = evalAll(args);
        }

        var argList: HList = argVals.toList().copy();

        // TODO trace the args

        var hfunc = func.toHFunction();

        var message = 'calling `$name`: $hfunc with args ${argVals.toPrint()}';
        if (watched) trace(message);

        try {
            switch (hfunc) {
                case Haxe(t, hxfunc, fname):
                    name = fname;
                    switch (t) {
                        case Var: 
                            argList = [List(argList)];
                        case Fixed:
                    }

                    message += ". Are you sure you are passing the right arguments?";
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
                            lastResult = eval(expression);
                        } catch (e: Dynamic) {
                            stackFrames = oldStackFrames;
                            throw e;
                        }
                    }

                    while (!stackFrames.toList().empty()) stackFrames.toList().pop();
                    while (!oldStackFrames.toList().empty()) stackFrames.toList().push(oldStackFrames.toList().pop());
                    stackFrames.toList().reverse();
                    
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

    // *
    public function evalUnquotes(expr: HValue): HValue {
        switch (expr) {
            case List(exps):
                var copy = exps.copy();
                // If any of exps is an UnquoteList, expand it and insert the values at that index
                var idx = 0;
                while (idx < copy.length) {
                    switch (copy[idx]) {   
                        case UnquoteList(exp):
                            copy.splice(idx, 1);
                            var innerList = eval(exp);
                            for (exp in innerList.toList()) {
                                
                                copy.insert(idx++, exp);
                            }
                        default:
                            var exp = copy[idx];
                            copy.splice(idx, 1);
                            copy.insert(idx, evalUnquotes(exp));
                    }
                    idx++;
 
                }
                return List(copy);
            case Quote(exp):
                return Quote(evalUnquotes(exp));
            case Unquote(h):
                return eval(h);
            case Quasiquote(exp):
                return evalUnquotes(exp);
            default: return expr;
        };
    }

    // *
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
                            // TODO make this error message come back!
                            // trace('Tried to access undefined variable $name with stackFrames ${stackFrames.toPrint()}');
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
                    default: 
                        return Signal(Error('${expr.toPrint()}: ${funcInfo.toPrint()} is not a function pointer'));
                }
                if (funcInfo == null || value == null) { trace(funcInfo); }
                var args = rest(expr);

                // trace('calling funcall $funcInfo with args (before evaluation): $args');
                funcall(T, funcInfo, List(args.toList().copy()));
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
                print(expr);
                // TODO make a modifiable variable for whether to throw errors or return them
                expr;
                //throw m;
            case Signal(_):
                expr;
            case Object(_, _):
                expr;
            default:
                throw 'Eval for type of expression ${expr} is not yet implemented';
        };
        if (value == null) {
            throw('Expression evaluated null: ${expr.toPrint()}');
        }
        // trace('${expr.toPrint()} -> ${value.toPrint()}'); // Good for debugging crazy stuff
        return value;
    }
}