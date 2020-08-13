package hiss;

import haxe.CallStack;

import hiss.HaxeTools;
using hiss.HaxeTools;
import hiss.HTypes;
import hiss.CompileInfo;
import Type;
import haxe.io.Path;
import uuid.Uuid;
import Reflect;
using hiss.HissTools;

class HissTools {

    // The version macro can't be passed directly as a function object.
    // It has to be wrapped in a regular function.
    public static function version() {
        return String(CompileInfo.version());
    }

    public static function homeDir() {
        #if (sys || hxnodejs)
            var path = Sys.getEnv(if (Sys.systemName() == "Windows") "UserProfile" else "HOME");
            return if (path != null) Path.normalize(path) else "";
        #else
            throw "Can't get home directory on this target.";
        #end
    }

    public static function get(dict: HValue, key: String) {
        return dict.toDict()[key];
    }

    public static function exists(dict: HValue, key: String) {
        return dict.toDict().exists(key);
    }

    public static function put(dict: HValue, key: String, v: HValue) {
        dict.toDict()[key] = v;
    }

    public static function toList(list: HValue, hint: String = "list"): HList {
        return HaxeTools.extract(list, List(l) => l, "list");
    }

    public static function toObject(obj: HValue, ?hint: String = "object"): Dynamic {
        return HaxeTools.extract(obj, Object(_, o) => o, "object");
    }

    public static function toCallable(f: HValue, hint: String = "function"): HFunction {
        return HaxeTools.extract(f, Function(hf, _) | Macro(hf, _) | SpecialForm(hf, _) => hf, hint);
    }

    public static function toHaxeString(hv: HValue): String {
        return HaxeTools.extract(hv, String(s) => s, "string");
    }

    public static function toInt(v: HValue): Int {
        return HaxeTools.extract(v, Int(i) => i, "int");
    }

    public static function toFloat(v: HValue): Float {
        return HaxeTools.extract(v, Float(f) => f, "float");
    }

    public static function toHFunction(hv: HValue): HFunction {
        return HaxeTools.extract(hv, Function(f, _) => f, "function");
    }

    public static function toDict(dict: HValue): HDict {
        return HaxeTools.extract(dict, Dict(h) => h, "dict");
    }

    public static function first(list: HValue): HValue {
        return list.toList()[0];
    }

    public static function second(list: HValue): HValue {
        return list.toList()[1];
    }

    public static function third(list: HValue): HValue {
        return list.toList()[2];
    }

    public static function fourth(list: HValue): HValue {
        return list.toList()[3];
    }

    public static function rest(list: HValue): HValue {
        return List(list.toList().slice(1));
    }

    public static function sort(list: Array<Dynamic>, ?fun: (Dynamic, Dynamic) -> Int) {
        if (fun == null) fun = Reflect.compare;
        var sorted = list.copy();
        sorted.sort(fun);
        return sorted;
    }

    public static function alternates(list: HValue, start: Bool) {
        var result = new Array<HValue>();
        var l = list.toList().copy();
        while (l.length > 0) {
            var next = l.shift();
            if (start) result.push(next);
            start = !start;
        }
        return List(result);
    }

    // Can't be ported to Hiss the Haxe reflection API doesn't allow array indexing
    public static function nth(list: HValue, idx: HValue):HValue {
        return list.toList()[idx.toInt()];
    }

    public static function setNth(arr: HValue, idx: HValue, val: HValue) { 
        arr.toList()[idx.toInt()] = val; return arr;
    }

    public static function symbolName(v: HValue): String {
        return HaxeTools.extract(v, Symbol(name) => name, "symbol name");
    }

    public static function symbol(?v: HValue): HValue {
        // When called with no arguments, (symbol) acts like common-lisp's (gensym)
        if (v == null) {
            return Symbol('_${Uuid.v4()}');
        }
        return Symbol(v.toHaxeString());
    }

    public static function range(a: Dynamic, ?b: Dynamic) {
        var start = if (b == null) 0 else a;
        var end = if (b == null) a else b;

        var intIterator = start ... end;

        // Haxe IntIterators are weird. What we really want is an Iterable of HValues,
        // whose iterator()'s next() and hasNext() are not inlined.
        return {
            iterator: function () {
                return {
                    next: function() {
                        return intIterator.next().toHValue();
                    },
                    hasNext: function() {
                        return intIterator.hasNext();
                    }
                };
            }
        };
    }

    /**
        Return the first argument HDict extended with the keys and values of the second.
    **/
    public static function dictExtend(dict: HValue, extension: HValue) {
        var extended = dict.toDict().copy();
        for (pair in extension.toDict().keyValueIterator()) {
            extended.set(pair.key, pair.value);
        }
        return Dict(extended);
    }    

    public static function extend(env: HValue, extension: HValue) {
        return cons(extension, env);
    }

    public static function destructuringBind(names: HValue, values: HValue) {
        var bindings = Dict([]);

        switch (names) {
            case Symbol(name):
                // Destructuring bind is still valid with a one-value binding
                bindings.put(name, values);
            case List(l1):

                var l2 = values.toList();

                /*if (l1.length != l2.length) {
                    throw 'Cannot bind ${l2.length} values to ${l1.length} names';
                }*/

                for (idx in 0...l1.length) {
                    switch (l1[idx]) {
                        case List(nestedList):
                            bindings = bindings.dictExtend(destructuringBind(l1[idx], l2[idx]));
                        case Symbol("&optional"):
                            var numOptionalValues = l1.length - idx - 1;
                            var remainingValues = l2.slice(idx);
                            while (remainingValues.length < numOptionalValues) {
                                remainingValues.push(Nil);
                            }
                            bindings = bindings.dictExtend(destructuringBind(List(l1.slice(idx+1)), List(remainingValues)));
                            break;
                        case Symbol("&rest"):
                            var remainingValues = l2.slice(idx);
                            bindings.put(l1[idx+1].symbolName(), List(remainingValues));
                            break;
                        case Symbol(name):
                            bindings.put(name, l2[idx]);
                        default:
                            throw 'Bad element ${l1[idx]} in name list for bindings';
                    }

                }
            default:
                throw 'Cannot perform destructuring bind on ${names.toPrint()} and ${values.toPrint()}';
        }

        return bindings;
    }

    // Since the variadic binop macro uses cons and it's one of the first
    // things in the Hiss prelude, might as well let this one stand as a Haxe function.
    public static function cons(hv: HValue, hl: HValue): HValue {
        if (!hl.truthy()) return List([hv]);
        var l = hl.toList().copy();
        l.insert(0, hv);
        return List(l);
    }

    // This one can't be pure Hiss because we can't instantiate a Map with a type parameter using reflection:
    static function emptyDict() {
        return Dict([]);
    }

    public static function eq(a: HValue, b: HValue): HValue {
        if (Type.enumIndex(a) != Type.enumIndex(b)) {
            return Nil;
        }
        switch (a) {
            case Int(_) | String(_) | Symbol(_) | Float(_)  | T | Nil:
                return if (Type.enumEq(a, b)) T else Nil;
            case List(_):
                var l1 = a.toList();
                var l2 = b.toList();
                if (l1.length != l2.length) return Nil;
                var i = 0;
                while (i < l1.length) {
                    if (!HissTools.truthy(eq(l1[i], l2[i]))) return Nil;
                    i++;
                }
                return T;
            case Quote(aa) | Quasiquote(aa) | Unquote(aa) | UnquoteList(aa):
                var bb = HaxeTools.extract(b, Quote(e) | Quasiquote(e) | Unquote(e) | UnquoteList(e) => e);
                return eq(aa, bb);
            case SpecialForm(fun, _):
                return switch (b) {
                    case SpecialForm(fun2, _) if (fun == fun2): T;
                    default: Nil;
                };
            default:
                throw 'eq is not implemented for $a and $b';
        }
    }

    public static function not(v: HValue) {
        return if (v.truthy()) Nil else T;
    }

    static var recursivePrintDepth = 100;
    static var maxObjectRepLength = 50;

    // Convert values to strings for user consumption
    public static function toMessage(v: HValue) {
        return switch (v) {
            case String(s): s;
            default: toPrint(v);
        }
    }

    // Convert values to strings for REPL printing
    public static function toPrint(v: HValue, recursiveCall: Int = 0): String {
        return switch (v) {
            case Int(i):
                Std.string(i);
            case Float(f):
                Std.string(f);
            case Symbol(name):
                name;
            case String(str) | InterpString(str):
                '"$str"';
            case List(l):
                if (recursiveCall > recursivePrintDepth) {
                    "STACK OVERFLOW DANGER";
                } else {
                    var valueStr = "";
                    for (v in l) {
                        valueStr += v.toPrint(recursiveCall+1) + ' ';
                    }
                    valueStr = valueStr.substr(0, valueStr.length - 1); // no trailing space
                    '(${valueStr})';
                };
            case Quote(e):
                "'" + e.toPrint(recursiveCall+1);
            case Object(t, o):
                '[$t: ${Std.string(o)}]';
            case Function(_, name, args):
                '$name($args)';
            case Macro(_, name):
                '$name';
            case SpecialForm(_, name):
                '$name';
            case Nil:
                'nil';
            case T:
                't';
            case Dict(hdict):
                if (recursiveCall > recursivePrintDepth) {
                    "STACK OVERFLOW DANGER";
                } else {
                    '${[for (k => v in hdict) '$k => ${v.toPrint(recursiveCall+1)}, ']}';
                }
            case Quasiquote(e):
                return '`${e.toPrint(recursiveCall+1)}';
            case Unquote(e):
                return ',${e.toPrint(recursiveCall+1)}';
            case UnquoteList(e):
                return ',@${e.toPrint(recursiveCall+1)}';
            default:
                throw 'Not clear why $v is being converted to string';
        }
    }

    public static function print(exp: HValue) {
        HaxeTools.println(exp.toPrint());
        return exp;
    }

    public static function message(exp: HValue) {
        HaxeTools.println(exp.toMessage());
        return exp;
    }

    public static function toHValue(v: Dynamic, hint:String = "HValue"): HValue {
        if (v == null) return Nil;
        var t = Type.typeof(v);
        return switch (t) {
            case TInt:
                Int(v);
            case TFloat:
                Float(v);
            case TBool:
                if (v) T else Nil;
            case TClass(c):
                var name = Type.getClassName(c);
                return switch (name) {
                    case "String":
                        String(v);
                    case "Array":
                        var va = cast(v, Array<Dynamic>);
                        List([for (e in va) HissTools.toHValue(e)]);
                    default:
                        Object(name, v);
                };
            case TEnum(e):
                var name = Type.getEnumName(e);
                switch (name) {
                    case "haxe.ds.Option":
                        return switch (cast(v, haxe.ds.Option<Dynamic>)) {
                            case Some(vInner): HissTools.toHValue(vInner);
                            case None: Nil;
                        }
                    case "hiss.HValue":
                        return cast (v, HValue);
                    default:
                        return Object(name, e);
                };
            case TObject:
                Object("!ANONYMOUS!", v);
            case TFunction:
                Object("NativeFun", v);
            default:
                throw 'value $v of type $t cannot be wrapped as $hint';
        }
    }

    /**
        Unwrap hvalues in a hiss list to their underlying types. Don't unwrap values whose indices
        are contained in keepWrapped, an optional list or T/Nil value.
    **/
    public static function unwrapList(hl: HValue, ?interp: CCInterp, keepWrapped: HValue = Nil): Array<Dynamic> {
        var indices: Array<Dynamic> = if (keepWrapped == Nil) {
            [];
        } else if (keepWrapped == T) {
            [for (i in 0... hl.toList().length) i];
        } else {
            unwrapList(keepWrapped, interp); // This looks like a recursive call but it's not. It's unwrapping the list of indices!
        }
        var idx = 0;
        return [for (v in hl.toList()) {
            if (indices.indexOf(idx++) != -1) {
                v;
            } else {
                v.value(interp);
            }
        }];
    }

    public static function length(v: HValue) {
        switch (v) {
            case List(l):
                return l.length;
            case String(s):
                return s.length;            
            default:
                throw '$v has no length';
        }
    }

    /**
     * Behind the scenes, this function evaluates the truthiness of an HValue
     **/
     public static function truthy(cond: HValue): Bool {
        return switch (cond) {
            case Nil: false;
            //case Int(i) if (i == 0): false; /* 0 being falsy would be useful for Hank read-counts */
            case List([]): false;
            default: true;
        }
    }

    /**
     * Behind the scenes function to HaxeTools.extract a haxe-compatible value from an HValue
     **/
     public static function value(hv: HValue, ?interp: CCInterp, reference: Bool = false): Dynamic {
        return switch (hv) {
            case Nil: false;
            case T: true;
            case Int(v):
                v;
            case Float(v):
                v;
            case String(v):
                v;
            case Object(_, v):
                v;
            case List(l):
                if (reference) {
                    l;
                } else {
                    [for (hvv in l) value(hvv, interp, true)]; // So far it seems that nested list elements should stay wrapped
                }
            case Dict(d):
                d;
            case Function(_, _, _):
                interp.toNativeFunction(hv);
            default:
                hv;
                /*throw 'hvalue $hv cannot be unwrapped for a native Haxe operation';*/
        }
    }

    // Primitive type predicates
    
    public static function isInt(hv: HValue) {
        return switch (hv) {
            case Int(_): T;
            default: Nil;
        };
    }

    public static function isFloat(hv: HValue) {
        return switch (hv) {
            case Float(_): T;
            default: Nil;
        };
    }

    public static function isNumber(hv: HValue) {
        return switch (hv) {
            case Int(_) | Float(_): T;
            default: Nil;
        };
    }

    public static function isSymbol(hv: HValue) {
        return switch (hv) {
            case Symbol(_): T;
            default: Nil;
        };
    }

    public static function isString(hv: HValue) {
        return switch (hv) {
            case String(_): T;
            default: Nil;
        };
    }

    public static function isList(hv: HValue) {
        return switch (hv) {
            case List(l): T;
            default: Nil;
        };
    }

    public static function isDict(hv: HValue) {
        return switch (hv) {
            case Dict(d): T;
            default: Nil;
        };
    }

    public static function isFunction(hv: HValue) {
        return switch (hv) {
            case Function(_, _, _): T;
            default: Nil;
        };
    }

    public static function isMacro(hv: HValue) {
        return switch (hv) {
            case Macro(_) | SpecialForm(_): T;
            default: Nil;
        };
    }

    public static function isCallable(hv: HValue) {
        return switch (hv) {
            case Function(_, _, _): T;
            case Macro(_) | SpecialForm(_): T;
            default: Nil;
        };
    }

    public static function isObject(hv: HValue) {
        return switch (hv) {
            case Object(_, _): T;
            default: Nil;
        };
    }
}