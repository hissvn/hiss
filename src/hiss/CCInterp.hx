package hiss;

import Type;
import Reflect;

import hiss.HTypes;
import ihx.ConsoleReader;
import hiss.HissReader;
import hiss.HissTools;
using hiss.HissTools;
import hiss.StaticFiles;

class CCInterp {
    var globals: HValue = Dict([]);
    var reader: HissReader;
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

        globals.put("+", Function((args: HValue, env: HValue, cc: Continuation) -> {
            cc((args.first().value() + args.second().value()).toHValue());
        }));

        StaticFiles.compileWith("stdlib2.hiss");
        load(List([String("stdlib2.hiss")]), Dict([]), (hval) -> {});
    }

    public static function main() {
        var interp = new CCInterp();
        var cReader = new ConsoleReader();        
        var locals = Dict([]);

        while (true) {
            HaxeTools.print(">>> ");
            cReader.cmd.prompt = ">>> ";

            var next = cReader.readLine();

            var exp = interp.read(next);

            interp.eval(exp, locals, HissTools.print);
        }
    }

    function load(args: HValue, env: HValue, cc: Continuation) {
        evalAll(reader.readAll(String(StaticFiles.getContent(args.first().value()))), env, cc);
    }

    function begin(exps: HValue, env: HValue, cc: Continuation) {
        eval(exps.first(), env, (result) -> {
            if (!exps.rest().truthy()) {
                cc(result);
            } else {
                begin(exps.rest(), env, cc);
            }
        });
    }

    function specialForm(args: HValue, env: HValue, cc: Continuation) {
        args.first().toFunction()(args.rest(), env, cc);
    }

    function macroCall(args: HValue, env: HValue, cc: Continuation) {
        specialForm(args, env, (expansion: HValue) -> {
            eval(expansion, env, cc);
        });
    }

    function funcall(callInline: Bool, args: HValue, env: HValue, cc: Continuation) {
        evalAll(args, env, (values) -> {
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
        eval(HissTools.second(args),
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
            eval(if (val.truthy()) {
                args.second();
            } else {
                args.third();
            }, env, cc);
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

        var caller = args.first().value(callOnReference);

        var method = Reflect.getProperty(caller, args.second().toHaxeString());
        var haxeCallArgs = args.third().unwrapList(keepArgsWrapped);

        cc(Reflect.callMethod(caller, method, haxeCallArgs).toHValue());
    }

    function callCC(args: HValue, env: HValue, cc: Continuation) {
        // Convert the continuation to a hiss function accepting one argument
        var ccHFunction = Function((innerArgs: HValue, innerEnv: HValue, innerCC: Continuation) -> {
            cc(innerArgs.first());
        });

        funcall(false,
            List([
                args.first(),
                ccHFunction]),
            env, 
            cc);
    }

    function evalUnquotes(args: HValue, env: HValue, cc: Continuation) {
        switch (args.first()) {
            case List(exps):
                var copy = exps.copy();
                // If any of exps is an UnquoteList, expand it and insert the values at that index
                var idx = 0;
                while (idx < copy.length) {
                    switch (copy[idx]) {
                        case UnquoteList(exp):
                            copy.splice(idx, 1);
                            eval(exp, env, (innerList: HValue) -> {
                                for (exp in innerList.toList()) { 
                                    copy.insert(idx++, exp);
                                }
                            });

                        // If an UnquoteList is quoted, apply the quote to each expression in the list
                        case Quote(UnquoteList(exp)):
                            copy.splice(idx, 1);
                            eval(exp, env, (innerList: HValue) -> {
                                for (exp in innerList.toList()) { 
                                    copy.insert(idx++, Quote(exp));
                                }
                            });

                        default:
                            var exp = copy[idx];
                            copy.splice(idx, 1);
                            evalUnquotes(List([exp]), env, (value: HValue) -> {
                                copy.insert(idx, value);
                            });
                    }
                    idx++;
 
                }
                cc(List(copy));
            case Quote(exp):
                evalUnquotes(List([exp]), env, (value: HValue) -> {
                    cc(Quote(value));
                });
            case Quasiquote(exp):
                evalUnquotes(List([exp]), env, cc);
            case Unquote(h):
                eval(h, env, cc);
            default:
                cc(args.first());
        };
    }

    public function read(str: String) {
        return reader.read("", HStream.FromString(str));
    }

    public function eval(exp: HValue, env: HValue, cc: Continuation) {
        var value = Nil;
        var captureValue = (val) -> { value = val; };
        try {
            switch (exp) {
                case Symbol(_):
                    getVar(exp, env, captureValue);
                case Int(_) | Float(_) | String(_):
                    captureValue(exp);
                
                // TODO the macro case would go here, but hold your horses!

                case Quote(e):
                    captureValue(e);
                case Unquote(e):
                    eval(e, env, captureValue);
                case Quasiquote(e):
                    evalUnquotes(List([e]), env, captureValue);

                case Function(_) | SpecialForm(_) | Macro(_) | T | Nil | Object(_, _):
                    captureValue(exp);

                case List(_):
                    eval(exp.first(), env, (callable: HValue) -> {
                        switch (callable) {
                            case Function(_):
                                funcall(false, exp, env, captureValue);
                            case Macro(_):
                                macroCall(callable.cons(exp.rest()), env, captureValue);
                            case SpecialForm(_):
                                specialForm(callable.cons(exp.rest()), env, captureValue);
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
        cc(value);
    }
}