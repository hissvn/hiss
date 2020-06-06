package hiss;

import Type;
import Reflect;
using Reflect;
import haxe.CallStack;
import haxe.Constraints.Function;

import hiss.HTypes;
#if sys
import ihx.ConsoleReader;
#end
import hiss.HissReader;
import hiss.HissTools;
using hiss.HissTools;
import hiss.StaticFiles;

using StringTools;

@:build(hiss.BinopsBuilder.build())
class HaxeBinops {

}

class CCInterp {
    var globals: HValue = Dict([]);
    var reader: HissReader;

    var tempTrace: Dynamic = null;
    var readingProgram = false;
    var maxStackDepth = 0;

    function disableTrace() {
        // On non-sys targets, trace is the only option
        tempTrace = haxe.Log.trace;
        haxe.Log.trace = (str, ?posInfo) -> {};
    }

    function enableTrace() {
        if (tempTrace != null) haxe.Log.trace = tempTrace;
    }

    function importFunction(func: Function, name: String, keepArgsWrapped: HValue) {
        globals.put(name, Function((args: HValue, env: HValue, cc: Continuation) -> {
            cc(Reflect.callMethod(null, func, args.unwrapList(keepArgsWrapped)).toHValue());
        }, name));
    }

    function importMethod(method: String, name: String, callOnReference: Bool, keepArgsWrapped: HValue, returnInstance: Bool) {
        globals.put(name, Function((args: HValue, env: HValue, cc: Continuation) -> {
            var instance = args.first().value(callOnReference);
            cc(instance.callMethod(instance.getProperty(method), args.rest().unwrapList(keepArgsWrapped)).toHValue());
        }, name));
    }

    public function new() {
        reader = new HissReader(this);

        // Primitives
        globals.put("setlocal", SpecialForm(set.bind(false)));
        globals.put("defvar", SpecialForm(set.bind(true)));
        globals.put("defun", SpecialForm(setCallable.bind(false)));
        globals.put("defmacro", SpecialForm(setCallable.bind(true)));
        globals.put("if", SpecialForm(_if));
        globals.put("lambda", SpecialForm(lambda.bind(false)));
        globals.put("call/cc", SpecialForm(callCC));
        globals.put("eval", Function(_eval, "eval"));
        globals.put("bound?", SpecialForm(bound));
        globals.put("load", Function(load, "load"));
        globals.put("funcall", SpecialForm(funcall.bind(false)));
        globals.put("funcall-inline", SpecialForm(funcall.bind(true)));
        // Use tail-recursive begin for loading the prelude:
        globals.put("begin", SpecialForm(trBegin));

        // Haxe interop -- We could bootstrap the rest from these if we had unlimited stack frames:
        globals.put("Type", Object("Class", Type));
        globals.put("Hiss-Tools", Object("Class", HissTools));
        globals.put("get-property", Function(getProperty, "get-property"));
        globals.put("call-haxe", Function(callHaxe, "call-haxe"));

        // Functions/forms that could be bootstrapped with register-function, but save stack frames if not:
        importFunction(HissTools.print, "print", T);
        importFunction(HissTools.length, "length", T);
        importFunction(HissTools.first, "first", T);
        importFunction(HissTools.rest, "rest", T);
        importFunction(HissTools.eq, "eq", T);
        importFunction(HissTools.nth, "nth", T);
        importFunction(HissTools.cons, "cons", T);
        importFunction(HissTools.not, "not", T);
        globals.put("quote", SpecialForm(quote));


        StaticFiles.compileWith("stdlib2.hiss");

        disableTrace();
        load(List([String("stdlib2.hiss")]), List([]), (hval) -> {});
        enableTrace();
    }

    public static function main() {
        var interp = new CCInterp();
        StaticFiles.compileWith("debug.hiss");
        #if sys
        var cReader = new ConsoleReader();        
        var locals = List([Dict([])]); // This allows for top-level setlocal

        while (true) {
            HaxeTools.print(">>> ");
            cReader.cmd.prompt = ">>> ";

            var next = cReader.readLine();

            interp.disableTrace();
            var exp = interp.read(next);
            interp.enableTrace();

            interp.eval(exp, locals, HissTools.print);
        }
        #else
        // An interactive repl isn't possible on non-sys platforms, so just run a test program.
        interp.load(List([String("debug.hiss")]), List([]), (hval) -> {});
        #end
    }

    function load(args: HValue, env: HValue, cc: Continuation) {
        readingProgram = true;
        var exps = reader.readAll(String(StaticFiles.getContent(args.first().value())));
        readingProgram = false;

        // Use a tail-recursive begin() call because programs can be long
        // and we can't keep descending in the stack:
        trBegin(exps, env, cc);
    }

    /**
        This tail-recursive implementation of begin breaks callCC,
        so it is only used internally.
    **/
    function trBegin(exps: HValue, env: HValue, cc: Continuation) {
        var value = Nil;
        eval(exps.first(), env, (result) -> {
            value = result;
        });

        if (!exps.rest().truthy()) {
            cc(value);
        }
        else {
            trBegin(exps.rest(), env, cc);
        }
    }

    function begin(exps: HValue, env: HValue, cc: Continuation) {
        eval(exps.first(), env, (result) -> {
            if (!exps.rest().truthy()) {
                cc(result);
            }
            else {
                begin(exps.rest(), env, cc);
            }
        });
    }

    inline function specialForm(args: HValue, env: HValue, cc: Continuation) {
        args.first().toCallable()(args.rest(), env, cc);
    }

    inline function macroCall(args: HValue, env: HValue, cc: Continuation) {
        specialForm(args, env, (expansion: HValue) -> {
            //HaxeTools.println(' ${expansion.toPrint()}');
            eval(expansion, env, cc);
        });
    }

    function funcall(callInline: Bool, args: HValue, env: HValue, cc: Continuation) {
        evalAll(args, env, (values) -> {
            // trace(values.toPrint());
            values.first().toHFunction()(values.rest(), if (callInline) env else List([]), cc);
        });
    }

    inline function evalAll(args: HValue, env: HValue, cc: Continuation) {
        if (!args.truthy()) {
            cc(Nil);
        } else {
            eval(args.first(), env, (value) -> {
                evalAll(args.rest(), env, (value2) -> {
                    cc(value.cons(value2));
                });
            });
        }
    }

    function or(args: HValue, env: HValue, cc: Continuation) {

    }

    function quote(args: HValue, env: HValue, cc: Continuation) {
        cc(args.first());
    }

    function set(global: Bool, args: HValue, env: HValue, cc: Continuation) {
        eval(args.second(),
            env, (val) -> {
                var scope = if (global) {
                    globals;
                } else {
                    env.first();
                }
                scope.put(args.first().symbolName(), val);
                cc(val);
            });
    }

    function setCallable(isMacro: Bool, args: HValue, env: HValue, cc: Continuation) {
        lambda(isMacro, args.rest(), env, (fun: HValue) -> {
            set(true, args.first().cons(List([fun])), env, cc);
        }, args.first().symbolName());
    }

    function _if(args: HValue, env: HValue, cc: Continuation) {
        eval(args.first(), env, (val) -> {
            if (val.truthy()) {
                eval(args.second(), env, cc);
            } else if (args.length() > 2) {
                eval(args.third(), env, cc);
            } else {
                cc(Nil);
            }
        });
    }

    /** Callable form for eval **/
    function _eval(args: HValue, env: HValue, cc: Continuation) {
        eval(args.first(), env, cc);
    }

    inline function getVar(name: HValue, env: HValue, cc: Continuation) {
        // Env is a list of dictionaries -- stack frames
        var stackFrames = env.toList();

        var g = globals.toDict();
        var name = name.symbolName();

        var v = Nil;
        for (frame in stackFrames) {
            var frameDict = frame.toDict();
            if (frameDict.exists(name)) {
                v = frameDict[name];
                break;
            }
        }
        cc(if (v != Nil) {
            v;
        } else if (g.exists(name)) {
            g[name];
        } else {
            Nil;
        });
    }

    function lambda(isMacro: Bool, args: HValue, env: HValue, cc: Continuation, name = "[anonymous lambda]") {
        var params = args.first();

        // TODO do I need a switch here to decide whether to use tail-recursive begin or not?!

        // like, lambda vs. tr-lambda


        var body = Symbol('begin').cons(args.rest());
        var hFun: HFunction = (fArgs, env, fCC) -> {
            var callEnv = env.extend(params.destructuringBind(fArgs)); // extending the outer env is how lambdas capture values
            eval(body, callEnv, fCC);
        };
        var callable = if (isMacro) {
            Macro(hFun);
        } else {
            Function(hFun, "[anonymous lambda]");
        };
        cc(callable);
    }

    function bound(args: HValue, env: HValue, cc: Continuation) {
        var stackFrames = env.toList();
        var g = globals.toDict();
        var name = args.first().symbolName();

        for (frame in stackFrames) {
            var frameDict = frame.toDict();
            if (frameDict.exists(name)) {
                cc(T);
            }
        }
        cc(if (g.exists(name)) {
            T;
        } else {
            Nil;
        });
    }

    function getProperty(args: HValue, env: HValue, cc: Continuation) {
        cc(Reflect.getProperty(args.first().value(true), args.second().toHaxeString()).toHValue());
    }

    /**
        Special form for calling Haxe functions and methods from within Hiss.

        args will be destructured like so:

        1. caller - class or object
        2. method - name of method or function on caller
        3. args (default empty list) - list of function arguments
        4. callOnReference (default Nil) - if T, a direct reference to caller will call the method, for when side-effects are desirable
        5. keepArgsWrapped (default Nil) - list of argument indices that should be passed in HValue form, rather than as Haxe Dynamic values. Nil for none, T for all.
    **/
    function callHaxe(args: HValue, env: HValue, cc: Continuation) {
        var callOnReference = if (args.length() < 4) {
            false;
        } else {
            args.nth(Int(3)).truthy();
        };
        var keepArgsWrapped = if (args.length() < 5) {
            Nil;
        } else {
            args.nth(Int(4));
        };

        //HaxeTools.println('calling haxe ${args.second().toHaxeString()} on ${args.first().toPrint()}');
        var caller = args.first().value(callOnReference);
        var method = Reflect.getProperty(caller, args.second().toHaxeString());
        var haxeCallArgs = args.third().unwrapList(keepArgsWrapped);

        cc(Reflect.callMethod(caller, method, haxeCallArgs).toHValue());
    }

    // 59 for 3 prints while imported
    // 17 for 3 prints while like this:
    function print(args: HValue, env: HValue, cc: Continuation) {
        args.first().print();
        cc(args.first());
    }

    function callCC(args: HValue, env: HValue, cc: Continuation) {
        // Convert the continuation to a hiss function accepting one argument
        var ccHFunction = Function((innerArgs: HValue, innerEnv: HValue, innerCC: Continuation) -> {
            globals.put("begin", SpecialForm(trBegin));
            
            //trace('cc was called with ${innerArgs.first().toPrint()}');
            // It's typical to JUST want to break out of a sequence, not return a value to it.
            if (!innerArgs.truthy()) cc(Nil);
            else cc(innerArgs.first());
        }, "cc");

        // Training wheels off. Give Hiss users the callCC-enabled, dangerous begin()
        globals.put("begin", SpecialForm(begin));
        funcall(true,
            List([
                args.first(),
                ccHFunction]),
            env, 
            cc);
    }

    // This breaks the continuation-based signature rules because I just want it to work.
    public inline function evalUnquotes(expr: HValue, env: HValue): HValue {
        switch (expr) {
            case List(exps):
                var copy = exps.copy();
                // If any of exps is an UnquoteList, expand it and insert the values at that index
                var idx = 0;
                while (idx < copy.length) {
                    switch (copy[idx]) {
                        case UnquoteList(exp):
                            copy.splice(idx, 1);

                            eval(exp, env, (innerList) -> {
                                for (exp in innerList.toList()) { 
                                    copy.insert(idx++, exp);
                                }
                            });
                        // If an UnquoteList is quoted, apply the quote to each expression in the list
                        case Quote(UnquoteList(exp)):
                            copy.splice(idx, 1);
                            eval(exp, env, (innerList) -> {
                                for (exp in innerList.toList()) { 
                                    copy.insert(idx++, Quote(exp));
                                }
                            });
                        default:
                            var exp = copy[idx];
                            copy.splice(idx, 1);
                            copy.insert(idx, evalUnquotes(exp, env));
                    }
                    idx++;
 
                }
                return List(copy);
            case Quote(exp):
                return Quote(evalUnquotes(exp, env));
            case Unquote(h):
                var val = Nil;
                eval(h, env, (v) -> { val = v; });
                return val;
            case Quasiquote(exp):
                return evalUnquotes(exp, env);
            default: return expr;
        };
    }

    public function read(str: String) {
        return reader.read("", HStream.FromString(str));
    }

    public function eval(exp: HValue, env: HValue, cc: Continuation) {
        try {
            switch (exp) {
                case Symbol(_):
                    getVar(exp, env, cc);
                case Int(_) | Float(_) | String(_):
                    cc(exp);
                
                case Quote(e):
                    cc(e);
                case Unquote(e):
                    eval(e, env, cc);
                case Quasiquote(e):
                    cc(evalUnquotes(e, env));

                case Function(_) | SpecialForm(_) | Macro(_) | T | Nil | Object(_, _):
                    cc(exp);

                case List(_):
                    maxStackDepth = Math.floor(Math.max(maxStackDepth, CallStack.callStack().length));
                    if (!readingProgram) {
                        HaxeTools.println('${CallStack.callStack().length}'.lpad(' ', 3) + '/' + '$maxStackDepth'.rpad(' ', 3) + '    ${exp.toPrint()}');
                    }

                    eval(exp.first(), env, (callable: HValue) -> {
                        switch (callable) {
                            case Function(_):
                                funcall(false, exp, env, cc);
                            case Macro(_):
                                //HaxeTools.print('macroexpanding ${exp.toPrint()} -> ');
                                macroCall(callable.cons(exp.rest()), env, cc);
                            case SpecialForm(_):
                                specialForm(callable.cons(exp.rest()), env, cc);
                            default: throw 'Cannot call $callable';
                        }
                    });
                default:
                    throw 'Cannot evaluate $exp yet';
            }
        }
        #if !throwErrors
        catch (s: Dynamic) {
            HaxeTools.println('Error $s from `${exp.toPrint()}`');
            HaxeTools.println('Callstack depth ${CallStack.callStack().length}');
        }
        #end
    }
}