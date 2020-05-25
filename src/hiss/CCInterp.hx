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
        globals.put("macroexpand", SpecialForm(specialForm));
        globals.put("setlocal", SpecialForm(set.bind(false)));
        globals.put("defvar", SpecialForm(set.bind(true)));
        globals.put("if", SpecialForm(_if));
        globals.put("lambda", SpecialForm(lambda));
        globals.put("call/cc", SpecialForm(callCC));

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
            if (next == "(quit)") break;

            var exp = HissReader.read(String(next));


            try {
                interp.eval(exp, locals, HissTools.print);
            } catch (s: Dynamic) {
                HaxeTools.println('Error $s');
            }
        }
    }

    function _print(exp: HValue, env: HValue, cc: Continuation) {
        HaxeTools.println(exp.first().toPrint());
        cc(exp.first());
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
        //trace('funcall ${args.toPrint()}');
        evalAll(args, env, (values) -> {
            values.first().toFunction()(values.rest(), Dict([]), cc);
        });
    }

    function evalAll(args: HValue, env: HValue, cc: Continuation) {
        if (!args.truthy()) {
            cc(Nil);
        } else {
            eval(args.first(), env, (value) -> {
//                trace(value);
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

    function _if(args: HValue, env: HValue, cc: Continuation) {
        eval(args.first(), env, (val) -> {
            eval(if (val.truthy()) {
                args.second();
            } else {
                args.third();
            }, env, cc);
        });
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

    function lambda(args: HValue, env: HValue, cc: Continuation) {
        var params = args.first();
        var body = Symbol('begin').cons(args.rest());
        cc(Function((fArgs, env, fCC) -> {
            var callEnv = env.extend(params.destructuringBind(fArgs)); // extending the outer env is how lambdas capture values
            eval(body, callEnv, fCC);
        }));
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

    public function eval(exp: HValue, env: HValue, cc: Continuation) {

        switch (exp) {
            case Symbol(_):
                getVar(exp, env, cc);
            case Int(_) | Float(_) | String(_):
                cc(exp);
            
            // TODO the macro case would go here, but hold your horses!

            case Quote(e):
                cc(e);
            case Function(_) | SpecialForm(_) | Macro(_):
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