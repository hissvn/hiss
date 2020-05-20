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

import hiss.HTypes.HValue;

import uuid.Uuid;
import Sys;

class HissInterp {
    var stackFrames: HValue;
    public var variables: HValue;

    public var functionStats: Map<String, Int> = new Map<String, Int>();

    

    /**
     * Implementation of the `if` macro. Returns value of `thenExp` if condition is truthy, else * evaluates `elseExp`
     **/
    // Keep
    function hissIf(condExp: HValue, thenExp: HValue, elseExp: Null<HValue>) {
        var cond = eval(condExp);
        return if (HissTools.truthy(cond)) {
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
        var argNames = HissTools.first(args).toList().map(s -> HissTools.symbolName(s).toHaxeString());
        
        var body: HList = HissTools.rest(args).toList();

        var def: HFunDef = {
            argNames: argNames,
            body: body
        };

        return Function(Hiss(def));
    }

    // Keep
    // TODO optional docstrings lollll
    function defun(args: HValue, isMacro: HValue = Nil) {
        var name = HissTools.symbolName(HissTools.first(args)).toHaxeString();
        functionStats[name] = 0;
        var fun: HValue = lambda(HissTools.rest(args));
        if (HissTools.truthy(isMacro)) {
            fun = Function(Macro(true, fun.toHFunction()));
        }
        variables.toDict()[name] = fun;
        return fun;
    }

    // Keep
    function defmacro(args: HValue): HValue {
        return defun(args, T);
    }

    public static macro function importFunction(f: Expr, argType: Expr, suffix: Expr) {
        var name = switch(f.expr) {
            case EConst(CIdent(s)) | EField(_, s):
                s.toLowerHyphen();
            default:
                throw "Failed to get function name";
        }
        return macro {
            var vname = $v{name} + $suffix;
            functionStats[vname] = 0;
            variables.toDict()[vname] = Function(Haxe($argType, $f, vname));            
        };
    }

    static macro function importMacro(f: Expr, argType: Expr, name: Expr) {
        return macro {
            variables.toDict()[$name] = Function(Macro(false, Haxe($argType, $f, $name)));
        }
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

    // Sort can't be ported because it has to convert hiss function definitions into Haxe function types.
    // This is almost possible through witchcraft, but in the end it isn't because Haxe doesn't support varargs.
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

    // Keep
    function progn(exps: HValue) {
        var value = null;
        for (exp in exps.toList()) {
            value = eval(exp);
            switch (value) {
                case Return(v):
                    return v;
                case Error(m):
                    return value;
                default:
            }
        }
        return value;
    }

    // not portable to Hiss because it checks for Haxe null
    function bound(value: HValue) {
        return if (resolve(HissTools.symbolName(value).toHaxeString()).value != null) T else Nil;
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

    // Keep
    // This predicate has to be a Haxe function because a hiss function's implicit progn will always return the error without catching it
    function error(exp: HValue) {
        return switch (exp) {
            case Error(_):
                T;
            default:
                Nil;
         };
    }

    public function importObject(name: String, obj: Dynamic) {
        variables.toDict()[name] = Object(Type.getClassName(Type.getClass(obj)), obj);
    }

    public function set(varName: String, value: Dynamic) {
        variables.toDict()[varName] = HissTools.toHValue(value);
    }

    // This has to be in Haxe because of the implicit progn in funcall.
    function _return(value: HValue): HValue {
        return Return(value);
    }

    public function new() {
        // Load the standard library and test files:
        StaticFiles.compileWith("stdlib.hiss");
        StaticFiles.compileWith("../../test/test-std.hiss");

        // The hiss standard library:
        variables = Dict([]);
        var vars: HDict = variables.toDict();

        stackFrames = List([]);
        vars['*stack-frames*'] = stackFrames;

        // Access to the variable dictionary allows setq to be a Hiss macro
        vars['*variables*'] = variables;

        vars['*interp*'] = Object("HissInterp", this);

        // Variables (Can keep all of these statements with no maintenance overhead)
        vars['Type'] = Object("Class", Type);
        vars['Strings'] = Object("Class", Strings);
        vars['H-Value'] = Object("Enum", HValue);
        vars['Hiss-Tools'] = Object("Class", HissTools);
        vars['nil'] = Nil;
        vars['null'] = Nil;
        vars['false'] = Nil;
        vars['t'] = T;
        vars['true'] = T;

        /**
            Functions implemented in Haxe with unnecessary maintainence overload
            Some of these may not be portable to pure Hiss, but they can still be moved out of HissInterp
            and brought into the Hiss environment with (register-function) instead of import macros.
        **/
        {
            importMacro(setlocal, Var, "setlocal");

            // Haxe std io
            importFunction(print, Fixed, "");
            importFunction(uglyPrint, Fixed, "");
            // Control flow
            importMacro(hissIf, Fixed, "if");
            importMacro(progn, Var, "progn");
            importMacro(hissDoFor.bind(T), Var, "for");
            importMacro(hissDoFor.bind(Nil), Var, "do-for");
            importMacro(hissWhile, Var, "while");

            vars['funcall'] = Function(Haxe(Fixed, funcall.bind(Nil), "funcall")); // Can this be imported and apply-partiallied?

            // most haxe binary operators are non-binary (like me!) in most Lisps.
            // They can take any number of arguments.
            // Since we still need haxe to run the computations, Hiss imports those binary
            // operators, but hides them with the prefix 'haxe' to it can provide its own
            // lispy (variadic) operator functions.
            importBinops(true, "+", "-", "/", "*", ">", ">=", "<", "<=", "==");

            // Some binary operators are Lisp-compatible as-is
            importBinops(false, "%"); 

            // We don't need && or || because they only operate on booleans (which Hiss doesn't have).
            // But we do import the ... range operator because ranges are nice so why not
            importBinops(true, "...");
        }

        /**
            Primitives -- Functions implemented in Haxe that might be impossible to port to Hiss/worth keeping around
        **/
        {
            // These are the reflective functions that make so many cool things possible:
            importFunction(getProperty, Fixed, "");
            importFunction(callMethod, Fixed, "");

            importFunction(eval, Fixed, "");

            // I can't believe I tried to port lambda....
            importMacro(lambda, Var, "lambda");
            importMacro(defun, Var, "defun");
            importMacro(defmacro, Var, "defmacro");

            // These are primitives for counter-intuitive, possibly
            // work-around-able reasons:
            importFunction(bound, Fixed, "?");
            importFunction(error, Fixed, "?");
            importFunction(_return, Fixed, "");
            importFunction(sort, Var, "");
        }
    }

    /** Get a field out of a container (object/class) **/
    function getProperty(container: HValue, field: HValue, byReference: HValue = Nil) {
        try {
            return HissTools.toHValue(Reflect.getProperty(HissTools.valueOf(container, HissTools.truthy(byReference)), field.toHaxeString()));
        } catch (s: Dynamic) {
            throw 'Cannot retrieve field `${field.toHaxeString()}` from object $container because $s';
        }
    }

    function callMethod(container: HValue, method: HValue, ?args: HValue, ?callOnReference: HValue = Nil, ?keepArgsWrapped: HValue = Nil) {
        if (args == null) args = List([]);
        var callArgs: Array<Dynamic> = HissTools.unwrapList(args, keepArgsWrapped);
        try {
            return HissTools.toHValue(Reflect.callMethod(HissTools.valueOf(container, HissTools.truthy(callOnReference)), HissTools.toFunction(getProperty(container, method, callOnReference)), callArgs));
        } catch (s: Dynamic) {
            return Error('Cannot call method `${method.toHaxeString()}` from object $container because $s');
        }
    }

    // *
    function setlocal (l: HValue) {
        var list = l.toList();
        var name = HissTools.symbolName(list[0]).toHaxeString();

        var value = eval(list[1]);
        var stackFrame: HDict = variables.toDict();
        if (stackFrames.toList().length > 0) {
            // By default, setlocal binds the variable at the current scope
            stackFrame = stackFrames.toList()[stackFrames.toList().length-1].toDict();
            // But if a higher scope already binds the variable, it will be modified instead. TODO or not??!?!?!
        }
        stackFrame[name] = value;
        if (list.length > 2) {
            return setlocal(List(list.slice(2)));
        } else {
            return value;
        }
    }

    // Keep
    function hissDoFor(collect: HValue, args: HValue): HValue {
        var argList = args.toList();
        var name = argList[0];
        var coll = eval(argList[1]);
        //var coll = argList[1];

        var results = [];

        var body: HValue = List(argList.slice(2));
        var iterator: Iterator<Dynamic> = switch (coll) {
            case Object("IntIterator", o):
                cast(eval(argList[1]).toObject(), IntIterator);
            case List(l):
                l.iterator();
            default:
                throw 'cannot call for loop on ${coll.toPrint()}';
        }
        
        for (v in iterator) {
            setlocal(List([name, Quote(HissTools.toHValue(v))]));

            var value = progn(body);
            switch (value) {
                case Continue:
                    continue;
                case Break:
                    return if (HissTools.truthy(collect)) List(results) else Nil;
                default:
                    if (HissTools.truthy(collect)) {
                        results.push(value);
                    }
            }
        }

        if (HissTools.truthy(collect)) {
            return List(results);
        }
        return Nil;
    }

    // Keep
    function hissWhile(args: HValue){
        var argList = args.toList();
        var cond = argList[0];
        var body: HValue = List(argList.slice(1));
        
        while (HissTools.truthy(eval(cond))) {
            var value = progn(body);
            switch (value) {
                case Break:
                    break;
                case Continue:
                    continue;
                default:
            }
        }
        return Nil;
    }

    // Keep
    public function funcall(evalArgs: HValue, funcOrPointer: HValue, args: HValue): HValue {
        var container = null;
        var name = "anonymous";
        var func = funcOrPointer;
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

        var oldStackFrames = List(stackFrames.toList().copy());

        switch (func) {
            case Function(Macro(e, m)):
                var macroExpansion = funcall(Nil, Function(m), args);
                return if (e) {
                    eval(macroExpansion);
                } else {
                    macroExpansion;
                };
            default:
        }
        
        var argVals = args;
        if (HissTools.truthy(evalArgs)) {
            argVals = List([for (exp in argVals.toList()) eval(exp)]);
        }

        var argList: HList = argVals.toList().copy();

        // TODO trace the args

        var hfunc = func.toHFunction();

        var argRep = if (argVals.toList().length > 10) {
            "an unreasonable number of arguments";
        } else {
            argVals.toPrint();
        }
        var message = 'calling `$name`: $hfunc with args ${argRep}';

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
                    if (HissTools.truthy(evalArgs)) {
                        while (!stackFrames.toList().empty()) stackFrames.toList().pop();
                        stackFrames.toList().push(Dict(argStackFrame));
                    } 
                    //  Macros should not!
                    else {
                        stackFrames.toList().push(Dict(argStackFrame));
                    }
                    
                    var result = progn(List(funDef.body));
                    
                    stackFrames = oldStackFrames;
                    // This extra step is required so Hiss code still has a valid reference to stackFrames:
                    variables.toDict()["*stack-frames*"] = stackFrames;
                    
                    return result;
                default: throw 'cannot call $funcOrPointer as a function';
            }
        } 
        #if !throwErrors
        catch (s: Dynamic) {
            //trace('error $s while $message');
            stackFrames = oldStackFrames;
            return Error(s);
        }
        #end
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
                        // If an UnquoteList is quoted, apply the quote to each expression in the list
                        case Quote(UnquoteList(exp)):
                            copy.splice(idx, 1);
                            var innerList = eval(exp);
                            for (exp in innerList.toList()) { 
                                copy.insert(idx++, Quote(exp));
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

    // Keep
    public function eval(expr: HValue, returnScope: HValue = Nil): HValue {
        var value = switch (expr) {
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
                if (HissTools.truthy(returnScope)) {
                    VarInfo(varInfo);
                } else {
                    varInfo.value;
                }
            case List([]):
                Nil;
            case List(exps):
                var func = eval(HissTools.first(expr), T);
                var args = HissTools.rest(expr);

                // trace('calling funcall $funcInfo with args (before evaluation): $args');
                funcall(T, func, List(args.toList().copy()));
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
                //print(expr);
                // TODO make a modifiable variable for whether to throw errors or return them
                expr;
                //throw m;
            /*case Break:
                expr;
            case Continue;
                expr;*/
            case Object(_, _):
                expr;
            default:
                Error('Eval for type of expression ${expr} is not yet implemented');
        };
        if (value == null) {
            return Error('Expression evaluated null: ${expr.toPrint()}');
        }
        // trace('${expr.toPrint()} -> ${value.toPrint()}'); // Good for debugging crazy stuff
        return value;
    }
}