package hiss;

import hiss.HTypes;
import ihx.ConsoleReader;
import hiss.HissReader;
import hiss.HissTools;
using HissTools;

class CCInterp {
    public static function main() {
        var hReader = new HissReader(null);
        var cReader = new ConsoleReader();

        while (true) {
            var next = cReader.readLine();
            if (next == "(quit)") break;

            var exp = HissReader.read(String(next));

            var env = Dict([]);

            eval(exp, env, print);
        }
    }

    public static function print(exp: HValue) {
        HaxeTools.println(exp.toPrint());
    }

    public static function begin(exps: HValue, env: HValue, cc: (HValue) -> Void) {
        // TODO
    }

    public static function set(args: HValue, env: HValue) {
        eval(HissTools.second(args),
            env, function(val) {
                env.put(args.first().symbolName(), val);
            });
        env.toDict()[HissTools.first(args).toHaxeString()] = 
        return HissTools.second(args);
    }

    public static function eval(exp: HValue, env: HValue, cc: (HValue) -> Void) {
        switch (exp) {
            case Symbol(name):
                cc(env.toDict()[name]);
            case Int(_) | Float(_) | String(_):
                cc(exp);
            
            // TODO the macro case would go here, but hold your horses!

            default:
                switch (HissTools.first(exp)) {
                    case Symbol("quote"):
                        cc(HissTools.second(exp));
                    case Symbol("begin"):
                        begin(HissTools.rest(exp), env, cc);
                    case Symbol("set!"):
                        cc(set(HissTools.rest(exp)))
                }
        }
    }
}