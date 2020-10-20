package hiss;

import Type;
using Type;
import Reflect;
using Reflect;
import Std;
import haxe.CallStack;
import haxe.Constraints.Function;
import haxe.io.Path;
import haxe.Log;
import haxe.Timer;
import hx.strings.Strings;
using hx.strings.Strings;

import hiss.wrappers.HHttp;
import hiss.wrappers.HDate;
import hiss.wrappers.HStringTools;

import hiss.HTypes;
#if (sys || hxnodejs)
import hiss.wrappers.HFile;
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
import hiss.Stdlib;
using hiss.Stdlib;
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
    
    var errorHandler: (Dynamic) -> Void = null;

    public function setErrorHandler(handler: (Dynamic) -> Void) {
        errorHandler = handler;
    }

    public function error(message: Dynamic) {
        if (errorHandler != null) {
            errorHandler(message);
        } else {
            throw message;
        }
    }

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
    #if traceClassImports
    var debugClassImports = true;
    #else
    var debugClassImports = false;
    #end

    // functions starting with is[Something] will be imported without the is, using predicateSuffix
    // TODO static functions with 'cc' in the metaSignature will be imported as ccfunctions with interp bound as the first argument (NOTE this will need to bypass reflect.callmethod in order to preserve asyncness)
    // TODO functions that convert [type1]To[type2] else will be imported with use conversionInfix instead of To 
    // functions with 'i' in the metaSignature will be imported with this interp bound as the first argument
    // functions with 'h' in the metaSignature will keep their args wrapped
    // functions with 'd' for destructive in the metaSignature will use sideEffectSuffix
    //     but also define an alias with a warning
    // functions and properties starting with an underscore will not be imported
    public function importClass(clazz: Class<Dynamic>, meta: ClassMeta) {
        if (debugClassImports) {
            trace('Import ${meta.name}');
        }
        globals.put(meta.name, Object("Class", clazz));

        if (meta.omitMemberPrefixes == null) {
            meta.omitMemberPrefixes = false;
        }
        if (meta.omitStaticPrefixes == null) {
            meta.omitStaticPrefixes = false;
        }
        // By default, convert names of functions and properties into the form name-to-lower-hyphen
        if (meta.convertNames == null) {
            meta.convertNames = Strings.toLowerHyphen;
        }
        
        if (meta.getterPrefix == null) {
            meta.getterPrefix = "get-";
        }
        if (meta.setterPrefix == null) {
            meta.setterPrefix = "set-";
        }
        if (meta.sideEffectSuffix == null) {
            meta.sideEffectSuffix = "!";
        }
        if (meta.predicateSuffix == null) {
            meta.predicateSuffix = "?";
        }
        if (meta.conversionInfix == null) {
            meta.conversionInfix = "->";
        }

        var dummyInstance = clazz.createEmptyInstance();
        for (instanceField in clazz.getInstanceFields()) {
            if (instanceField.startsWith("_")) continue;
            var fieldValue = Reflect.getProperty(dummyInstance, instanceField);
            switch (Type.typeof(fieldValue)) {
                // Import methods:
                case TFunction:
                    var metaSignature = "";
                    if (instanceField.contains("_")) {
                        metaSignature = instanceField.split("_")[1];
                        instanceField = instanceField.substr(0, instanceField.indexOf("_"));
                    }

                    var bindInterpreter = metaSignature.contains("i");
                    var wrapArgs = if (metaSignature.contains("h")) T else Nil;
                    var destructive = metaSignature.contains("d");
                    // TODO do something with ccFunctions
                    var ccFunction = metaSignature.contains("cc");
                    var isPredicate = (instanceField.toLowerHyphen().split("-")[0] == "is");
                    if (isPredicate) instanceField = instanceField.substr(2); // drop the 'is'
                    var translatedName = meta.convertNames(instanceField);
                    if (isPredicate) translatedName += meta.predicateSuffix;
                    if (destructive) translatedName += meta.sideEffectSuffix;
                    if (!meta.omitMemberPrefixes) {
                        translatedName = meta.name + ":" + translatedName;
                    }
                    if (debugClassImports) {
                        trace(translatedName);
                    }
                    globals.put(translatedName, Function((args, env, cc) -> {
                        var instance = args.first().value(this);
                        var argArray = args.rest_h().unwrapList(this, wrapArgs);

                        if (bindInterpreter) {
                            argArray.insert(0, this);
                        }
                        // We need an empty instance for checking the types of the properties.
                        // BUT if we get our function pointers from the empty instance, the C++ target
                        // will segfault when we try to call them, so getProperty has to be called every time
                        var methodPointer = Reflect.getProperty(instance, instanceField);
                        var returnValue: Dynamic = Reflect.callMethod(instance, methodPointer, argArray);
                        cc(returnValue.toHValue());
                    }, {name:translatedName}));
                default:
                    // generate getters and setters for instance fields
                    // TODO this approach is naive. It only finds properties that are returned by getProperty() which hopefully
                    // excludes ones that aren't publicly readable (TODO test that). It also generates setters for ALL publicly readable
                    // properties, which may include some that aren't publicly writeable. Maybe trying setProperty() with a dummy
                    // value to check if the write succeeds somehow, then setting it back, would catch that.

                    // TODO One approach to privacy would be to just ignore properties with _ in front,
                    // if I commit to saying importClass() is only for specially formed classes.

                    // TODO test these imports
                    var getterTranslatedName = meta.convertNames(instanceField);
                    getterTranslatedName = meta.getterPrefix + getterTranslatedName;
                    if (!meta.omitMemberPrefixes) {
                        getterTranslatedName = meta.name + ":" + getterTranslatedName;
                    }
                    if (debugClassImports) {
                        trace(getterTranslatedName);
                    }
                    globals.put(getterTranslatedName, Function((args, env, cc) -> {
                        var instance = args.first().value(this);
                        var value : Dynamic = Reflect.getProperty(instance, instanceField);
                        cc(value.toHValue());
                    }, {name:getterTranslatedName}));

                    var setterTranslatedName = meta.convertNames(instanceField);
                    setterTranslatedName = meta.setterPrefix + setterTranslatedName + meta.sideEffectSuffix;
                    if (!meta.omitMemberPrefixes) {
                        setterTranslatedName = meta.name + ":" + setterTranslatedName;
                    }
                    if (debugClassImports) {
                        trace(setterTranslatedName);
                    }
                    globals.put(setterTranslatedName, Function((args, env, cc) -> {
                        var instance = args.first().value(this);
                        var value = args.second().value(this);
                        Reflect.setProperty(instance, instanceField, value);
                        cc(args.second());
                    }, {name:setterTranslatedName}));
                    // It can be confusing to forget the ! when trying to use a setter, so allow usage without ! but with a warning:
                    if (setterTranslatedName.endsWith("!")) {
                        defAlias(List([Symbol(setterTranslatedName), Symbol(setterTranslatedName.substr(0, setterTranslatedName.length - 1)), Symbol("@deprecated")]), emptyEnv(), noCC);
                    }
            }
        }

        for (classField in clazz.getClassFields()) {
            if (classField.startsWith("_")) continue;
            // TODO this logic is much-repeated from the above for-loop
            var fieldValue = Reflect.getProperty(clazz, classField);
            switch (Type.typeof(fieldValue)) {
                case TFunction:
                    var metaSignature = "";
                    if (classField.contains("_")) {
                        metaSignature = classField.split("_")[1];
                        classField = classField.substr(0, classField.indexOf("_"));
                    }

                    var bindInterpreter = metaSignature.contains("i");
                    var wrapArgs = if (metaSignature.contains("h")) T else Nil;
                    var destructive = metaSignature.contains("d");
                    // TODO do something with ccFunctions
                    var ccFunction = metaSignature.contains("cc");
                    var isPredicate = (classField.toLowerHyphen().split("-")[0] == "is");
                    if (isPredicate) classField = classField.substr(2); // drop the 'is'
                    var translatedName = meta.convertNames(classField);
                    if (isPredicate) translatedName += meta.predicateSuffix;
                    if (destructive) translatedName += meta.sideEffectSuffix;
                    if (!meta.omitStaticPrefixes) {
                        translatedName = meta.name + ":" + translatedName;
                    }
                    if (debugClassImports) {
                        trace(translatedName);
                    }
                    globals.put(translatedName, Function((args, env, cc) -> {
                        var argArray = args.unwrapList(this, wrapArgs);
                        if (bindInterpreter) {
                            argArray.insert(0, this);
                        }
                        cc(Reflect.callMethod(clazz, fieldValue, argArray).toHValue());
                    }, {name:translatedName}));
                default:
                    // TODO generate getters and setters for static properties
            }
        }
    }

    function _new(args: HValue, env: HValue, cc: Continuation) {
        var clazz: Class<Dynamic> = args.first().value(this);
        var args = args.rest_h().unwrapList(this);
        var instance: Dynamic = Type.createInstance(clazz, args);
        cc(instance.toHValue());
    }

    public function importFunction(instance: Dynamic, func: Function, meta: CallableMeta, keepArgsWrapped: HValue = Nil) {
        globals.put(meta.name, Function((args: HValue, env: HValue, cc: Continuation) -> {
            cc(Reflect.callMethod(instance, func, args.unwrapList(this, keepArgsWrapped)).toHValue());
        }, meta));
    }

    public function importCCFunction(func: HFunction, meta: CallableMeta) {
        globals.put(meta.name, Function(func, meta));
    }

    public function importSpecialForm(func: HFunction, meta: CallableMeta) {
        globals.put(meta.name, SpecialForm(func, meta));
    }

    // TODO this is like register-method but never used.
    function importMethod(method: String, meta: CallableMeta, callOnReference: Bool, keepArgsWrapped: HValue, returnInstance: Bool) {
        globals.put(meta.name, Function((args: HValue, env: HValue, cc: Continuation) -> {
            var instance = args.first().value(this, callOnReference);
            cc(instance.callMethod(instance.getProperty(method), args.rest_h().unwrapList(this, keepArgsWrapped)).toHValue());
        }, meta));
    }

    public static function noOp (args: HValue, env: HValue, cc: Continuation) { }
    public static function noCC (arg: HValue) { }

    var currentBeginFunction: HFunction = null;
    var currentEvalAllFunction: HFunction = null;

    static function emptyList() { return List([]); }

    public function emptyDict() { return Dict(new HDict(this)); }

    public function emptyEnv() { return List([emptyDict()]); }

    // TODO declutter the constructor by refactoring to allow importClass(CCInterp) and importClass(HissTools) (and importClass of whatever functions get split out of HissTools)
    public function new(?printFunction: (Dynamic) -> Dynamic) {
        HissTestCase.reallyTrace = Log.trace;

        globals = emptyDict();
        reader = new HissReader(this);

        // convention: functions with side effects end with ! unless they start with def
        
        // When not a repl, use Sys.exit for quitting
        #if (sys || hxnodejs)
        importFunction(Sys, Sys.exit.bind(0), { name: "quit!", argNames: [] });
        #end

        // Primitives
        importSpecialForm(set.bind(Global), { name: "defvar" });
        importSpecialForm(set.bind(Local), { name: "setlocal!" });
        importSpecialForm(set.bind(Destructive), { name: "set!" });
        importSpecialForm(setCallable.bind(false), { name: "defun" });
        importSpecialForm(setCallable.bind(true), { name: "defmacro" });
        importSpecialForm(defAlias, {name: "defalias"});
        importFunction(this, docs, {name: "docs", argNames: ["callable"]}, T);
        importFunction(this, help, {name: "help", argNames: []});
        importSpecialForm(_if, { name: "if" });
        importSpecialForm(lambda.bind(false), { name: "lambda" });
        importSpecialForm(callCC, { name: "call/cc" });
        importSpecialForm(_eval, { name: "eval" });
        importSpecialForm(bound, { name: "bound?" });
        importCCFunction(_load, { name: "load!", argNames: ["file"] });
        importSpecialForm(funcall.bind(false), { name: "funcall" });
        importSpecialForm(funcall.bind(true), { name: "funcall-inline" });
        importSpecialForm(loop, { name: "loop" });
        importSpecialForm(or, { name: "or" });
        importSpecialForm(and, { name: "and" });

        // Use tail-recursive begin and iterate by default:
        useFunctions(trBegin, trEvalAll, iterate);

        // Allow switching at runtime:
        importFunction(this, useFunctions.bind(trBegin, trEvalAll, iterate), { name: "disable-cc!" });
        importFunction(this, useFunctions.bind(begin, evalAll, iterateCC), { name: "enable-cc!" });

        // First-class unit testing:
        importSpecialForm(HissTestCase.testAtRuntime.bind(this), { name: "test" });
        importCCFunction(HissTestCase.hissPrints.bind(this), { name: "prints" });

        // Haxe interop -- We could bootstrap the rest from these if we had unlimited stack frames:
        importClass(HType, {name: "Type"});
        importCCFunction(getProperty, { name: "get-property" });
        importCCFunction(callHaxe, { name: "call-haxe" });
        importCCFunction(_new, { name: "new" });

        // Error handling
        importFunction(this, error, { name: "error!", argNames: ["message"] }, Nil);
        importSpecialForm(throwsError, { name: "error?" });
        importSpecialForm(hissTry, { name: "try" });

        importClass(HStream, {name: "HStream"});
        importFunction(reader, reader.setMacroString, {name: "set-macro-string!", argNames:  ["string", "read-function"]}, List([Int(1)]));
        importFunction(reader, reader.setDefaultReadFunction, {name: "set-default-read-function!", argNames: ["read-function"]}, T);
        importFunction(reader, reader.readNumber, {name: "read-number", argNames: ["start", "stream"]}, Nil);
        importFunction(reader, reader.readString, {name: "read-string", argNames: ["start", "stream"]}, Nil);
        importFunction(reader, reader.readSymbol, {name: "read-symbol", argNames: ["start", "stream"]}, Nil);
        importFunction(reader, reader.nextToken, {name: "HStream:next-token!", argNames: ["stream"]}, Nil);
        importFunction(reader, reader.readDelimitedList, {name: "read-delimited-list", argNames: ["terminator", "delimiters", "eof-terminates", "blank-elements", "start", "stream"]}, List([Int(3)]) /* keep blankElements wrapped */);
        importFunction(reader, reader.copyReadtable, {name: "copy-readtable"});
        importFunction(reader, reader.useReadtable, {name: "use-readtable!"});
        importFunction(this, () -> new HDict(this), {name: "empty-readtable"});

        // Open Pandora's box if it's available:
        #if target.threaded
        importClass(HDeque, {name: "Deque"});
        importClass(HLock, {name: "Lock"});
        importClass(HMutex, {name: "Mutex"});
        importClass(HThread, {name:"Thread"});
        //importClass(Threading.Tls, "Tls");
        #end

        importFunction(this, repl, {name:"repl"});

        // TODO could handle all HissTools imports with an importClass() that doesn't apply a function prefix and converts is{Thing} to thing?
        // The only problem with that some functions need args wrapped and others don't

        // Dictionaries
        importCCFunction(makeDict, {name:"dict"});
        importFunction(this, (dict: HValue, key) -> dict.toDict().get(key), {name: "dict-get"}, T);
        importFunction(this, (dict: HValue, key, value) -> dict.toDict().put(key, value), {name: "dict-set!"}, T);
        importFunction(this, (dict: HValue, key) -> dict.toDict().exists(key), {name: "dict-contains"}, T);
        importFunction(this, (dict: HValue, key) -> dict.toDict().erase(key), {name: "dict-erase!"}, T);

        // command-line args
        importFunction(this, () -> List(scriptArgs), {name: "args"});

        // String functions:
        importClass(HStringTools, {name: "StringTools", omitStaticPrefixes: true});

        importClass(Stdlib, {name: "Stdlib", omitStaticPrefixes: true});

        // Sometimes it's useful to provide the interpreter with your own target-native print function
        // so they will be used while the standard library is being loaded.
        if (printFunction != null) {
            importFunction(this, printFunction, {name: "print!", argNames: ["value"]},Nil);
        }

        importFunction(this, not, {name: "not", argNames: ["val"]}, T);
    
        importFunction(HaxeTools, HaxeTools.shellCommand, {name: "shell-command", argNames: ["cmd"]}, Nil);
        importFunction(this, read, {name: "read", argNames: ["string"]}, Nil);
        importFunction(this, readAll, {name: "read-all", argNames: ["string"]}, Nil);

        importSpecialForm(quote, {name:"quote"});

        importCCFunction(VariadicFunctions.add.bind(this), {name: "+"});
        importCCFunction(VariadicFunctions.subtract.bind(this), {name: "-"});
        importCCFunction(VariadicFunctions.divide.bind(this), {name: "/"});
        importCCFunction(VariadicFunctions.multiply.bind(this), {name: "*"});
        importCCFunction(VariadicFunctions.numCompare.bind(this, Lesser), {name: "<"});
        importCCFunction(VariadicFunctions.numCompare.bind(this, LesserEqual), {name: "<="});
        importCCFunction(VariadicFunctions.numCompare.bind(this, Greater), {name: ">"});
        importCCFunction(VariadicFunctions.numCompare.bind(this, GreaterEqual), {name: ">="});
        importCCFunction(VariadicFunctions.numCompare.bind(this, Equal), {name: "="});
        
        // Std
        importFunction(Std, Std.random, {name:"random"});
        importFunction(Std, Std.parseInt, {name: "int"});
        importFunction(Std, Std.parseFloat, {name: "float"});

        importCCFunction(VariadicFunctions.append, {name: "append"});

        importFunction(this, (a, b) -> { return a % b; }, {name: "%", argNames: ["a", "b"]});

        importFunction(HaxeTools, HaxeTools.readLine, {name: "read-line", argNames: []});

        // Operating system
        importFunction(StaticFiles, StaticFiles.getContent, { name: "get-content", argNames: ["file"] });
        #if (sys || hxnodejs)
        importClass(HFile, {name: "File"});
        importFunction(Sys, Sys.sleep, { name: "sleep!", argNames: ["seconds"] });
        importFunction(Sys, Sys.getEnv, { name: "get-env", argNames: ["var"]});
        #else
        importCCFunction(sleepCC, { name: "sleep!", argNames: ["seconds"] });
        #end

        importCCFunction(delay, { name: "delay!", argNames: ["func", "seconds"] });

        // Take special care when importing this one because it also contains cc functions that importClass() would handle wrong
        importClass(HHttp, {name: "Http"});
        // Just re-import to overwrite the CC function which shouldn't be imported normally:
        importCCFunction(HHttp.request.bind(this), { name: "Http:request" });
        // TODO handle functions suffixed with CC so they're imported that way always?
        // ^ Although that wouldn't handle the binding part.

        importClass(HDate, {name:"Date"});

        importFunction(this, python, { name: "python", argNames: [] });

        StaticFiles.compileWith("stdlib2.hiss");

        //disableTrace();
        load("stdlib2.hiss");
        //enableTrace();
    }

    function not(v: HValue) {
        return if (truthy(v)) Nil else T;
    }

    // It's absurd that we should have to provide this function...
    function python() { 
        #if hissUsePython3
        return "python3";
        #else
        return "python";
        #end
    }

    // error? will have an implicit begin
    function throwsError(args: HValue, env: HValue, cc: Continuation) {
        try {
            internalEval(Symbol("begin").cons_h(args), env, (val) -> {
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
        } catch (sig: HSignal) {
            throw sig;
        } catch (err: Dynamic) {
            // TODO let the catch access the error message
            if (args.length_h() > 1) {
                internalEval(args.second(), env, cc);
            } else {
                cc(Nil);
            }
        }
    }

    // TODO make public enableCC() and disableCC()
    function useFunctions(beginFunction: HFunction, evalAllFunction: HFunction, iterateFunction: IterateFunction) {
        currentBeginFunction = beginFunction;
        currentEvalAllFunction = evalAllFunction;
        globals.put("begin", SpecialForm(beginFunction,{name:"begin"}));
        importSpecialForm(iterateFunction.bind(true, true), {name:"for"});
        importSpecialForm(iterateFunction.bind(false, true), {name:"do-for"});
        importSpecialForm(iterateFunction.bind(true, false), {name:"map"});
        importSpecialForm(iterateFunction.bind(false, false), {name:"do-map"});
        return Nil;
    }

    /** Run a Hiss REPL from this interpreter instance **/
    public function repl(useConsoleReader=true) {
        StaticFiles.compileWith("repl-lib.hiss");
        load("repl-lib.hiss");

        
        var history = [];
        importFunction(this, () -> history, {name:"history"});
        importFunction(this, (str) -> history[history.length-1] = str, {name:"rewrite-history"});
        #if (sys || hxnodejs)
        var historyFile = Path.join([Stdlib.homeDir(), ".hisstory"]);
        history = sys.io.File.getContent(historyFile).split("\n");

        var cReader = null;
        if (useConsoleReader) cReader = new ConsoleReader(-1, historyFile);
        // The REPL needs to make sure its ConsoleReader actually saves the history on exit, so quit() is provided here
        // differently than the version in stdlib2.hiss :)
        importFunction(this, () -> {
            if (useConsoleReader) {
                cReader.saveHistory();
            }
            throw HSignal.Quit;
        }, {name:"quit!"});
        var locals = emptyEnv(); // This allows for top-level setlocal

        HaxeTools.println('Hiss version ${CompileInfo.version()}');
        HaxeTools.println("Type (help) for a list of functions, or (quit) to quit the REPL");

        while (true) {
            HaxeTools.print(">>> ");
            
            var next = "";
            if (useConsoleReader) {
                cReader.cmd.prompt = ">>> ";

                next = cReader.readLine();
            } else {
                next = Sys.stdin().readLine();
            }
            history.push(next);

            //interp.disableTrace();
            var exp = null;
            try {
                exp = read(next);
            } catch (err: Dynamic) {
                HaxeTools.println('Reader error: $err');
                continue;
            }
            //interp.enableTrace();

            // TODO errors from async functions won't be caught by this, so use errorHandler instead of try-catch
            try {
                internalEval(exp, locals, Stdlib.print_hd);
            }
            catch (e: HSignal) {
                switch (e) {
                    case Quit:
                        return;
                }
            }
            #if (!throwErrors)
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
        error("This Hiss interpreter is not compiled with REPL support.");
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
        var exps = reader.readAll(String(StaticFiles.getContent(args.first().value(this))));
        readingProgram = false;

        // Let the user decide whether to load tail-recursively or not:
        currentBeginFunction(exps, env, cc);
    }

    function envWithReturn(env: HValue, called: RefBool) {
        var stackFrameWithReturn = emptyDict();
        stackFrameWithReturn.put("return", Function((args, env, cc) -> {
            called.b = true;
            cc(args.first());
        }, {name:"return"}));
        return env.extend(stackFrameWithReturn);
    }

    function envWithBreakContinue(env: HValue, breakCalled: RefBool, continueCalled: RefBool) {
        var stackFrameWithBreakContinue = emptyDict();
        stackFrameWithBreakContinue.put("continue", Function((_, _, continueCC) -> {
            continueCalled.b = true; continueCC(Nil);
        }, {name:"continue"}));
        stackFrameWithBreakContinue.put("break", Function((_, _, breakCC) -> {
            breakCalled.b = true; breakCC(Nil);
        }, {name: "break"}));
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

        if (returnCalled.b || !truthy(exps.rest_h())) {
            cc(value);
        }
        else {
            trBegin(exps.rest_h(), env, cc);
        }
    }

    function begin(exps: HValue, env: HValue, cc: Continuation) {
        var returnCalled = new RefBool();
        env = envWithReturn(env, returnCalled);

        internalEval(exps.first(), env, (result) -> {
            if (returnCalled.b || !truthy(exps.rest_h())) {
                cc(result);
            }
            else {
                begin(exps.rest_h(), env, cc);
            }
        });
    }

    function specialForm(args: HValue, env: HValue, cc: Continuation) {
        #if traceCallstack
        HaxeTools.println('${CallStack.callStack().length}: ${args.toPrint()}');
        #end
        switch(args.first()) {
            case Macro(func, meta) | SpecialForm(func, meta):
                #if !ignoreWarnings
                if (meta.deprecated) {
                    String('Warning! Macro ${meta.name} is deprecated.').message_hd();
                }
                #end
                func(args.rest_h(), env, cc);
            default: throw '${args.first()} is not a macro or special form';
        }
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
        
        currentEvalAllFunction(args, env, (values) -> {
            // trace(values.toPrint());
            
            switch (values.first()) {
                case Function(func, meta):
                    #if !ignoreWarnings
                    if (meta.deprecated) {
                        String('Warning! Function ${meta.name} is deprecated.').message_hd();
                    }
                    #end
                    func(values.rest_h(), if (callInline) env else emptyEnv(), cc);
                default: throw 'Cannot funcall ${values.first()}';
            }
            
            
        });
    }

    function evalAll(args: HValue, env: HValue, cc: Continuation) {
        if (!truthy(args)) {
            cc(Nil);
        } else {
            internalEval(args.first(), env, (value) -> {
                evalAll(args.rest_h(), env, (value2) -> {
                    cc(value.cons_h(value2));
                });
            });
        }
    }

    function trEvalAll(args: HValue, env: HValue, cc: Continuation) {
        if (!truthy(args)) {
            cc(Nil);
        } else {
            cc(List([for (arg in args.toList()) eval(arg, env)]));
        }
    }

    function quote(args: HValue, env: HValue, cc: Continuation) {
        cc(args.first());
    }

    // TODO move out of CCInterp
    function sleepCC(args: HValue, env: HValue, cc: Continuation) {
        Timer.delay(cc.bind(Nil), Math.round(args.first().toFloat() * 1000));
    }

    // TODO move out of CCInterp
    // This won't work in the repl, I THINK because the main thread is always occupied
    function delay(args: HValue, env: HValue, cc: Continuation) {
        Timer.delay(() -> {
            funcall(false, List([args.first()]), env, noCC);
        }, Math.round(args.second().toFloat() * 1000));
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
                scope.put(args.first().symbolName_h(), val);
                cc(val);
            });
    }

    function setCallable(isMacro: Bool, args: HValue, env: HValue, cc: Continuation) {
        lambda(isMacro, args.rest_h(), env, (fun: HValue) -> {
            set(Global, args.first().cons_h(List([fun])), env, cc);
        }, args.first().symbolName_h());
    }

    function defAlias(args: HValue, env: HValue, cc: Continuation) {
        var func = args.first();
        var alias = args.second();
        var metaSymbols = [for (symbol in args.toList().slice(2)) symbol.symbolName_h()];

        internalEval(func, env, (funcVal) -> {
            var hFunc = funcVal.toCallable();
            var meta = Reflect.copy(metadata(funcVal));

            meta.name = alias.symbolName_h();
            if (metaSymbols.indexOf("@deprecated") != -1) {
                meta.deprecated = true;
            }

            var newFunc = switch (funcVal) {
                case Function(_, _):
                    Function(hFunc, meta);
                case Macro(_, _):
                    Macro(hFunc, meta);
                case SpecialForm(_, _):
                    SpecialForm(hFunc, meta);
                default:
                    throw '';
            };

            globals.put(alias.symbolName_h(), newFunc);
            cc(newFunc);
        });
    }

    function _if(args: HValue, env: HValue, cc: Continuation) {
        if (args.length_h() > 3) {
            error('(if) called with too many arguments. Try wrapping the cases in (begin)');
        }
        internalEval(args.first(), env, (val) -> {
            if (truthy(val)) {
                internalEval(args.second(), env, cc);
            } else if (args.length_h() > 2) {
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
        if (v != null) {
            cc(v);
        } else if (g.exists(name)) {
            cc(g.get(name));
        } else {
            error('$name is undefined');
        };
    }

    function lambda(isMacro: Bool, args: HValue, env: HValue, cc: Continuation, name = "[anonymous lambda]") {
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
            callEnv = callEnv.extend(params.destructuringBind(this, fArgs)); // extending the outer env is how lambdas capture values
            internalEval(Symbol('begin').cons_h(List(body)), callEnv, fCC);
        };
        
        var callable = if (isMacro) {
            Macro(hFun, meta);
        } else {
            Function(hFun, meta);
        };
        cc(callable);
    }

    function metadata(callable: HValue) {
        return HaxeTools.extract(callable, Function(_, meta) | Macro(_, meta) | SpecialForm(_, meta) => meta);
    }

    function docs(func: HValue) {
        return metadata(func).docstring;
    }

    function help() {
        for (name => value in globals.toDict()) {
            try {
                var functionHelp = name.symbolName_h();
                try {
                    var docs = docs(value);
                    if (docs != null && docs.length > 0) {
                        functionHelp += ': $docs';
                    }
                } catch (s: Dynamic) {
                    continue; // Not a callable
                }
                String(functionHelp).message_hd();
            }
        }
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
                internalEval(Symbol("begin").cons_h(body), bodyEnv, innerCC);
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
        var iterable: Iterable<HValue> = it.value(this, true);

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
                    return;
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
            var iterable: Iterable<HValue> = it.value(this, true);
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
        var body = args.rest_h();

        var names = Symbol("recur").cons_h(bindings.alternates(true));
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
                internalEval(Symbol("begin").cons_h(body), env.extend(names.destructuringBind(this, SpecialForm(recur, {name: "recur"}).cons_h(values))), (value) -> {result = value;});
                
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
        cc(Reflect.getProperty(args.first().value(this, true), args.second().toHaxeString()).toHValue());
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
        var callOnReference = if (args.length_h() < 4) {
            false;
        } else {
            truthy(args.nth_h(Int(3)));
        };
        var keepArgsWrapped = if (args.length_h() < 5) {
            Nil;
        } else {
            args.nth_h(Int(4));
        };
        var haxeCallArgs = if (args.length_h() < 3) {
            [];
        } else {
            args.third().unwrapList(this, keepArgsWrapped);
        };

        var caller = args.first().value(this, callOnReference);
        var methodName = args.second().toHaxeString();
        var method = Reflect.getProperty(caller, methodName);

        if (method == null) {
            error('There is no haxe method called $methodName on ${args.first().toPrint()}');
        } else {
            cc(Reflect.callMethod(caller, method, haxeCallArgs).toHValue());
        }
    }

    static var ccNum = 0;
    function callCC(args: HValue, env: HValue, cc: Continuation) {
        var ccId = ccNum++;
        var message = "";
        var functionToCall = null;

        if (args.length_h() > 1) {
            message = eval(args.first(), env).toHaxeString();
            functionToCall = args.second();
        } else {
            functionToCall = args.first();
        }

        // Convert the continuation to a hiss function accepting one argument
        var ccHFunction = Function((innerArgs: HValue, innerEnv: HValue, innerCC: Continuation) -> {
            var arg = if (!truthy(innerArgs)) {
                // It's typical to JUST want to break out of a sequence, not return a value to it.
                Nil;
            } else {
                innerArgs.first();
            };

            #if traceContinuations
            Sys.println('calling $message(cc#$ccId) with ${arg.toPrint()}');
            #end

            cc(arg);
        }, { name: "cc", argNames: ["result"] });

        funcall(true,
            List([
                functionToCall,
                ccHFunction
            ]),
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

    public function readAll(str: String) {
        return reader.readAll(String(str));
    }

    function or(args: HValue, env: HValue, cc: Continuation) {
        for (arg in args.toList()) {
            var argVal = Nil;
            internalEval(arg, env, (val) -> {argVal = val;});
            if (truthy(argVal)) {
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
            if (!truthy(argVal)) {
                cc(Nil);
                return;
            }
        }
        cc(argVal);
    }

    // TODO move out of CCInterp
    function makeDict(args: HValue, env: HValue, cc: Continuation) {
        var dict = new HDict(this);

        var idx = 0;
        while (idx < args.length_h()) {
            var key = args.nth_h(Int(idx));
            var value = args.nth_h(Int(idx+1));
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

    /** Asynchronous-friendly form of eval. NOTE: The args are out of order so this isn't an HFunction. **/
    public function evalCC(arg: HValue, cc: Continuation, ?env: HValue) {
        if (env == null) env = emptyEnv();
        internalEval(arg, env, cc);
    }

    /**
     * Behind the scenes, this function evaluates the truthiness of an HValue.
     * Its behavior can be overridden, but don't do it unless you know what you're getting into.
     **/
    public dynamic function truthy(cond: HValue): Bool {
        return switch (cond) {
            case Nil: false;
            //case Int(i) if (i == 0): false; /* 0 being falsy would be useful for Hank read-counts */
            case List([]): false;
            default: true;
        }
    }

    /** Core form of eval -- continuation-based, takes one expression **/
    private function internalEval(exp: HValue, env: HValue, cc: Continuation) {
        // TODO if there's an error handler, handle exceptions from haxe code through that

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

            case Function(_) | SpecialForm(_) | Macro(_) | T | Nil | Null | Object(_, _):
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
                            inline macroCall(callable.cons_h(exp.rest_h()), env, cc);
                        case SpecialForm(_):
                            inline specialForm(callable.cons_h(exp.rest_h()), env, cc);
                        default: error('Hiss cannot call $callable from ${exp.first().toPrint()}');
                    }
                });
            default:
                error('Cannot evaluate $exp yet');
        }
    }
}

typedef IterateFunction = (collect: Bool, bodyForm: Bool, args: HValue, env: HValue, cc: Continuation) -> Void;
typedef PerformIterationFunction = (operation: HFunction, env: HValue, cc: Continuation) -> Void;