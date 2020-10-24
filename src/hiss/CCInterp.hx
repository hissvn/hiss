package hiss;

import Type;

using Type;

import Reflect;

using Reflect;
using Lambda;

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
import hiss.SpecialForms;
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
using hiss.HTypes.ClassMetaTools;

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
    public var globals:HValue;

    var reader:HissReader;

    var tempTrace:Dynamic = null;
    var readingProgram = false;
    var maxStackDepth = 0;

    var errorHandler:(Dynamic) -> Void = null;

    public function setErrorHandler(handler:(Dynamic) -> Void) {
        errorHandler = handler;
    }

    public function error(message:Dynamic) {
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

    public function importVar(value:Dynamic, name:String) {
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
    // static functions with 'cc' in the metaSignature will be imported as ccfunctions with interp bound as the first argument (NOTE this will need to bypass reflect.callmethod in order to preserve asyncness)
    // static functions with 's' in the metaSignature are special forms (therefore they are also in cc form)
    // TODO functions that convert [type1]To[type2] else will be imported with use conversionInfix instead of To
    // functions with 'i' in the metaSignature will be imported with this interp bound as the first argument
    // functions with 'h' in the metaSignature will keep their args wrapped
    // functions with 'd' for destructive in the metaSignature will use sideEffectSuffix
    //     but also define an alias with a warning
    // functions and properties starting with an underscore will not be imported
    // functions with 'a' in the metaSignature are asynchronous (only makes sense if they are also cc)
    // if a variable exists with the same name as a function but ending in _doc instead of a meta signature,
    //     that variable will be imported as a docstring of the function.
    // if a variable exists with the same name as a function but ending in _args instead of a meta signature,
    //     that variable will be imported as the arg names of the function.
    public function importClass(clazz:Class<Dynamic>, meta:ClassMeta) {
        if (debugClassImports) {
            trace('Import ${meta.name}');
        }
        // TODO this just gives access to the constructor, which isn't always desirable:
        globals.put(meta.name, Object("Class", clazz));

        meta.addDefaultFields();

        function shouldImport(field:String) {
            return !(field.startsWith("_") || field.endsWith("_doc") || field.endsWith("_args"));
        }

        function translateName(field:String, isStatic, isPredicate, destructive, meta) {
            var translatedName = field;
            if (field.contains("_")) {
                translatedName = translatedName.substr(0, translatedName.indexOf("_"));
            }
            if (isPredicate)
                translatedName = translatedName.substr(2); // drop the 'is'
            translatedName = meta.convertNames(translatedName);
            if (isPredicate)
                translatedName += meta.predicateSuffix;
            if (destructive)
                translatedName += meta.sideEffectSuffix;
            if (!isStatic && !meta.omitMemberPrefixes) {
                translatedName = meta.name + ":" + translatedName;
            }
            if (isStatic && !meta.omitStaticPrefixes) {
                translatedName = meta.name + ":" + translatedName;
            }
            return translatedName;
        }

        // Collect all class fields needing to be imported in a map so one for loop imports both static and non-static
        var fieldsToImport:Map<String, Bool> = []; // The bool is true if the field is static

        for (instanceField in clazz.getInstanceFields().filter(shouldImport)) {
            fieldsToImport[instanceField] = false;
        }

        for (classField in clazz.getClassFields().filter(shouldImport)) {
            fieldsToImport[classField] = true;
        }

        var dummyInstance = clazz.createEmptyInstance();

        for (field => isStatic in fieldsToImport) {
            var fieldValue = Reflect.getProperty(isStatic ? clazz : dummyInstance, field);
            switch (Type.typeof(fieldValue)) {
                // Import methods:
                case TFunction:
                    var nameWithoutSignature = field;
                    var metaSignature = "";
                    if (field.contains("_")) {
                        var parts = field.split("_");
                        nameWithoutSignature = parts[0];
                        metaSignature = parts[1];
                    }

                    var bindInterpreter = metaSignature.contains("i");
                    var wrapArgs = if (metaSignature.contains("h")) T else Nil;
                    var destructive = metaSignature.contains("d");
                    var isPredicate = (field.toLowerHyphen().split("-")[0] == "is");
                    var specialForm = metaSignature.contains("s");
                    var ccFunction = !specialForm && metaSignature.contains("cc");
                    var isAsync = metaSignature.contains("a");
                    
                    if (!ccFunction && isAsync) {
                        throw '$field in ${meta.name} must be a ccfunction to be declared async';
                    }

                    if ((specialForm || ccFunction) && !isStatic) {
                        throw '$field in ${meta.name} must be static to be a special form or ccfunction';
                    }

                    var translatedName = translateName(field, isStatic, isPredicate, destructive, meta);

                    if (debugClassImports) {
                        trace(translatedName);
                    }

                    var functionMeta:CallableMeta = { name: translatedName };

                    if (Reflect.hasField(clazz, '${nameWithoutSignature}_doc')) {
                        functionMeta.docstring = Reflect.getProperty(clazz, '${nameWithoutSignature}_doc');
                    }

                    if (Reflect.hasField(clazz, '${nameWithoutSignature}_args')) {
                        functionMeta.argNames = Reflect.getProperty(clazz, '${nameWithoutSignature}_args');
                    }

                    if (ccFunction) {
                        importCCFunction((args, env, cc) -> {
                            fieldValue(this, args, env, cc);
                        }, functionMeta);
                    } else if (specialForm) {
                        importSpecialForm((args, env, cc) -> {
                            fieldValue(this, args, env, cc);
                        }, functionMeta);
                    } else {
                        globals.put(translatedName, Function((args, env, cc) -> {
                            var callObject:Dynamic = clazz;
                            if (!isStatic) {
                                callObject = args.first().value(this);
                                args = args.rest_h();
                            }
                            var argArray = args.unwrapList(this, wrapArgs);

                            if (bindInterpreter) {
                                argArray.insert(0, this);
                            }
                            // We need an empty instance for checking the types of the properties.
                            // BUT if we get our function pointers from the empty instance, the C++ target
                            // will segfault when we try to call them, so getProperty has to be called every time
                            var funcPointer = Reflect.getProperty(callObject, field);

                            var returnValue:Dynamic = Reflect.callMethod(callObject, funcPointer, argArray);
                            cc(returnValue.toHValue());
                        }, functionMeta));
                    }
                    if (destructive) {
                        defDestructiveAlias(translatedName, meta.sideEffectSuffix);
                    }
                // Import properties
                default:
                    // TODO every property currently gets a getter and a setter no matter what.
                    // Private properties are imported and therefore made public unless they start with _.
                    var getterTranslatedName = meta.convertNames(field);
                    getterTranslatedName = meta.getterPrefix + getterTranslatedName;
                    if (!meta.omitMemberPrefixes) {
                        getterTranslatedName = meta.name + ":" + getterTranslatedName;
                    }
                    if (debugClassImports) {
                        trace(getterTranslatedName);
                    }
                    globals.put(getterTranslatedName, Function((args, env, cc) -> {
                        var callObject:Dynamic = clazz;
                        if (!isStatic) {
                            callObject = args.first().value(this);
                        }
                        var value:Dynamic = Reflect.getProperty(callObject, field);
                        cc(value.toHValue());
                    }, {name: getterTranslatedName}));

                    var setterTranslatedName = meta.convertNames(field);
                    setterTranslatedName = meta.setterPrefix + setterTranslatedName + meta.sideEffectSuffix;
                    if (!meta.omitMemberPrefixes) {
                        setterTranslatedName = meta.name + ":" + setterTranslatedName;
                    }
                    if (debugClassImports) {
                        trace(setterTranslatedName);
                    }
                    globals.put(setterTranslatedName, Function((args, env, cc) -> {
                        var callObject:Dynamic = clazz;
                        if (!isStatic) {
                            callObject = args.first().value(this);
                            args = args.rest_h();
                        }
                        var value = args.first().value(this);
                        Reflect.setProperty(callObject, field, value);
                        cc(args.second());
                    }, {name: setterTranslatedName}));
                    // It can be confusing to forget the ! when trying to use a setter, so allow usage without ! but with a warning:
                    defDestructiveAlias(setterTranslatedName, meta.sideEffectSuffix);
            }
        }
    }

    public function importFunction(instance:Dynamic, func:Function, meta:CallableMeta, keepArgsWrapped:HValue = Nil) {
        globals.put(meta.name, Function((args, env, cc) -> {
            cc(Reflect.callMethod(instance, func, args.unwrapList(this, keepArgsWrapped)).toHValue());
        }, meta));
    }

    public function importCCFunction(func:HFunction, meta:CallableMeta) {
        globals.put(meta.name, Function(func, meta));
    }

    public function importSpecialForm(func:HFunction, meta:CallableMeta) {
        globals.put(meta.name, SpecialForm(func, meta));
    }

    // TODO this is like register-method but never used.
    function importMethod(method:String, meta:CallableMeta, callOnReference:Bool, keepArgsWrapped:HValue, returnInstance:Bool) {
        globals.put(meta.name, Function((args, env, cc) -> {
            var instance = args.first().value(this, callOnReference);
            cc(instance.callMethod(instance.getProperty(method), args.rest_h().unwrapList(this, keepArgsWrapped)).toHValue());
        }, meta));
    }

    public static function noOp(args:HValue, env:HValue, cc:Continuation) {}

    public static function noCC(arg:HValue) {}

    var currentBeginFunction:HFunction = null;
    var currentEvalAllFunction:HFunction = null;

    static function emptyList() {
        return List([]);
    }

    public function emptyDict() {
        return Dict(new HDict(this));
    }

    public function emptyEnv() {
        return List([emptyDict()]);
    }

    // TODO declutter the constructor by refactoring to allow importObject(this)
    public function new(?printFunction:(Dynamic) -> Dynamic) {
        HissTestCase.reallyTrace = Log.trace;

        globals = emptyDict();
        reader = new HissReader(this);

        // convention: functions with side effects end with ! unless they start with def

        // When not a repl, use Sys.exit for quitting
        #if (sys || hxnodejs)
        importFunction(Sys, Sys.exit.bind(0), {name: "quit!", argNames: []});
        #end

        // These functions make sense for living in CCInterp because they access internal state directly:
        importSpecialForm(set.bind(Global), {name: "defvar"});
        importSpecialForm(set.bind(Local), {name: "setlocal!"});
        importSpecialForm(set.bind(Destructive), {name: "set!"});
        importSpecialForm(setCallable.bind(false), {name: "defun"});
        importSpecialForm(setCallable.bind(true), {name: "defmacro"});
        importSpecialForm(defAlias, {name: "defalias"});
        importSpecialForm(_eval, {name: "eval"});
        importSpecialForm(funcall.bind(false), {name: "funcall"});
        importSpecialForm(funcall.bind(true), {name: "funcall-inline"});
        // Use tail-recursive begin and iterate by default:
        useFunctions(trBegin, trEvalAll, iterate);

        // Allow switching at runtime:
        importFunction(this, useFunctions.bind(trBegin, trEvalAll, iterate), {name: "disable-cc!"});
        importFunction(this, useFunctions.bind(begin, evalAll, iterateCC), {name: "enable-cc!"});

        // Error handling
        importFunction(this, error, {name: "error!", argNames: ["message"]}, Nil);
        importSpecialForm(throwsError, {name: "error?"});
        importSpecialForm(hissTry, {name: "try"});

        // Running as a repl
        importFunction(this, repl, {name: "repl"});

        importFunction(this, read, {name: "read", argNames: ["string"]}, Nil);
        importFunction(this, readAll, {name: "read-all", argNames: ["string"]}, Nil);

        importClass(HStream, {name: "HStream"});
        importFunction(reader, reader.setMacroString, {name: "set-macro-string!", argNames: ["string", "read-function"]}, List([Int(1)]));
        importFunction(reader, reader.setDefaultReadFunction, {name: "set-default-read-function!", argNames: ["read-function"]}, T);
        importFunction(reader, reader.readNumber, {name: "read-number!", argNames: ["start", "stream"]}, Nil);
        importFunction(reader, reader.readString, {name: "read-string!", argNames: ["start", "stream"]}, Nil);
        importFunction(reader, reader.readSymbol, {name: "read-symbol!", argNames: ["start", "stream"]}, Nil);
        importFunction(reader, reader.nextToken, {name: "next-token!", argNames: ["stream"]}, Nil);
        importFunction(reader, reader.readDelimitedList, {
            name: "read-delimited-list!",
            argNames: [
                "terminator",
                "delimiters",
                "eof-terminates",
                "blank-elements",
                "start",
                "stream"
            ]
        }, List([Int(3)]) /* keep blankElements wrapped */);
        importFunction(reader, reader.copyReadtable, {name: "copy-readtable"});
        importFunction(reader, reader.useReadtable, {name: "use-readtable!"});
        importFunction(reader, reader.read, {name: "read-next!", argNames: ["start", "stream"]});
        defDestructiveAlias("read-number!", "!");
        defDestructiveAlias("read-string!", "!");
        defDestructiveAlias("read-symbol!", "!");
        defDestructiveAlias("read-delimited-list!", "!");
        defDestructiveAlias("read-next!", "!");

        importClass(Stdlib, {name: "Stdlib", omitStaticPrefixes: true});

        // Sometimes it's useful to provide the interpreter with your own target-native print function
        // so they will be used while the standard library is being loaded.
        if (printFunction != null) {
            importFunction(this, printFunction, {name: "print!", argNames: ["value"]}, Nil);
        }

        importClass(VariadicFunctions, {name: "VariadicFunctions", omitStaticPrefixes: true});

        // Open Pandora's box if it's available:
        #if target.threaded
        importClass(HDeque, {name: "Deque"});
        importClass(HLock, {name: "Lock"});
        importClass(HMutex, {name: "Mutex"});
        importClass(HThread, {name: "Thread"});
        // importClass(Threading.Tls, "Tls");
        #end

        // Dictionaries
        importClass(HDict, {
            name: "Dict",
            omitMemberPrefixes: true,
            omitStaticPrefixes: true,
            convertNames: (name) -> {
                return "dict-" + name.toLowerHyphen();
            }
        });

        #if (sys || hxnodejs)
        importClass(HFile, {name: "File"});
        #end

        // command-line args
        importFunction(this, () -> List(scriptArgs), {name: "args"});

        // String functions:
        importClass(HStringTools, {name: "StringTools", omitStaticPrefixes: true});

        importClass(HHttp, {name: "Http"});
        // Alias HTTP so capitalization typos don't get annoying:
        importClass(HHttp, {name: "HTTP"});

        importClass(HDate, {name: "Date"});

        importClass(HType, {name: "Type"});

        importCCFunction(_load, {name: "load!", argNames: ["file"]});

        // First-class unit testing:
        importSpecialForm(HissTestCase.testAtRuntime.bind(this), {name: "test!"});
        importCCFunction(HissTestCase.hissPrints.bind(this), {name: "prints"});

        // Operating system
        importFunction(StaticFiles, StaticFiles.getContent, {name: "get-content", argNames: ["file"]});

        importClass(SpecialForms, {name: "SpecialForms", omitStaticPrefixes: true});

        importSpecialForm(loop, {name: "loop"});

        // TODO These functions do not use interp state, and could be defined in another class with the 's' meta
        importFunction(this, () -> new HDict(this), {name: "empty-readtable"});

        // TODO these classes should be wrapped and imported whole:
        // Std
        importFunction(Std, Std.random, {name: "random"});
        importFunction(Std, Std.parseInt, {name: "int"});
        importFunction(Std, Std.parseFloat, {name: "float"});

        #if (sys || hxnodejs)
        importFunction(Sys, Sys.sleep, {name: "sleep!", argNames: ["seconds"]});
        importFunction(Sys, Sys.getEnv, {name: "get-env", argNames: ["var"]});
        #end

        StaticFiles.compileWith("Stdlib.hiss");

        // disableTrace();
        load("Stdlib.hiss");
        // enableTrace();
    }

    // error? will have an implicit begin
    function throwsError(args:HValue, env:HValue, cc:Continuation) {
        try {
            internalEval(Symbol("begin").cons_h(args), env, (val) -> {
                cc(Nil); // If the continuation is called, there is no error
            });
        } catch (err:Dynamic) {
            cc(T);
        }
    }

    function hissTry(args:HValue, env:HValue, cc:Continuation) {
        try {
            // Try cannot have an implicit begin because the second argument is the catch
            internalEval(args.first(), env, cc);
        } catch (sig:HSignal) {
            throw sig;
        } catch (err:Dynamic) {
            // TODO let the catch access the error message
            if (args.length_h() > 1) {
                internalEval(args.second(), env, cc);
            } else {
                cc(Nil);
            }
        }
    }

    // TODO make public enableCC() and disableCC()
    function useFunctions(beginFunction:HFunction, evalAllFunction:HFunction, iterateFunction:IterateFunction) {
        currentBeginFunction = beginFunction;
        currentEvalAllFunction = evalAllFunction;
        globals.put("begin", SpecialForm(beginFunction, {name: "begin"}));
        importSpecialForm(iterateFunction.bind(true, true), {name: "for"});
        importSpecialForm(iterateFunction.bind(false, true), {name: "do-for"});
        importSpecialForm(iterateFunction.bind(true, false), {name: "map"});
        importSpecialForm(iterateFunction.bind(false, false), {name: "do-map"});
        return Nil;
    }

    /** Run a Hiss REPL from this interpreter instance **/
    public function repl(useConsoleReader = true) {
        StaticFiles.compileWith("ReplLib.hiss");
        load("ReplLib.hiss");

        var history = [];
        importFunction(this, () -> history, {name: "history"});
        importFunction(this, (str) -> history[history.length - 1] = str, {name: "rewrite-history"});
        #if (sys || hxnodejs)
        var historyFile = Path.join([Stdlib.homeDir(), ".hisstory"]);
        history = sys.io.File.getContent(historyFile).split("\n");

        var cReader = null;
        if (useConsoleReader)
            cReader = new ConsoleReader(-1, historyFile);
        // The REPL needs to make sure its ConsoleReader actually saves the history on exit, so quit() is provided here
        // differently than the version in Stdlib.hiss :)
        importFunction(this, () -> {
            if (useConsoleReader) {
                cReader.saveHistory();
            }
            throw HSignal.Quit;
        }, {name: "quit!"});
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

            // interp.disableTrace();
            var exp = null;
            try {
                exp = read(next);
            } catch (err:Dynamic) {
                HaxeTools.println('Reader error: $err');
                continue;
            }
            // interp.enableTrace();

            try {
                internalEval(exp, locals, Stdlib.print_hd);
            } catch (e:HSignal) {
                switch (e) {
                    case Quit:
                        return;
                }
            }
            // TODO Errors from async functions won't be caught by the try, so they throw their errors via error().
            // So this should use errorHandler instead of try-catch
            #if (!throwErrors)
            catch (s:String) {
                HaxeTools.println('Error "$s" from `${exp.toPrint_h()}`');
                HaxeTools.println('Callstack depth ${CallStack.callStack().length}');
            } catch (err:Dynamic) {
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

    var scriptArgs:HList = [];

    public static function run(interp:CCInterp, ?args:Array<String>) {
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

    public function load(file:String) {
        _load(List([String(file)]), emptyEnv(), noCC);
    }

    function _load(args:HValue, env:HValue, cc:Continuation) {
        readingProgram = true;
        var exps = reader.readAll(String(StaticFiles.getContent(args.first().value(this))));
        readingProgram = false;

        // Let the user decide whether to load tail-recursively or not:
        currentBeginFunction(exps, env, cc);
    }

    function envWithReturn(env:HValue, called:RefBool) {
        var stackFrameWithReturn = emptyDict();
        stackFrameWithReturn.put("return", Function((args, env, cc) -> {
            called.b = true;
            cc(args.first());
        }, {name: "return"}));
        return env.extend(stackFrameWithReturn);
    }

    function envWithBreakContinue(env:HValue, breakCalled:RefBool, continueCalled:RefBool) {
        var stackFrameWithBreakContinue = emptyDict();
        stackFrameWithBreakContinue.put("continue", Function((_, _, continueCC) -> {
            continueCalled.b = true;
            continueCC(Nil);
        }, {name: "continue"}));
        stackFrameWithBreakContinue.put("break", Function((_, _, breakCC) -> {
            breakCalled.b = true;
            breakCC(Nil);
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
    function trBegin(exps:HValue, env:HValue, cc:Continuation) {
        var returnCalled = new RefBool();
        env = envWithReturn(env, returnCalled);
        var value = eval(exps.first(), env);

        if (returnCalled.b || !truthy(exps.rest_h())) {
            cc(value);
        } else {
            trBegin(exps.rest_h(), env, cc);
        }
    }

    function begin(exps:HValue, env:HValue, cc:Continuation) {
        var returnCalled = new RefBool();
        env = envWithReturn(env, returnCalled);

        internalEval(exps.first(), env, (result) -> {
            if (returnCalled.b || !truthy(exps.rest_h())) {
                cc(result);
            } else {
                begin(exps.rest_h(), env, cc);
            }
        });
    }

    function specialForm(args:HValue, env:HValue, cc:Continuation) {
        #if traceCallstack
        HaxeTools.println('${CallStack.callStack().length}: ${args.toPrint()}');
        #end
        switch (args.first()) {
            case Macro(func, meta) | SpecialForm(func, meta):
                #if !ignoreWarnings
                if (meta.deprecated) {
                    String('Warning! Macro ${meta.name} is deprecated.').message_hd();
                }
                #end
                func(args.rest_h(), env, cc);
            default:
                throw '${args.first()} is not a macro or special form';
        }
    }

    function macroCall(args:HValue, env:HValue, cc:Continuation) {
        specialForm(args, env, (expansion:HValue) -> {
            #if traceMacros
            HaxeTools.println('${args.toPrint()} -> ${expansion.toPrint()}');
            #end
            internalEval(expansion, env, cc);
        });
    }

    function funcall(callInline:Bool, args:HValue, env:HValue, cc:Continuation) {
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

    function evalAll(args:HValue, env:HValue, cc:Continuation) {
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

    function trEvalAll(args:HValue, env:HValue, cc:Continuation) {
        if (!truthy(args)) {
            cc(Nil);
        } else {
            cc(List([for (arg in args.toList()) eval(arg, env)]));
        }
    }

    function set(type:SetType, args:HValue, env:HValue, cc:Continuation) {
        internalEval(args.second(), env, (val) -> {
            var scope = null;
            switch (type) {
                case Global:
                    scope = globals;
                case Local:
                    scope = env.first();
                case Destructive:
                    for (frame in env.toList()) {
                        var frameDict = frame.toDict();
                        if (frameDict.exists_h(args.first())) {
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

    function setCallable(isMacro:Bool, args:HValue, env:HValue, cc:Continuation) {
        SpecialForms.lambda_s(this, args.rest_h(), env, (fun : HValue) -> {
            set(Global, args.first().cons_h(List([fun])), env, cc);
        }, args.first().symbolName_h(), isMacro);
    }

    function defAlias(args:HValue, env:HValue, cc:Continuation) {
        var func = args.first();
        var alias = args.second();
        var metaSymbols = [for (symbol in args.toList().slice(2)) symbol.symbolName_h()];

        internalEval(func, env, (funcVal) -> {
            var hFunc = funcVal.toCallable();
            var meta = Reflect.copy(funcVal.metadata());

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

    /**
        The Hiss convention is for functions with side effects to end with "!".
        It can be nice to have things work without the !, but with a warning.
    **/
    public function defDestructiveAlias(destructiveName:String, suffix:String) {
        // trace(destructiveName);
        // trace(suffix);
        defAlias(List([
            Symbol(destructiveName),
            Symbol(destructiveName.substr(0, destructiveName.length - suffix.length)),
            Symbol("@deprecated")
        ]), emptyEnv(), noCC);
    }

    function getVar(name:HValue, env:HValue, cc:Continuation) {
        // Env is a list of dictionaries -- stack frames
        var stackFrames = env.toList();

        var g = globals.toDict();

        var v = null;
        for (frame in stackFrames) {
            var frameDict = frame.toDict();
            if (frameDict.exists_h(name)) {
                v = frameDict.get_h(name);
                break;
            }
        }
        if (v != null) {
            cc(v);
        } else if (g.exists_h(name)) {
            cc(g.get_h(name));
        } else {
            error('$name is undefined');
        };
    }

    // Helper function to get the iterable object in iterate() and iterateCC()
    function iterable(bodyForm:Bool, args:HValue, env:HValue, cc:Continuation) {
        internalEval(if (bodyForm) {
            args.second();
        } else {
            args.first();
        }, env, cc);
    }

    function performIteration(bodyForm:Bool, args:HValue, env:HValue, cc:Continuation, performFunction:PerformIterationFunction) {
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
    function iterate(collect:Bool, bodyForm:Bool, args:HValue, env:HValue, cc:Continuation) {
        var it:HValue = Nil;
        iterable(bodyForm, args, env, (_iterable) -> {
            it = _iterable;
        });
        var iterable:Iterable<HValue> = it.value(this, true);

        function synchronousIteration(operation:HFunction, innerEnv:HValue, outerCC:Continuation) {
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
                if (breakCalled.b)
                    break;
            }

            outerCC(List(results));
        }

        performIteration(bodyForm, args, env, cc, synchronousIteration);
    }

    /**
        Continuation-based (and therefore dangerous!) implementation
    **/
    function iterateCC(collect:Bool, bodyForm:Bool, args:HValue, env:HValue, cc:Continuation) {
        iterable(bodyForm, args, env, (it) -> {
            var iterable:Iterable<HValue> = it.value(this, true);
            var iterator = iterable.iterator();

            var results = [];
            var continueCalled = new RefBool();
            var breakCalled = new RefBool();

            env = envWithBreakContinue(env, breakCalled, continueCalled);

            function asynchronousIteration(operation:HFunction, innerEnv:HValue, outerCC:Continuation) {
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
    function loop(args:HValue, env:HValue, cc:Continuation) {
        var bindings = args.first();
        var body = args.rest_h();

        var names = Symbol("recur").cons_h(bindings.alternates(true));
        var firstValueExps = bindings.alternates(false);
        currentEvalAllFunction(firstValueExps, env, (firstValues) -> {
            var nextValues = Nil;
            var recurCalled = false;
            var recur:HFunction = (nextValueExps, env, cc) -> {
                currentEvalAllFunction(nextValueExps, env, (nextVals) -> {
                    nextValues = nextVals;
                });
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
                internalEval(Symbol("begin").cons_h(body), env.extend(names.destructuringBind(this, SpecialForm(recur, {name: "recur"}).cons_h(values))),
                    (value) -> {
                        result = value;
                    });
            } while (recurCalled);
            cc(result);
        });
    }

    // This breaks continuation-based signature rules because I just want it to work.
    public function evalUnquotes(expr:HValue, env:HValue):HValue {
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
                internalEval(h, env, (v) -> {
                    val = v;
                });
                return val;
            case Quasiquote(exp):
                return evalUnquotes(exp, env);
            default:
                return expr;
        };
    }

    public function read(str:String) {
        return reader.read("", HStream.FromString(str));
    }

    public function readAll(str:String) {
        return reader.readAll(String(str));
    }

    /** Hiss-callable form for eval **/
    function _eval(args:HValue, env:HValue, cc:Continuation) {
        internalEval(args.first(), env, (val) -> {
            internalEval(val, env, cc);
        });
    }

    /** Public, synchronous form of eval. Won't work with javascript asynchronous functions **/
    public function eval(arg:HValue, ?env:HValue) {
        var value = null;
        if (env == null)
            env = emptyEnv();
        internalEval(arg, env, (_value) -> {
            value = _value;
        });
        return value;
    }

    /** Asynchronous-friendly form of eval. NOTE: The args are out of order so this isn't an HFunction. **/
    public function evalCC(arg:HValue, cc:Continuation, ?env:HValue) {
        if (env == null)
            env = emptyEnv();
        internalEval(arg, env, cc);
    }

    /**
     * Behind the scenes, this function evaluates the truthiness of an HValue.
     * Its behavior can be overridden, but don't do it unless you know what you're getting into.
    **/
    public dynamic function truthy(cond:HValue):Bool {
        return switch (cond) {
            case Nil: false;
            // case Int(i) if (i == 0): false; /* 0 being falsy would be useful for Hank read-counts */
            case List([]): false;
            default: true;
        }
    }

    // Handle expression interpolation in Hiss strings
    function interpolateString(raw:String, env:HValue, cc:Continuation, startingIndex = 0) {
        var nextExpressionIndex = raw.indexOf("$", startingIndex);

        if (nextExpressionIndex == -1) {
            cc(String(raw));
        } else if (raw.charAt(nextExpressionIndex - 1) == '\\') {
            // Allow \$ for putting $ in string.
            interpolateString(raw.substr(0, nextExpressionIndex - 1) + raw.substr(nextExpressionIndex), env, cc, nextExpressionIndex + 1);
        } else {
            var expStream = HStream.FromString(raw.substr(nextExpressionIndex + 1));

            // Allow ${name} so a space isn't required to terminate the symbol
            var exp = null;
            var expLength = -1;
            if (expStream.peek(1) == "{") {
                expStream.drop_d("{");
                var braceContents = HaxeTools.extract(expStream.takeUntil_d(['}'], false, false, true), Some(o) => o).output;
                expStream = HStream.FromString(braceContents);
                expLength = 2 + expStream.length();
                exp = reader.read("", expStream);
            } else {
                var startingLength = expStream.length();
                exp = reader.read("", expStream);
                expLength = startingLength - expStream.length();
            }
            internalEval(exp, env, (val) -> {
                interpolateString(raw.substr(0, nextExpressionIndex) + val.toMessage() + raw.substr(nextExpressionIndex + 1 + expLength), env, cc, nextExpressionIndex + 1 + val.toMessage().length);
            });
        }
    }

    /** Core form of eval -- continuation-based, takes one expression **/
    private function internalEval(exp:HValue, env:HValue, cc:Continuation) {
        // TODO if there's an error handler, handle exceptions from haxe code through that

        switch (exp) {
            case Symbol(_):
                inline getVar(exp, env, cc);
            case Int(_) | Float(_) | String(_):
                cc(exp);
            case InterpString(raw):
                interpolateString(raw, env, cc);
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

                internalEval(exp.first(), env, (callable:HValue) -> {
                    switch (callable) {
                        case Function(_):
                            inline funcall(false, exp, env, cc);
                        case Macro(_):
                            // HaxeTools.print('macroexpanding ${exp.toPrint()} -> ');
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

typedef IterateFunction = (collect:Bool, bodyForm:Bool, args:HValue, env:HValue, cc:Continuation) -> Void;
typedef PerformIterationFunction = (operation:HFunction, env:HValue, cc:Continuation) -> Void;
