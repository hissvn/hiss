package hiss;

import hiss.HTypes;
import ihx.ConsoleReader;
import hiss.HissReader;
import hiss.HissTools;
using hiss.HissTools;

typedef Continuation = (HValue) -> Void;

class CCInterp {
    public static function main() {
        var hReader = new HissReader();
        var cReader = new ConsoleReader();

        var env = Dict([]);

        while (true) {
            HaxeTools.print(">>> ");
            cReader.cmd.prompt = ">>> ";

            var next = cReader.readLine();
            if (next == "(quit)") break;

            var exp = HissReader.read(String(next));


            try {
                eval(exp, env, print);
            } catch (s: Dynamic) {
                trace('psych lol $s');
            }
        }
    }

    static function print(exp: HValue) {
        HaxeTools.println(exp.toPrint());
    }

    static function begin(exps: HValue, env: HValue, cc: Continuation) {
        // TODO
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
        
    }

    public static function eval(exp: HValue, env: HValue, cc: Continuation) {
        switch (exp) {
            case Symbol(_):
                getVar(exp, env, cc);
            case Int(_) | Float(_) | String(_):
                cc(exp);
            
            // TODO the macro case would go here, but hold your horses!

            default:
                switch (HissTools.first(exp)) {
                    case Symbol("quote"):
                        cc(exp.second());
                    case Symbol("begin"):
                        begin(exp.rest(), env, cc);
                    case Symbol("set!"):
                        set(exp.rest(), env, cc);
                    case Symbol("if"):
                        _if(exp.rest(), env, cc);
                    case Symbol("lambda"):

                    default:
                        throw 'yeet';
                }
        }
    }
}