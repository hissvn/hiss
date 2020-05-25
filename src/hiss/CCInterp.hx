package hiss;

import hiss.HTypes;
import ihx.ConsoleReader;
import hiss.HissReader;
import hiss.HissTools;
using hiss.HissTools;

class CCInterp {
    var globals: HValue = Dict([]);

    public function new() {
        globals.put("print", Function(_print));
        globals.put("quote", SpecialForm(quote));
        globals.put("begin", SpecialForm(begin));
        globals.put("setlocal", SpecialForm(set.bind(false)));
        globals.put("defvar", SpecialForm(set.bind(true)));
        globals.put("defun", SpecialForm(setCallable.bind(false)));
        globals.put("defmacro", SpecialForm(setCallable.bind(true)));
        globals.put("if", SpecialForm(_if));
        globals.put("lambda", SpecialForm(lambda.bind(false)));
        globals.put("call/cc", SpecialForm(callCC));
        globals.put("eval", SpecialForm(_eval));
        globals.put("quit", Function(quit));
        globals.put("bound?", SpecialForm(bound));

        globals.put("+", Function((args: HValue, env: HValue, cc: Continuation) -> {
            cc((args.first().value() + args.second().value()).toHValue());
        }));
    }

    public static function main() {
        var hReader = new HissReader();
        var interp = new CCInterp();
        var cReader = new ConsoleReader();        
        var locals = Dict([]);

        while (true) {
            HaxeTools.print(">>> ");
            cReader.cmd.prompt = ">>> ";

            var next = cReader.readLine();

            var exp = HissReader.read(String(next));

            try {
                interp.eval(exp, locals, HissTools.print);
            }
            #if !throwErrors
            catch (s: Dynamic) {
                HaxeTools.println('Error $s');
            }
            #end
        }
    }

    function quit(args: HValue, env: HValue, cc: Continuation) {
        Sys.exit(0);
    }

    function _print(args: HValue, env: HValue, cc: Continuation) {
        HaxeTools.println(args.first().toPrint());
        cc(args.first());
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

    function funcall(args: HValue, env: HValue, cc: Continuation) {
        evalAll(args, env, (values) -> {
            values.first().toFunction()(values.rest(), Dict([]), cc);
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

    /** Special form for eval **/
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

    function callCC(args: HValue, env: HValue, cc: Continuation) {
        // Convert the continuation to a hiss function accepting one argument
        var ccHFunction = Function((innerArgs: HValue, innerEnv: HValue, innerCC: Continuation) -> {
            cc(innerArgs.first());
        });

        funcall(
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

    public function eval(exp: HValue, env: HValue, cc: Continuation) {
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
                evalUnquotes(List([e]), env, cc);

            case Function(_) | SpecialForm(_) | Macro(_) | T | Nil:
                cc(exp);

            case List(_):
                eval(exp.first(), env, (callable: HValue) -> {
                    switch (callable) {
                        case Function(_):
                            funcall(exp, env, cc);
                        case Macro(_):
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
}