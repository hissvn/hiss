package hiss;

import Type;
import Reflect;
using Reflect;
import haxe.CallStack;
import haxe.Constraints.Function;
import haxe.io.Path;

import hiss.HTypes;
#if sys
import ihx.ConsoleReader;
#end
import hiss.HissReader;
import hiss.HissTools;
using hiss.HissTools;
import hiss.StaticFiles;
import hiss.HissMath;
import hiss.NativeFunctions;

using StringTools;

@:build(hiss.NativeFunctions.build(3))
class CCInterp {
    public var globals: HValue = Dict([]);
    var reader: HissReader;

    var tempTrace: Dynamic = null;
    var readingProgram = false;
    var maxStackDepth = 0;

    function disableTrace() {
        // On non-sys targets, trace is the only option
        if (tempTrace == null) {
            trace("Disabling trace");
            tempTrace = haxe.Log.trace;
            haxe.Log.trace = (str, ?posInfo) -> {};
        }
    }

    function enableTrace() {
        if (tempTrace != null) {
            trace("Enabling trace");
            haxe.Log.trace = tempTrace;
        }
    }

    public function importFunction(func: Function, name: String, keepArgsWrapped: HValue = Nil) {
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

    public static function noOp (args: HValue, env: HValue, cc: Continuation) { }
    public static function noCC (arg: HValue) { }

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
        globals.put("load", Function(_load, "load"));
        globals.put("funcall", SpecialForm(funcall.bind(false)));
        globals.put("funcall-inline", SpecialForm(funcall.bind(true)));
        globals.put("loop", SpecialForm(loop));
        globals.put("or", SpecialForm(or));
        globals.put("and", SpecialForm(and));

        globals.put("for", SpecialForm(iterate.bind(true, true)));
        globals.put("for-drop", SpecialForm(iterate.bind(false, true)));
        globals.put("map", SpecialForm(iterate.bind(true, false)));
        globals.put("map-drop", SpecialForm(iterate.bind(false, false)));

        // Use tail-recursive begin for loading the prelude:
        globals.put("begin", SpecialForm(trBegin));

        // Haxe interop -- We could bootstrap the rest from these if we had unlimited stack frames:
        globals.put("Type", Object("Class", Type));
        globals.put("Hiss-Tools", Object("Class", HissTools));
        globals.put("get-property", Function(getProperty, "get-property"));
        globals.put("call-haxe", Function(callHaxe, "call-haxe"));

        // Debug info
        importFunction(HissTools.version, "version");

        // Functions/forms that could be bootstrapped with register-function, but save stack frames if not:
        importFunction(HissTools.print, "print", T);
        importFunction(HissTools.length, "length", T);
        importFunction(HissTools.first, "first", T);
        importFunction(HissTools.rest, "rest", T);
        importFunction(HissTools.eq, "eq", T);
        importFunction(HissTools.nth, "nth", T);
        importFunction(HissTools.cons, "cons", T);
        importFunction(HissTools.not, "not", T);
        importFunction(HissTools.alternates.bind(_, true), "even-alternates", T);
        importFunction(HissTools.alternates.bind(_, false), "odd-alternates", T);
        importFunction(HaxeTools.shellCommand, "shell-command", Nil);
        importFunction(read, "read", Nil);

        globals.put("quote", SpecialForm(quote));

        globals.put("+", Function(HissMath.add, "+"));
        globals.put("-", Function(HissMath.subtract, "-"));
        globals.put("/", Function(HissMath.divide, "/"));
        globals.put("*", Function(HissMath.multiply, "/"));
        globals.put("<", Function(HissMath.numCompare.bind(Lesser), "<"));
        globals.put("<=", Function(HissMath.numCompare.bind(LesserEqual), "<="));
        globals.put(">", Function(HissMath.numCompare.bind(Greater), ">"));
        globals.put(">=", Function(HissMath.numCompare.bind(GreaterEqual), ">="));
        globals.put("=", Function(HissMath.numCompare.bind(Equal), "="));

        // Operating system
        importFunction(HissTools.homeDir, "home-dir");
        importFunction(StaticFiles.getContent, "get-content");

        // (test) is a no-op in production:
        globals.put("test", SpecialForm(noOp));

        StaticFiles.compileWith("stdlib2.hiss");

        //disableTrace();
        load("stdlib2.hiss");
        //enableTrace();

        // Training wheels off. Give Hiss users the callCC-enabled, dangerous begin()
        globals.put("begin", SpecialForm(begin));
    }

    /** Run a Hiss REPL from this interpreter instance **/
    public function repl() {
        #if sys
        var cReader = new ConsoleReader(-1, Path.join([HissTools.homeDir(), ".hisstory"]));  
        // The REPL needs to make sure its ConsoleReader actually saves the history on exit :)
        importFunction(() -> {
            cReader.saveHistory();
            Sys.exit(0);
        }, "quit");
        var locals = List([Dict([])]); // This allows for top-level setlocal

        HaxeTools.println('Hiss version ${CompileInfo.version()}');
        HaxeTools.println("Type (quit) to quit the REPL");

        while (true) {
            HaxeTools.print(">>> ");
            cReader.cmd.prompt = ">>> ";

            var next = cReader.readLine();

            //interp.disableTrace();
            var exp = null;
            try {
                exp = read(next);
            } catch (err: Dynamic) {
                HaxeTools.println('Reader error: $err');
                continue;
            }
            //interp.enableTrace();

            internalEval(exp, locals, HissTools.print);
        }
        #else
        throw "Can't run a Hiss REPL on this platform.";
        #end
    }

    public static function main() {
        var interp = new CCInterp();

        #if sys
        interp.repl();
        #else
        // An interactive repl isn't possible on non-sys platforms, so just run a test program.
        StaticFiles.compileWith("debug.hiss");
        interp.load("debug.hiss");
        #end
    }

    public function load(file: String) {
        _load(List([String(file)]), List([Dict([])]), noCC);
    }

    function _load(args: HValue, env: HValue, cc: Continuation) {
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
        var value = eval(exps.first(), env);

        if (!exps.rest().truthy()) {
            cc(value);
        }
        else {
            trBegin(exps.rest(), env, cc);
        }
    }

    function begin(exps: HValue, env: HValue, cc: Continuation) {
        var returnCalled = false;
        env = env.extend(Dict(["return" => Function((args, env, cc) -> {
            returnCalled = true;
            cc(args.first());
        }, "return")]));

        internalEval(exps.first(), env, (result) -> {
            if (returnCalled || !exps.rest().truthy()) {
                cc(result);
            }
            else {
                begin(exps.rest(), env, cc);
            }
        });
    }

    function specialForm(args: HValue, env: HValue, cc: Continuation) {
        args.first().toCallable()(args.rest(), env, cc);
    }

    function macroCall(args: HValue, env: HValue, cc: Continuation) {
        specialForm(args, env, (expansion: HValue) -> {
            //HaxeTools.println(' ${expansion.toPrint()}');
            internalEval(expansion, env, cc);
        });
    }

    function funcall(callInline: Bool, args: HValue, env: HValue, cc: Continuation) {
        evalAll(args, env, (values) -> {
            // trace(values.toPrint());
            values.first().toHFunction()(values.rest(), if (callInline) env else List([Dict([])]), cc);
        });
    }

    function evalAll(args: HValue, env: HValue, cc: Continuation) {
        if (!args.truthy()) {
            cc(Nil);
        } else {
            internalEval(args.first(), env, (value) -> {
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
        internalEval(args.second(),
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
        internalEval(args.first(), env, (val) -> {
            if (val.truthy()) {
                internalEval(args.second(), env, cc);
            } else if (args.length() > 2) {
                internalEval(args.third(), env, cc);
            } else {
                cc(Nil);
            }
        });
    }

    function getVar(name: HValue, env: HValue, cc: Continuation) {
        // Env is a list of dictionaries -- stack frames
        var stackFrames = env.toList();

        var g = globals.toDict();
        var name = name.symbolName();

        var v = null;
        for (frame in stackFrames) {
            var frameDict = frame.toDict();
            if (frameDict.exists(name)) {
                v = frameDict[name];
                break;
            }
        }
        cc(if (v != null) {
            v;
        } else if (g.exists(name)) {
            g[name];
        } else {
            throw '$name is undefined';
        });
    }

    function lambda(isMacro: Bool, args: HValue, env: HValue, cc: Continuation, name = "[anonymous lambda]") {
        var params = args.first();

        // TODO do I need a switch here to decide whether to use tail-recursive begin or not?!

        // like, exposing lambda vs. tr-lambda to Hiss programs

        // something like... `big-lambda` XD

        var body = Symbol('begin').cons(args.rest());
        var hFun: HFunction = (fArgs, env, fCC) -> {
            var callEnv = env.extend(params.destructuringBind(fArgs)); // extending the outer env is how lambdas capture values
            internalEval(body, callEnv, fCC);
        };
        var callable = if (isMacro) {
            Macro(hFun);
        } else {
            Function(hFun, "[anonymous lambda]");
        };
        cc(callable);
    }

    /**
        Implementation behind (for), (drop-for), (map), and (drop-map)
    **/
    function iterate(collect: Bool, bodyForm: Bool, args: HValue, env: HValue, cc: Continuation) {
        var it: HValue = Nil;
        internalEval(if (bodyForm) {
            args.second();
        } else {
            args.first();
        }, env, (_iterable) -> { it = _iterable; });
        var iterable: Iterable<HValue> = it.value(true);

        var operation: HFunction = null;
        if (bodyForm) {
            var varName = args.first().symbolName();
            var body = List(args.toList().slice(2));
            operation = (innerArgs, env, cc) -> {
                var bodyEnv = env.extend(Dict([varName => innerArgs.first()]));
                internalEval(Symbol("begin").cons(body), bodyEnv, cc);
            };
        } else {
            internalEval(args.second(), env, (fun) -> {operation = fun.toHFunction();});
        }

        var results = [];
        var iterationCC = if (collect) {
            (result) -> { results.push(result); };
        } else {
            noCC;
        }

        for (value in iterable) {
            operation(List([value]), if (bodyForm) { env; } else { List([Dict([])]); }, iterationCC);
        }

        cc(List(results));
    }

    /**
        Special form for performing Hiss operations tail-recursively
    **/
    function loop(args: HValue, env: HValue, cc: Continuation) {
        var bindings = args.first();
        var body = args.rest();

        var names = Symbol("recur").cons(bindings.alternates(true));
        var firstValueExps = bindings.alternates(false);
        evalAll(firstValueExps, env, (firstValues) -> {
            var nextValues = Nil;
            var recurCalled = false;
            var recur: HFunction = (nextValueExps, env, cc) -> {
                evalAll(nextValueExps, env, (nextVals) -> {nextValues = nextVals;});
                recurCalled = true;
            }
            var values = firstValues;
            var result = Nil;
            do {
                if (recurCalled) {
                    values = nextValues;
                    recurCalled = false;
                }

                // Recur has to be a special form so it retains the environment of the original loop call
                internalEval(Symbol("begin").cons(body), env.extend(names.destructuringBind(SpecialForm(recur).cons(values))), (value) -> {result = value;});
                
            } while (recurCalled);
            cc(result);
        });
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

    function print(args: HValue, env: HValue, cc: Continuation) {
        args.first().print();
        cc(args.first());
    }

    function callCC(args: HValue, env: HValue, cc: Continuation) {
        // Convert the continuation to a hiss function accepting one argument
        var ccHFunction = Function((innerArgs: HValue, innerEnv: HValue, innerCC: Continuation) -> {
            //trace('cc was called with ${innerArgs.first().toPrint()}');
            // It's typical to JUST want to break out of a sequence, not return a value to it.
            if (!innerArgs.truthy()) cc(Nil);
            else cc(innerArgs.first());
        }, "cc");

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

                            internalEval(exp, env, (innerList) -> {
                                for (exp in innerList.toList()) { 
                                    copy.insert(idx++, exp);
                                }
                            });
                        // If an UnquoteList is quoted, apply the quote to each expression in the list
                        case Quote(UnquoteList(exp)):
                            copy.splice(idx, 1);
                            internalEval(exp, env, (innerList) -> {
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
                internalEval(h, env, (v) -> { val = v; });
                return val;
            case Quasiquote(exp):
                return evalUnquotes(exp, env);
            default: return expr;
        };
    }

    public function read(str: String) {
        return reader.read("", HStream.FromString(str));
    }

    function or(args: HValue, env: HValue, cc: Continuation) {
        for (arg in args.toList()) {
            var argVal = Nil;
            internalEval(arg, env, (val) -> {argVal = val;});
            if (argVal.truthy()) {
                cc(argVal);
                return;
            }
        }
        cc(Nil);
    }

    function and(args: HValue, env: HValue, cc: Continuation) {
        var argVal = T;
        for (arg in args.toList()) {
            internalEval(arg, env, (val) -> {argVal = val;});
            if (!argVal.truthy()) {
                cc(Nil);
                return;
            }
        }
        cc(argVal);
    }

    /** Hiss-callable form for eval **/
    function _eval(args: HValue, env: HValue, cc: Continuation) {
        internalEval(args.first(), env, cc);
    }

    /** Public, synchronous form of eval **/
    public function eval(arg: HValue, ?env: HValue) {
        var value = null;
        if (env == null) env = List([Dict([])]);
        internalEval(arg, env, (_value) -> {
            value = _value;
        });
        return value;
    }

    /** Core form of eval -- continuation-based, takes one expression **/
    private function internalEval(exp: HValue, env: HValue, cc: Continuation) {
        try {
            switch (exp) {
                case Symbol(_):
                    inline getVar(exp, env, cc);
                case Int(_) | Float(_) | String(_):
                    cc(exp);

                case InterpString(raw):
                    // Handle expression interpolation
                    var interpolated = raw;

                    var idx = 0;
                    while (interpolated.indexOf("$", idx) != -1) {
                        idx = interpolated.indexOf("$", idx);
                        // Allow \$ for putting $ in string.
                        if (interpolated.charAt(idx-1) == '\\') {
                            ++idx;
                            continue;
                        }

                        var expStream = HStream.FromString(interpolated.substr(idx+1));
                        var startingLength = expStream.length();
                        var exp = reader.read("", expStream);
                        var expLength = startingLength - expStream.length();
                        internalEval(exp, env, (val) -> {
                            interpolated = interpolated.substr(0, idx) + val.toMessage() + interpolated.substr(idx+1+expLength);
                            idx = idx + 1 + val.toMessage().length;
                        });
                    }
                    
                    cc(String(interpolated));
                
                case Quote(e):
                    cc(e);
                case Unquote(e):
                    internalEval(e, env, cc);
                case Quasiquote(e):
                    cc(inline evalUnquotes(e, env));

                case Function(_) | SpecialForm(_) | Macro(_) | T | Nil | Object(_, _):
                    cc(exp);

                case List(_):
                    maxStackDepth = Math.floor(Math.max(maxStackDepth, CallStack.callStack().length));
                    if (!readingProgram) {
                        // For debugging stack overflows, use this:

                        // HaxeTools.println('${CallStack.callStack().length}'.lpad(' ', 3) + '/' + '$maxStackDepth'.rpad(' ', 3) + '    ${exp.toPrint()}');
                    }

                    internalEval(exp.first(), env, (callable: HValue) -> {
                        switch (callable) {
                            case Function(_):
                                inline funcall(false, exp, env, cc);
                            case Macro(_):
                                //HaxeTools.print('macroexpanding ${exp.toPrint()} -> ');
                                inline macroCall(callable.cons(exp.rest()), env, cc);
                            case SpecialForm(_):
                                inline specialForm(callable.cons(exp.rest()), env, cc);
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