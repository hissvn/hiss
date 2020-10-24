package hiss;

using hiss.Stdlib;
using hiss.HissTools;
using hiss.HTypes;

/** 
    Core special forms
**/
class SpecialForms {
    public static function if_s(interp:CCInterp, args:HValue, env:HValue, cc:Continuation) {
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

    public static function lambda_s(interp:CCInterp, args:HValue, env:HValue, cc:Continuation, name = "[anonymous lambda]", isMacro = false) {
        var params = args.first();

        // Check for metadata
        var meta = {
            name: name,
            argNames: [
                for (paramSymbol in params.toList())
                    try {
                        // simple functions args can be imported with names
                        paramSymbol.symbolName_h();
                    } catch (s:Dynamic) {
                        // nested list args cannot
                        "[nested list]";
                    }
            ],
            docstring: "",
            deprecated: false,
            async: false
        };

        var body = args.rest_h().toList();

        var idx = 0;
        for (exp in body) {
            switch (exp) {
                case String(d) | InterpString(d):
                    // Unless the string is the only expression left in the body, use it as a docstring
                    if (idx + 1 < body.length) {
                        meta.docstring = d;
                        body.shift();
                    }
                case Symbol("@deprecated"):
                    meta.deprecated = true;
                    body.shift();
                case Symbol("@async"):
                    meta.async = true;
                    body.shift();
                default:
                    break;
            }
            idx += 1;
        }

        var hFun:HFunction = (fArgs, innerEnv, fCC) -> {
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

    public static function and_s(interp:CCInterp, args:HValue, env:HValue, cc:Continuation) {
        var argVal = T;
        for (arg in args.toList()) {
            // TODO this won't work for async calls as and arguments
            interp.evalCC(arg, (val) -> {
                argVal = val;
            }, env);
            if (!interp.truthy(argVal)) {
                cc(Nil);
                return;
            }
        }
        cc(argVal);
    }

    public static function or_s(interp:CCInterp, args:HValue, env:HValue, cc:Continuation) {
        for (arg in args.toList()) {
            var argVal = Nil;
            // TODO this won't work for async calls as or arguments
            interp.evalCC(arg, (val) -> {
                argVal = val;
            }, env);
            if (interp.truthy(argVal)) {
                cc(argVal);
                return;
            }
        }
        cc(Nil);
    }

    static var _ccNum = 0;

    public static function callCC_s(interp:CCInterp, args:HValue, env:HValue, cc:Continuation) {
        var ccId = _ccNum++;
        var message = "";
        var functionToCall = null;

        if (args.length_h() > 1) {
            message = interp.eval(args.first(), env).toHaxeString();
            functionToCall = args.second();
        } else {
            functionToCall = args.first();
        }

        // Convert the continuation to a hiss function accepting one argument
        var ccHFunction = Function((innerArgs : HValue, innerEnv : HValue, innerCC : Continuation) -> {
            var arg = if (!interp.truthy(innerArgs)) {
                // It's typical to JUST want to break out of a sequence, not return a value to it.
                Nil;
            } else {
                innerArgs.first();
            };

            #if traceContinuations
            Sys.println('calling $message(cc#$ccId) with ${arg.toPrint()}');
            #end

            cc(arg);
        }, {name: "cc", argNames: ["result"]});

        interp.evalCC(List([Symbol("funcall-inline"), functionToCall, ccHFunction]), cc, env);
    }

    public static function quote_s(interp:CCInterp, args:HValue, env:HValue, cc:Continuation) {
        cc(args.first());
    }
}
