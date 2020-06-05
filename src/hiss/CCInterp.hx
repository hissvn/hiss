package hiss;

import Type;
import Reflect;

import hiss.HTypes;
#if sys
import ihx.ConsoleReader;
#end
import hiss.HissReader;
import hiss.HissTools;
using hiss.HissTools;
import hiss.StaticFiles;

@:build(hiss.BinopsBuilder.build())
class HaxeBinops {

}

class CCInterp {
    var globals: HValue = Dict([]);
    var stackFrames: HValue = List([]);
    var reader: HissReader;

    var tempTrace: Dynamic = null;

    function disableTrace() {
        // On non-sys targets, trace is the only option
        tempTrace = haxe.Log.trace;
        haxe.Log.trace = (str, ?posInfo) -> {};
    }

    function enableTrace() {
        if (tempTrace != null) haxe.Log.trace = tempTrace;
    }


    public function new() {
        reader = new HissReader(this);

        // Primitives
        globals.put("begin", SpecialForm(begin));
        globals.put("setlocal", SpecialForm(set.bind(false)));
        globals.put("defvar", SpecialForm(set.bind(true)));
        globals.put("defun", SpecialForm(setCallable.bind(false)));
        globals.put("defmacro", SpecialForm(setCallable.bind(true)));
        globals.put("if", SpecialForm(_if));
        globals.put("lambda", SpecialForm(lambda.bind(false)));
        globals.put("call/cc", SpecialForm(callCC));
        globals.put("eval", Function(_eval));
        globals.put("bound?", SpecialForm(bound));
        globals.put("load", Function(load));
        globals.put("funcall", SpecialForm(funcall.bind(false)));
        globals.put("funcall-inline", SpecialForm(funcall.bind(true)));

        // Haxe interop -- We can bootstrap the rest from these:
        globals.put("Type", Object("Class", Type));
        globals.put("Hiss-Tools", Object("Class", HissTools));
        globals.put("get-property", Function(getProperty));
        globals.put("call-haxe", Function(callHaxe));

        StaticFiles.compileWith("stdlib2.hiss");

        disableTrace();
        load(List([String("stdlib2.hiss")]), Dict([]), (hval) -> {});
        enableTrace();
    }

    public static function main() {
        var interp = new CCInterp();
        StaticFiles.compileWith("debug.hiss");
        #if sys
        var cReader = new ConsoleReader();        
        var locals = Dict([]);

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
        interp.load(List([String("debug.hiss")]), Dict([]), (hval) -> {});
        #end
    }

    function load(args: HValue, env: HValue, cc: Continuation) {
        begin(reader.readAll(String(StaticFiles.getContent(args.first().value()))), env, cc);
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

    function specialForm(args: HValue, env: HValue, cc: Continuation) {
        args.first().toFunction()(args.rest(), env, cc);
    }

    function macroCall(args: HValue, env: HValue, cc: Continuation) {
        specialForm(args, env, (expansion: HValue) -> {
            HaxeTools.println(' ${expansion.toPrint()}');
            eval(expansion, env, cc);
        });
    }

    function funcall(callInline: Bool, args: HValue, env: HValue, cc: Continuation) {
        evalAll(args, env, (values) -> {
            // trace(values.toPrint());
            values.first().toFunction()(values.rest(), if (callInline) env else Dict([]), cc);
        });
    }

    function evalAll(args: HValue, env: HValue, cc: Continuation) {
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

    function quote(args: HValue, env: HValue, cc: Continuation) {
        cc(args.first());
    }

    function set(global: Bool, args: HValue, env: HValue, cc: Continuation) {
        eval(args.second(),
            env, (val) -> {
                var scope = if (global) {
                    globals;
                } else {
                    env;
                }
                scope.put(args.first().symbolName(), val);
                cc(val);
            });
    }

    function setCallable(isMacro: Bool, args: HValue, env: HValue, cc: Continuation) {
        lambda(isMacro, args.rest(), env, (fun: HValue) -> {
            set(true, args.first().cons(List([fun])), env, cc);
        });
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

    function getVar(name: HValue, env: HValue, cc: Continuation) {
        var d = env.toDict();
        var g = globals.toDict();
        var name = name.symbolName();
        cc(if (d.exists(name)) {
            d[name];
        } else if (g.exists(name)) {
            g[name];
        } else {
            Nil;
        });
    }

    function lambda(isMacro: Bool, args: HValue, env: HValue, cc: Continuation) {
        var params = args.first();
        var body = Symbol('begin').cons(args.rest());
        var hFun: HFunction = (fArgs, env, fCC) -> {
            var callEnv = env.extend(params.destructuringBind(fArgs)); // extending the outer env is how lambdas capture values
            eval(body, callEnv, fCC);
        };
        var callable = if (isMacro) {
            Macro(hFun);
        } else {
            Function(hFun);
        };
        cc(callable);
    }

    function bound(args: HValue, env: HValue, cc: Continuation) {
        var d = env.toDict();
        var g = globals.toDict();
        var name = args.first().symbolName();
        cc(if (d.exists(name) || g.exists(name)) {
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

        HaxeTools.println('calling haxe ${args.second().toHaxeString()} on ${args.first().toPrint()}');
        var caller = args.first().value(callOnReference);

        var method = Reflect.getProperty(caller, args.second().toHaxeString());
        var haxeCallArgs = args.third().unwrapList(keepArgsWrapped);

        cc(Reflect.callMethod(caller, method, haxeCallArgs).toHValue());
    }

    function callCC(args: HValue, env: HValue, cc: Continuation) {
        // Convert the continuation to a hiss function accepting one argument
        var ccHFunction = Function((innerArgs: HValue, innerEnv: HValue, innerCC: Continuation) -> {
            //trace('cc was called with ${innerArgs.first().toPrint()}');
            cc(innerArgs.first());
        });

        funcall(true,
            List([
                args.first(),
                ccHFunction]),
            env, 
            cc);
    }

    // This breaks the continuation-based signature rules because I just want it to work.
    public function evalUnquotes(expr: HValue, env: HValue): HValue {
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
                
                // TODO the macro case would go here, but hold your horses!

                case Quote(e):
                    cc(e);
                case Unquote(e):
                    eval(e, env, cc);
                case Quasiquote(e):
                    cc(evalUnquotes(e, env));

                case Function(_) | SpecialForm(_) | Macro(_) | T | Nil | Object(_, _):
                    cc(exp);

                case List(_):
                    eval(exp.first(), env, (callable: HValue) -> {
                        switch (callable) {
                            case Function(_):
                                funcall(false, exp, env, cc);
                            case Macro(_):
                                HaxeTools.print('macroexpanding ${exp.toPrint()} -> ');
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
        }
        #end
    }
}