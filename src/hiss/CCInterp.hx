package hiss;

import Type;
using Type;
import Reflect;
using Reflect;
import haxe.CallStack;
import haxe.Constraints.Function;
import haxe.io.Path;
import haxe.Log;
import hx.strings.Strings;
using hx.strings.Strings;

import hiss.HTypes;
#if (sys || hxnodejs)
import sys.io.File;
import sys.io.FileOutput;
import ihx.ConsoleReader;
#end
#if target.threaded
import hiss.wrappers.Threading;
#end
import hiss.wrappers.HType;
import hiss.HissReader;
import hiss.HissTools;
using hiss.HissTools;
import hiss.StaticFiles;
import hiss.VariadicFunctions;
import hiss.NativeFunctions;
import hiss.HissTestCase;

import StringTools;
using StringTools;

enum SetType {
    Global;
    Local;
    Destructive;
}

@:expose
@:build(hiss.NativeFunctions.build())
class CCInterp {
    public var globals: HValue;
    var reader: HissReader;

    var tempTrace: Dynamic = null;
    var readingProgram = false;
    var maxStackDepth = 0;

    function disableTrace() {
        // On non-sys targets, trace is the only option
        if (tempTrace == null) {
            trace("Disabling trace");
            tempTrace = Log.trace;
            Log.trace = (str, ?posInfo) -> {};
        }
    }

    function enableTrace() {
        if (tempTrace != null) {
            trace("Enabling trace");
            Log.trace = tempTrace;
        }
    }

    public function importVar(value: Dynamic, name: String) {
        globals.put(name, value.toHValue());
    }

    // Sometimes Haxe stdlib classes are implemented differently from target to target,
    // so it's important to see whether all the methods Hiss relies on are actually
    // imported on each target, and if not all targets provide them, wrap them
    var debugClassImports = false;

    public function importClass(clazz: Class<Dynamic>, name: String, ?methodNameFunction: String->String) {
        if (debugClassImports) {
            trace('Import $name');
        }
        globals.put(name, Object("Class", clazz));

        // By default, convert method names into the form ClassName:method-to-lower-hyphen
        if (methodNameFunction == null) {
            methodNameFunction = (methodName) -> {
                name + ":" + methodName.toLowerHyphen();
            };
        }

        var dummyInstance = clazz.createEmptyInstance();
        for (instanceField in clazz.getInstanceFields()) {
            var fieldValue = Reflect.getProperty(dummyInstance, instanceField);
            switch (Type.typeof(fieldValue)) {
                case TFunction:
                    var translatedName = methodNameFunction(instanceField);
                    if (debugClassImports) {
                        trace(translatedName);
                    }
                    globals.put(translatedName, Function((args, env, cc) -> {
                        // This has been split into more atomic steps for debugging on different hiss targets:
                        var instance = args.first().value(this);
                        var argArray = args.rest().unwrapList(this);
                        // We need an empty instance for checking the types of the properties.
                        // BUT if we get our function pointers from the empty instance, the C++ target
                        // will segfault when we try to call them, so getProperty has to be called every time
                        var methodPointer = Reflect.getProperty(instance, instanceField);
                        var returnValue: Dynamic = Reflect.callMethod(instance, methodPointer, argArray);
                        cc(returnValue.toHValue());
                    }, translatedName));
                default:
                    // TODO generate getters and setters for instance fields
            }
        }

        for (classField in clazz.getClassFields()) {
            // TODO this logic is much-repeated from the above for-loop
            var fieldValue = Reflect.getProperty(clazz, classField);
            switch (Type.typeof(fieldValue)) {
                case TFunction:
                    var translatedName = methodNameFunction(classField);
                    if (debugClassImports) {
                        trace(translatedName);
                    }
                    globals.put(translatedName, Function((args, env, cc) -> {
                        cc(Reflect.callMethod(null, fieldValue, args.unwrapList(this)).toHValue());
                    }, translatedName));
                default:
                    // TODO generate getters and setters for static properties
            }
        }
    }

    function _new(args: HValue, env: HValue, cc: Continuation) {
        var clazz: Class<Dynamic> = args.first().value(this);
        var args = args.rest().unwrapList(this);
        var instance: Dynamic = Type.createInstance(clazz, args);
        cc(instance.toHValue());
    }

    public function importFunction(func: Function, name: String, keepArgsWrapped: HValue = Nil, ?args: Array<String>) {
        globals.put(name, Function((args: HValue, env: HValue, cc: Continuation) -> {
            cc(Reflect.callMethod(null, func, args.unwrapList(this, keepArgsWrapped)).toHValue());
        }, name, args));
    }

    public function importCCFunction(func: HFunction, name: String, ?args: Array<String>) {
        globals.put(name, Function(func, name, args));
    }

    public function importSpecialForm(func: HFunction, name: String) {
        globals.put(name, SpecialForm(func, name));
    }

    function importMethod(method: String, name: String, callOnReference: Bool, keepArgsWrapped: HValue, returnInstance: Bool) {
        globals.put(name, Function((args: HValue, env: HValue, cc: Continuation) -> {
            var instance = args.first().value(callOnReference);
            cc(instance.callMethod(instance.getProperty(method), args.rest().unwrapList(this, keepArgsWrapped)).toHValue());
        }, name));
    }

    public static function noOp (args: HValue, env: HValue, cc: Continuation) { }
    public static function noCC (arg: HValue) { }

    var currentBeginFunction: HFunction = null;

    static function emptyList() { return List([]); }

    public function emptyDict() { return Dict(new HDict(this)); }

    public function emptyEnv() { return List([emptyDict()]); }

    public function new(?printFunction: (Dynamic) -> Dynamic) {
        HissTestCase.reallyTrace = Log.trace;

        globals = emptyDict();
        reader = new HissReader(this);

        // When not a repl, use Sys.exit for quitting
        #if (sys || nodejs)
        importFunction(Sys.exit.bind(0), "quit", []);
        #end

        // Primitives
        importSpecialForm(set.bind(Global), "defvar");
        importSpecialForm(set.bind(Local), "setlocal");
        importSpecialForm(set.bind(Destructive), "set!");
        importSpecialForm(setCallable.bind(false), "defun");
        importSpecialForm(setCallable.bind(true), "defmacro");
        importSpecialForm(_if, "if");
        importSpecialForm(lambda.bind(false), "lambda");
        importSpecialForm(callCC, "call/cc");
        importSpecialForm(_eval, "eval");
        importSpecialForm(bound, "bound?");
        importCCFunction(_load, "load", ["file"]);
        importSpecialForm(funcall.bind(false), "funcall");
        importSpecialForm(funcall.bind(true), "funcall-inline");
        importSpecialForm(loop, "loop");
        importSpecialForm(or, "or");
        importSpecialForm(and, "and");

        // Use tail-recursive begin and iterate by default:
        useBeginAndIterate(trBegin, iterate);

        // Allow switching at runtime:
        importFunction(useBeginAndIterate.bind(trBegin, iterate), "enable-tail-recursion");
        importFunction(useBeginAndIterate.bind(trBegin, iterate), "disable-continuations");
        importFunction(useBeginAndIterate.bind(begin, iterateCC), "enable-continuations");
        importFunction(useBeginAndIterate.bind(begin, iterateCC), "disable-tail-recursion");

        // First-class unit testing:
        importSpecialForm(HissTestCase.testAtRuntime.bind(this), "test");
        importCCFunction(HissTestCase.hissPrints.bind(this), "prints");

        // Haxe interop -- We could bootstrap the rest from these if we had unlimited stack frames:
        importClass(HType, "Type");
        importCCFunction(getProperty, "get-property");
        importCCFunction(callHaxe, "call-haxe");
        importCCFunction(_new, "new");

        // Error handling
        importFunction(error, "error!", Nil, ["message"]);
        importSpecialForm(throwsError, "error?");
        importSpecialForm(hissTry, "try");

        // Open Pandora's box if it's available:
        #if target.threaded
        importClass(HDeque, "Deque");
        importClass(HLock, "Lock");
        importClass(HMutex, "Mutex");
        importClass(HThread, "Thread");
        //importClass(Threading.Tls, "Tls");
        #end

        importFunction(repl, "repl");

        // TODO could handle all HissTools imports with an importClass() that doesn't apply a function prefix and converts is{Thing} to thing?
        // The only problem with that some functions need args wrapped and others don't

        // Dictionaries
        importCCFunction(makeDict, "dict");
        importFunction((dict: HValue, key) -> dict.toDict().get(key), "dict-get", T);
        importFunction((dict: HValue, key, value) -> dict.toDict().put(key, value), "dict-set!", T);
        importFunction((dict: HValue, key) -> dict.toDict().exists(key), "dict-contains", T);
        importFunction((dict: HValue, key) -> dict.toDict().erase(key), "dict-erase!", T);

        // command-line args
        importFunction(() -> List(scriptArgs), "args");

        // Primitive type predicates
        importFunction(HissTools.isInt, "int?", T);
        importFunction(HissTools.isFloat, "float?", T);
        importFunction(HissTools.isNumber, "number?", T);
        importFunction(HissTools.isSymbol, "symbol?", T);
        importFunction(HissTools.isString, "string?", T);
        importFunction(HissTools.isList, "list?", T);
        importFunction(HissTools.isDict, "dict?", T);
        importFunction(HissTools.isFunction, "function?", T);
        importFunction(HissTools.isMacro, "macro?", T);
        importFunction(HissTools.isCallable, "callable?", T);
        importFunction(HissTools.isObject, "object?", T);

        importFunction(HissTools.clear, "clear!", T);

        // Iterator tools
        importFunction(HissTools.iterable, "iterable", Nil, ["next", "has-next"]);
        importFunction(HissTools.iteratorToIterable, "iterator->iterable", Nil, ["haxe-iterator"]);

        // String functions:
        globals.put("StringTools", Object("Class", StringTools));
        importFunction(StringTools.startsWith, "starts-with");
        importFunction(StringTools.endsWith, "ends-with");
        importFunction(StringTools.lpad, "lpad");
        importFunction(StringTools.rpad, "rpad");

        // Debug info
        importFunction(HissTools.version, "version", []);

        // Sometimes it's useful to provide the interpreter with your own target-native print function
        // so they will be used while the standard library is being loaded.
        if (printFunction != null) {
            importFunction(printFunction, "print", Nil, ["value"]);
        }
        else {
            importFunction(HissTools.print, "print", T, ["value"]);
        }

        importFunction(HissTools.message, "message", T, ["value"]);

        // Functions/forms that could be bootstrapped with register-function, but save stack frames if not:
        importFunction(HissTools.length, "length", T, ["seq"]);
        importFunction(HissTools.reverse, "reverse", T, ["l"]);
        importFunction(HissTools.first, "first", T, ["l"]);
        importFunction(HissTools.rest, "rest", T, ["l"]);
        importFunction(HissTools.last, "last", T, ["l"]);
        importFunction(HissTools.eq.bind(_, this, _), "eq", T, ["a", "b"]);
        importFunction(HissTools.nth, "nth", T, ["l", "n"]);
        importFunction(HissTools.cons, "cons", T, ["val", "l"]);
        importFunction(HissTools.not, "not", T, ["val"]);
        importFunction(HissTools.sort, "sort", Nil, ["l, sort-function"]);
        importFunction(HissTools.range, "range", Nil, ["start", "end"]);
        importFunction(HissTools.alternates.bind(_, false), "even-alternates", T);
        importFunction(HissTools.alternates.bind(_, true), "odd-alternates", T);
        importFunction(HaxeTools.shellCommand, "shell-command", Nil, ["cmd"]);
        importFunction(read, "read", Nil, ["str"]);

        importFunction(HissTools.symbolName, "symbol-name", T, ["sym"]);
        importFunction(HissTools.symbol, "symbol", T, ["sym-name"]);

        importSpecialForm(quote, "quote");

        importCCFunction(VariadicFunctions.add, "+");
        importCCFunction(VariadicFunctions.subtract, "-");
        importCCFunction(VariadicFunctions.divide, "/");
        importCCFunction(VariadicFunctions.multiply, "*");
        importCCFunction(VariadicFunctions.numCompare.bind(Lesser), "<");
        importCCFunction(VariadicFunctions.numCompare.bind(LesserEqual), "<=");
        importCCFunction(VariadicFunctions.numCompare.bind(Greater), ">");
        importCCFunction(VariadicFunctions.numCompare.bind(GreaterEqual), ">=");
        importCCFunction(VariadicFunctions.numCompare.bind(Equal), "=");

        importCCFunction(VariadicFunctions.append, "append");

        importFunction((a, b) -> { return a % b;}, "%");

        importFunction(HaxeTools.readLine, "read-line");

        // Operating system
        importFunction(HissTools.homeDir, "home-dir", []);
        importFunction(StaticFiles.getContent, "get-content", ["file"]);
        #if (sys || hxnodejs)
        importClass(File, "File");
        importClass(FileOutput, "FileOutput");
        importFunction(Sys.sleep, "sleep!", ["duration"]);
        #end

        StaticFiles.compileWith("stdlib2.hiss");

        //disableTrace();
        load("stdlib2.hiss");
        //enableTrace();
    }

    function error(message: Dynamic) { throw message; }

    // error? will have an implicit begin
    function throwsError(args: HValue, env: HValue, cc: Continuation) {
        try {
            internalEval(Symbol("begin").cons(args), env, (val) -> {
                cc(Nil); // If the continuation is called, there is no error
            });
        } catch (err: Dynamic) {
            cc(T);
        }
    }

    function hissTry(args: HValue, env: HValue, cc: Continuation) {
        try {
            // Try cannot have an implicit begin because the second argument is the catch
            internalEval(args.first(), env, cc);
        } catch (err: Dynamic) {
            if (args.length() > 1) {
                internalEval(args.second(), env, cc);
            } else {
                cc(Nil);
            }
        }
    }

    function useBeginAndIterate(beginFunction: HFunction, iterateFunction: IterateFunction) {
        currentBeginFunction = beginFunction;
        globals.put("begin", SpecialForm(beginFunction, "begin"));
        importSpecialForm(iterateFunction.bind(true, true), "for");
        importSpecialForm(iterateFunction.bind(false, true), "do-for");
        importSpecialForm(iterateFunction.bind(true, false), "map");
        importSpecialForm(iterateFunction.bind(false, false), "do-map");
        return Nil;
    }

    /** Run a Hiss REPL from this interpreter instance **/
    public function repl(useConsoleReader=true) {
        #if (sys || hxnodejs)
        var cReader = null;
        if (useConsoleReader) cReader = new ConsoleReader(-1, Path.join([HissTools.homeDir(), ".hisstory"]));
        // The REPL needs to make sure its ConsoleReader actually saves the history on exit, so quit() is provided here
        // differently than the version in stdlib2.hiss :)
        importFunction(() -> {
            if (useConsoleReader) {
                cReader.saveHistory();
            }
            throw HSignal.Quit;
        }, "quit");
        var locals = emptyEnv(); // This allows for top-level setlocal

        HaxeTools.println('Hiss version ${CompileInfo.version()}');
        HaxeTools.println("Type (quit) to quit the REPL");

        while (true) {
            HaxeTools.print(">>> ");
            
            var next = "";
            if (useConsoleReader) {
                cReader.cmd.prompt = ">>> ";

                next = cReader.readLine();
            } else {
                next = Sys.stdin().readLine();
            }

            //interp.disableTrace();
            var exp = null;
            try {
                exp = read(next);
            } catch (err: Dynamic) {
                HaxeTools.println('Reader error: $err');
                continue;
            }
            //interp.enableTrace();
            try {
                internalEval(exp, locals, HissTools.print);
            }
            catch (e: HSignal) {
                switch (e) {
                    case Quit:
                        return;
                }
            }
            #if !throwErrors
            catch (s: String) {
                HaxeTools.println('Error "$s" from `${exp.toPrint()}`');
                HaxeTools.println('Callstack depth ${CallStack.callStack().length}');
            } catch (err: Dynamic) {
                HaxeTools.println('Error type ${Type.typeof(err)}: $err from `${exp.toPrint()}`');
                HaxeTools.println('Callstack depth ${CallStack.callStack().length}');
            }
            #end
        }
        #else
        throw "This Hiss interpreter is not compiled with REPL support.";
        #end
    }

    /** Command-line entrypoint for Hiss. Usage:

            hiss [file.hiss] -- run a hiss script
            hiss -- start a REPL

    **/
    public static function main() {
        var interp = new CCInterp();

        run(interp);
    }

    var scriptArgs: HList = [];

    public static function run(interp: CCInterp, ?args: Array<String>) {
        #if (sys || hxnodejs)
        if (args == null) {
            args = Sys.args();
        }
        
        var useConsoleReader = true;
        var script = null;

        var nextArg = null;
        while (args.length > 0) {
            var nextArg = args.shift();
            switch (nextArg) {
                case "--nocr" | "--no-cr" | "--no-console-reader":
                    useConsoleReader = false;
                case _ if (nextArg.endsWith(".hiss")):
                    script = nextArg;
                // Args after the script path are passed to the script to be accessed by (args)
                case _ if (script != null):
                    interp.scriptArgs.push(String(nextArg));
            }
        }

        #if js
        // On JS we might as well never try to use the console reader
        useConsoleReader = false;
        #end

        if (script != null) {
            interp.load(script);
        } else {
            interp.repl(useConsoleReader);
        }
        #else
        trace("Hiss cannot run as a console application on this target.");
        #end

    }

    public function load(file: String) {
        _load(List([String(file)]), emptyEnv(), noCC);
    }

    function _load(args: HValue, env: HValue, cc: Continuation) {
        readingProgram = true;
        var exps = reader.readAll(String(StaticFiles.getContent(args.first().value())));
        readingProgram = false;

        // Let the user decide whether to load tail-recursively or not:
        currentBeginFunction(exps, env, cc);
    }

    function envWithReturn(env: HValue, called: RefBool) {
        var stackFrameWithReturn = emptyDict();
        stackFrameWithReturn.put("return", Function((args, env, cc) -> {
            called.b = true;
            cc(args.first());
        }, "return"));
        return env.extend(stackFrameWithReturn);
    }

    function envWithBreakContinue(env: HValue, breakCalled: RefBool, continueCalled: RefBool) {
        var stackFrameWithBreakContinue = emptyDict();
        stackFrameWithBreakContinue.put("continue", Function((_, _, continueCC) -> {
            continueCalled.b = true; continueCC(Nil);
        }, "continue", []));
        stackFrameWithBreakContinue.put("break", Function((_, _, breakCC) -> {
            breakCalled.b = true; breakCC(Nil);
        }, "break", []));
        return env.extend(stackFrameWithBreakContinue);
    }

    /**
        This tail-recursive implementation of begin breaks callCC.
        Toggle between tail recursion and continuation support with
        (enable-tail-recursion), (disable-tail-recursion),
                               X
        (enable-continuations), (disable-continuations)

        (The X denotes equivalent functions)
    **/
    function trBegin(exps: HValue, env: HValue, cc: Continuation) {
        var returnCalled = new RefBool();
        env = envWithReturn(env, returnCalled);
        var value = eval(exps.first(), env);

        if (returnCalled.b || !exps.rest().truthy()) {
            cc(value);
        }
        else {
            trBegin(exps.rest(), env, cc);
        }
    }

    function begin(exps: HValue, env: HValue, cc: Continuation) {
        var returnCalled = new RefBool();
        env = envWithReturn(env, returnCalled);

        internalEval(exps.first(), env, (result) -> {
            if (returnCalled.b || !exps.rest().truthy()) {
                cc(result);
            }
            else {
                begin(exps.rest(), env, cc);
            }
        });
    }

    function specialForm(args: HValue, env: HValue, cc: Continuation) {
        #if traceCallstack
        HaxeTools.println('${CallStack.callStack().length}: ${args.toPrint()}');
        #end
        args.first().toCallable()(args.rest(), env, cc);
    }

    function macroCall(args: HValue, env: HValue, cc: Continuation) {
        specialForm(args, env, (expansion: HValue) -> {
            #if traceMacros
            HaxeTools.println('${args.toPrint()} -> ${expansion.toPrint()}');
            #end
            internalEval(expansion, env, cc);
        });
    }

    function funcall(callInline: Bool, args: HValue, env: HValue, cc: Continuation) {
        #if traceCallstack
        HaxeTools.println('${CallStack.callStack().length}: ${args.toPrint()}');
        #end
        evalAll(args, env, (values) -> {
            // trace(values.toPrint());
            values.first().toHFunction()(values.rest(), if (callInline) env else emptyEnv(), cc);
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

    function set(type: SetType, args: HValue, env: HValue, cc: Continuation) {
        internalEval(args.second(),
            env, (val) -> {
                var scope = null;
                switch (type) {
                    case Global:
                        scope = globals;
                    case Local:
                        scope = env.first();
                    case Destructive:
                        for (frame in env.toList()) {
                            var frameDict = frame.toDict();
                            if (frameDict.exists(args.first())) {
                                scope = frame;
                                break;
                            }
                        }
                        if (scope == null) scope = globals;
                }
                scope.put(args.first().symbolName(), val);
                cc(val);
            });
    }

    function setCallable(isMacro: Bool, args: HValue, env: HValue, cc: Continuation) {
        lambda(isMacro, args.rest(), env, (fun: HValue) -> {
            set(Global, args.first().cons(List([fun])), env, cc);
        }, args.first().symbolName());
    }

    function _if(args: HValue, env: HValue, cc: Continuation) {
        if (args.length() > 3) {
            throw '(if) called with too many arguments. Try wrapping the cases in (begin)';
        }
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

        var v = null;
        for (frame in stackFrames) {
            var frameDict = frame.toDict();
            if (frameDict.exists(name)) {
                v = frameDict.get(name);
                break;
            }
        }
        cc(if (v != null) {
            v;
        } else if (g.exists(name)) {
            g.get(name);
        } else {
            throw '$name is undefined';
        });
    }

    function lambda(isMacro: Bool, args: HValue, env: HValue, cc: Continuation, name = "[anonymous lambda]") {
        var params = args.first();

        var body = Symbol('begin').cons(args.rest());
        var hFun: HFunction = (fArgs, innerEnv, fCC) -> {
            var callEnv = List(env.toList().concat(innerEnv.toList()));
            callEnv = callEnv.extend(params.destructuringBind(this, fArgs)); // extending the outer env is how lambdas capture values
            internalEval(body, callEnv, fCC);
        };
        var callable = if (isMacro) {
            Macro(hFun, "[anonymous macro]");
        } else {
            var paramNames = [for (paramSymbol in params.toList()) paramSymbol.symbolName()];
            Function(hFun, "[anonymous lambda]", paramNames);
        };
        cc(callable);
    }

    // Helper function to get the iterable object in iterate() and iterateCC()
    function iterable(bodyForm: Bool, args: HValue, env: HValue, cc: Continuation) {
        internalEval(if (bodyForm) {
            args.second();
        } else {
            args.first();
        }, env, cc);
    }

    function performIteration(bodyForm: Bool, args:HValue, env: HValue, cc: Continuation, performFunction: PerformIterationFunction) {
        if (bodyForm) {
            var body = List(args.toList().slice(2));
            performFunction((innerArgs, innerEnv, innerCC) -> {
                // If it's body form, the values of the iterable need to be bound for the body
                // (potentially with list destructuring)
                var bodyEnv = innerEnv.extend(args.first().destructuringBind(this, innerArgs.first()));
                internalEval(Symbol("begin").cons(body), bodyEnv, innerCC);
            }, env, cc);
        } else {
            // If it's function form, a name symbol is not necessary
            internalEval(args.second(), env, (fun) -> { 
                performFunction(fun.toHFunction(), emptyEnv(), cc);
            });
        }
    }

    /**
        Stack-safe implementation behind (for), (do-for), (map), and (do-map)
    **/
    function iterate(collect: Bool, bodyForm: Bool, args: HValue, env: HValue, cc: Continuation) {
        var it: HValue = Nil;
        iterable(bodyForm, args, env, (_iterable) -> { it = _iterable; });
        var iterable: Iterable<HValue> = it.value(true);

        function synchronousIteration(operation: HFunction, innerEnv: HValue, outerCC: Continuation) {
            var results = [];
            var continueCalled = new RefBool();
            var breakCalled = new RefBool();

            innerEnv = envWithBreakContinue(innerEnv, breakCalled, continueCalled);

            var iterationCC = if (collect) {
                (result) -> {
                    if (continueCalled.b || breakCalled.b) {
                        continueCalled.b = false;
                        return;
                    }
                    results.push(result);
                };
            } else {
                noCC;
            }

            for (value in iterable) {
                operation(List([value]), innerEnv, iterationCC);
                if (breakCalled.b) break;
            }

            outerCC(List(results));
        }

        performIteration(bodyForm, args, env, cc, synchronousIteration);
    }

    /**
        Continuation-based (and therefore dangerous!) implementation
    **/
    function iterateCC(collect: Bool, bodyForm: Bool, args: HValue, env: HValue, cc: Continuation) {
        iterable(bodyForm, args, env, (it) -> {
            var iterable: Iterable<HValue> = it.value(true);
            var iterator = iterable.iterator();

            var results = [];
            var continueCalled = new RefBool();
            var breakCalled = new RefBool();

            env = envWithBreakContinue(env, breakCalled, continueCalled);

            function asynchronousIteration(operation: HFunction, innerEnv: HValue, outerCC: Continuation) {
                if (!iterator.hasNext()) {
                    outerCC(List(results));
                } else {
                    operation(List([iterator.next()]), innerEnv, (value) -> {
                        if (breakCalled.b) {
                            outerCC(List(results));
                        } else {
                            if (collect && !continueCalled.b) {
                                results.push(value);
                            }
                            continueCalled.b = false;

                            asynchronousIteration(operation, innerEnv, outerCC);
                        }
                    });
                }
                
            }

            performIteration(bodyForm, args, env, cc, asynchronousIteration);
        });
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
                internalEval(Symbol("begin").cons(body), env.extend(names.destructuringBind(this, SpecialForm(recur, "recur").cons(values))), (value) -> {result = value;});
                
            } while (recurCalled);
            cc(result);
        });
    }

    function bound(args: HValue, env: HValue, cc: Continuation) {
        var stackFrames = env.toList();
        var g = globals.toDict();
        var name = args.first();

        for (frame in stackFrames) {
            var frameDict = frame.toDict();
            if (frameDict.exists(name)) {
                cc(T);
                return;
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
        var haxeCallArgs = if (args.length() < 3) {
            [];
        } else {
            args.third().unwrapList(this, keepArgsWrapped);
        };

        var caller = args.first().value(callOnReference);
        var methodName = args.second().toHaxeString();
        var method = Reflect.getProperty(caller, methodName);

        if (method == null) {
            throw 'There is no haxe method called $methodName on ${args.first().toPrint()}';
        } else {
            cc(Reflect.callMethod(caller, method, haxeCallArgs).toHValue());
        }
    }

    static var ccNum = 0;
    function callCC(args: HValue, env: HValue, cc: Continuation) {
        var ccId = ccNum++;
        // Convert the continuation to a hiss function accepting one argument
        var ccHFunction = Function((innerArgs: HValue, innerEnv: HValue, innerCC: Continuation) -> {
            var arg = if (!innerArgs.truthy()) {
                // It's typical to JUST want to break out of a sequence, not return a value to it.
                Nil;
            } else {
                innerArgs.first();
            };

            trace('calling cc#$ccId with ${arg.toPrint()}');

            cc(arg);
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
                                idx--; // continue; would be better, but this is a callback!
                            });
                        // If an UnquoteList is quoted, apply the quote to each expression in the list
                        case Quote(UnquoteList(exp)):
                            copy.splice(idx, 1);
                            internalEval(exp, env, (innerList) -> {
                                for (exp in innerList.toList()) { 
                                    copy.insert(idx++, Quote(exp));
                                }
                                idx--;
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

    function makeDict(args: HValue, env: HValue, cc: Continuation) {
        var dict = new HDict(this);

        var idx = 0;
        while (idx < args.length()) {
            var key = args.nth(Int(idx));
            var value = args.nth(Int(idx+1));
            dict.put(key, value);
            idx += 2;
        }

        cc(Dict(dict));
    }

    /** Hiss-callable form for eval **/
    function _eval(args: HValue, env: HValue, cc: Continuation) {
        internalEval(args.first(), env, (val) -> {
            internalEval(val, env, cc);
        });
    }

    /** Public, synchronous form of eval. Won't work with javascript asynchronous functions **/
    public function eval(arg: HValue, ?env: HValue) {
        var value = null;
        if (env == null) env = emptyEnv();
        internalEval(arg, env, (_value) -> {
            value = _value;
        });
        return value;
    }

    /** Asynchronos-friendly form of eval. NOTE: The args are out of order so this isn't an HFunction. **/
    public function evalCC(arg: HValue, cc: Continuation, ?env: HValue) {
        if (env == null) env = emptyEnv();
        internalEval(arg, env, cc);
    }

    /** Core form of eval -- continuation-based, takes one expression **/
    private function internalEval(exp: HValue, env: HValue, cc: Continuation) {
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
                        interpolated = interpolated.substr(0, idx - 1) + interpolated.substr(idx++);
                        continue;
                    }

                    var expStream = HStream.FromString(interpolated.substr(idx+1));

                    // Allow ${name} so a space isn't required to terminate the symbol
                    var exp = null;
                    var expLength = -1;
                    if (expStream.peek(1) == "{") {
                        expStream.drop("{");
                        var braceContents = HaxeTools.extract(expStream.takeUntil(['}'], false, false, true), Some(o) => o).output;
                        expStream = HStream.FromString(braceContents);
                        expLength = 2 + expStream.length();
                        exp = reader.read("", expStream);
                    } else {
                        var startingLength = expStream.length();
                        exp = reader.read("", expStream);
                        expLength = startingLength - expStream.length();
                    }
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
                        default: throw 'Hiss cannot call $callable from ${exp.first().toPrint()}';
                    }
                });
            default:
                throw 'Cannot evaluate $exp yet';
        }
    }
}

typedef IterateFunction = (collect: Bool, bodyForm: Bool, args: HValue, env: HValue, cc: Continuation) -> Void;
typedef PerformIterationFunction = (operation: HFunction, env: HValue, cc: Continuation) -> Void;