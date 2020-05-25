package hiss;

import hiss.HTypes;
import ihx.ConsoleReader;
import hiss.HissReader;
import hiss.HissTools;
using hiss.HissTools;

class CCInterp {
    public static function main() {
        var hReader = new HissReader();
        var cReader = new ConsoleReader();

        var env = Dict([]);
        env.put("print", Function(print));
        env.put("+", Function((args: HValue, env: HValue, cc: Continuation) -> {
            cc((args.first().value() + args.second().value()).toHValue());
        }));

        while (true) {
            HaxeTools.print(">>> ");
            cReader.cmd.prompt = ">>> ";

            var next = cReader.readLine();
            if (next == "(quit)") break;

            var exp = HissReader.read(String(next));


            try {
                eval(exp, env, (v) -> { print(v, env, (h) -> {}); });
            } /*catch (s: Dynamic) {
                trace('psych lol $s');
            }*/
        }
    }

    static function print(exp: HValue, env: HValue, cc: Continuation) {
        HaxeTools.println(exp.toPrint());
        cc(exp);
    }

    static function begin(exps: HValue, env: HValue, cc: Continuation) {
        eval(exps.first(), env, (result) -> {
            if (!exps.rest().truthy()) {
                cc(result);
            } else {
                begin(exps.rest(), env, cc);
            }
        });
    }

    static function funcall(args: HValue, env: HValue, cc: Continuation) {
        trace('funcall ${args.toPrint()}');
        evalAll(args, env, (values) -> {
            values.first().toFunction()(values.rest(), env, cc);
        });
    }

    static function evalAll(args: HValue, env: HValue, cc: Continuation) {
        if (!args.truthy()) {
            cc(Nil);
        } else {
            eval(args.first(), env, (value) -> {
                trace(value);
                evalAll(args.rest(), env, (value2) -> {
                    cc(value.cons(value2));
                });
            });
        }
    }

    static function set(args: HValue, env: HValue, cc: Continuation) {
        eval(HissTools.second(args),
            env, (val) -> {
                env.put(args.first().symbolName(), val);
                cc(val);
            });
    }

    static function _if(args: HValue, env: HValue, cc: Continuation) {
        eval(args.first(), env, (val) -> {
            eval(if (val.truthy()) {
                args.second();
            } else {
                args.third();
            }, env, cc);
        });
    }

    static function getVar(name: HValue, env: HValue, cc: Continuation) {
        var d = env.toDict();
        var name = name.symbolName();
        cc(if (d.exists(name)) {
            d[name];
        } else {
            Nil;
        });
    }

    static function lambda(args: HValue, env: HValue, cc: Continuation) {
        var params = args.first();
        var body = Symbol('begin').cons(args.rest());
        cc(Function((fArgs, env, fCC) -> {
            var callEnv = env.extend(params.destructuringBind(fArgs)); // extending the outer env is how lambdas capture values
            eval(body, callEnv, fCC);
        }));
    }

    static function callCC(args: HValue, env: HValue, cc: Continuation) {
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

    public static function eval(exp: HValue, env: HValue, cc: Continuation) {

        switch (exp) {
            case Symbol(_):
                getVar(exp, env, cc);
            case Int(_) | Float(_) | String(_):
                cc(exp);
            
            // TODO the macro case would go here, but hold your horses!

            case Quote(e):
                cc(e);
            case Function(_):
                cc(exp);


            case List(_):
                switch (exp.first()) {
                    case Symbol("quote"):
                        cc(exp.second());
                    case Symbol("begin"):
                        begin(exp.rest(), env, cc);
                    case Symbol("set!"):
                        set(exp.rest(), env, cc);
                    case Symbol("if"):
                        _if(exp.rest(), env, cc);
                    case Symbol("lambda"):
                        lambda(exp.rest(), env, cc);
                    case Symbol("call/cc"):
                        trace("what");
                        callCC(exp.rest(), env, cc);
                    default:
                        funcall(exp, env, cc);
                }
            default:
                throw 'Cannot evaluate $exp yet';
        }
    }
}