package hiss;

using hiss.Stdlib;
using hiss.HissTools;
using hiss.HTypes;

/** 
    Core special forms
**/
class SpecialForms {
    public static function if_s(interp: CCInterp, args: HValue, env: HValue, cc: Continuation) {
        if (args.length_h() > 3) {
            interp.error('(if) called with too many arguments. Try wrapping the cases in (begin)');
        }
        interp.evalCC(args.first(), (val) -> {
            if (interp.truthy(val)) {
                interp.evalCC(args.second(), cc, env);
            } else if (args.length_h() > 2) {
                interp.evalCC(args.third(), cc, env);
            } else {
                cc(Nil);
            }
        }, env);
    }

    public static function lambda_s(interp: CCInterp, args: HValue, env: HValue, cc: Continuation, name = "[anonymous lambda]", isMacro = false) {
        var params = args.first();

        // Check for metadata
        var meta = {
            name: name,
            argNames: [for (paramSymbol in params.toList()) try {
                // simple functions args can be imported with names
                paramSymbol.symbolName_h();
            } catch (s: Dynamic){
                // nested list args cannot
                "[nested list]";
            }],
            docstring: "",
            deprecated: false,
            async: false
        };

        var body = args.rest_h().toList();
        
        for (exp in body) {
            switch (exp) {
                case String(d) | InterpString(d):
                    meta.docstring = d;
                    body.shift();
                case Symbol("@deprecated"):
                    meta.deprecated = true;
                    body.shift();
                case Symbol("@async"):
                    meta.async = true;
                    body.shift();
                default:
                    break;
            }
        }

        var hFun: HFunction = (fArgs, innerEnv, fCC) -> {
            var callEnv = List(env.toList().concat(innerEnv.toList()));
            callEnv = callEnv.extend(params.destructuringBind(interp, fArgs)); // extending the outer env is how lambdas capture values
            interp.evalCC(Symbol('begin').cons_h(List(body)), fCC, callEnv);
        };
        
        var callable = if (isMacro) {
            Macro(hFun, meta);
        } else {
            Function(hFun, meta);
        };
        cc(callable);
    }
}