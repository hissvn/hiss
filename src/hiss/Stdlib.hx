package hiss;

import haxe.io.Path;

import hiss.HTypes;
import uuid.Uuid;

using hiss.HissTools;
using hiss.Stdlib;

/**
    Hiss Standard library functions implemented in Haxe
**/
class Stdlib {
    public static function sort(list: Array<Dynamic>, ?fun: (Dynamic, Dynamic) -> Int) {
        if (fun == null) fun = Reflect.compare;
        var sorted = list.copy();
        sorted.sort(fun);
        return sorted;
    }

    public static function reverse(list: Array<Dynamic>) {
        var reversed = list.copy();
        reversed.reverse();
        return reversed;
    }

    // Can't be ported to Hiss the Haxe reflection API doesn't allow array indexing
    public static function nth_h(list: HValue, idx: HValue):HValue {
        return list.toList()[idx.toInt()];
    }

    public static function setNth_h(arr: HValue, idx: HValue, val: HValue) { 
        arr.toList()[idx.toInt()] = val; return arr;
    }

    public static function symbolName_h(v: HValue): String {
        return HaxeTools.extract(v, Symbol(name) => name, "symbol name");
    }

    public static function symbol(?name: String) {
        // When called with no arguments, (symbol) acts like common-lisp's (gensym)
        if (name == null) {
            return Symbol('_${Uuid.v4()}');
        }
        // With a string argument, it's like common-lisp's (intern)
        return Symbol(name);
    }

    /**
        Hiss can only iterate on objects that unify with the Haxe Iterable interface.
        This function wraps a next() and hasNext() function as an iterable object.
        With it, you can make an iterable object out of hiss functions.

        If you need to call this with Haxe functions, make sure next() returns an HValue.
    **/
    public static function iterable(next: Dynamic, hasNext: Dynamic) {
        return {
            iterator: function() {
                return {
                    next: () -> next().toHValue(),
                    hasNext: hasNext
                };
            }
        };
    }

    /**
        Wrap a Haxe iterator as a hiss-compatible Iterable.
    **/
    public static function iteratorToIterable(iterator: Iterator<Dynamic>) {
        return iterable(iterator.next, iterator.hasNext);
    }

    /**
        Destructively clear a list
    **/
    public static function clear_hd(l: HValue) {
        var arr = l.toList();
        arr.splice(0, arr.length);
        return l;
    }

    public static function range(a: Dynamic, ?b: Dynamic) {
        var start = if (b == null) 0 else a;
        var end = if (b == null) a else b;

        var intIterator = start ... end;

        // Haxe IntIterators are weird. What we really want is an Iterable of HValues,
        // whose iterator()'s next() and hasNext() are not inlined.
        return iteratorToIterable(intIterator);
    }

    public static function length_h(v: HValue) {
        switch (v) {
            case List(l):
                return l.length;
            case String(s):
                return s.length;
            default:
                throw '$v has no length';
        }
    }

    // Primitive type predicates
    
    public static function isInt_h(hv: HValue) {
        return switch (hv) {
            case Int(_): T;
            default: Nil;
        };
    }

    public static function isFloat_h(hv: HValue) {
        return switch (hv) {
            case Float(_): T;
            default: Nil;
        };
    }

    public static function isNumber_h(hv: HValue) {
        return switch (hv) {
            case Int(_) | Float(_): T;
            default: Nil;
        };
    }

    public static function isSymbol_h(hv: HValue) {
        return switch (hv) {
            case Symbol(_): T;
            default: Nil;
        };
    }

    public static function isString_h(hv: HValue) {
        return switch (hv) {
            case String(_): T;
            default: Nil;
        };
    }

    public static function isList_h(hv: HValue) {
        return switch (hv) {
            case List(l): T;
            default: Nil;
        };
    }

    public static function isDict_h(hv: HValue) {
        return switch (hv) {
            case Dict(d): T;
            default: Nil;
        };
    }

    public static function isFunction_h(hv: HValue) {
        return switch (hv) {
            case Function(_, _): T;
            default: Nil;
        };
    }

    public static function isMacro_h(hv: HValue) {
        return switch (hv) {
            case Macro(_, _) | SpecialForm(_, _): T;
            default: Nil;
        };
    }

    public static function isCallable_h(hv: HValue) {
        return switch (hv) {
            case Function(_, _) | Macro(_, _) | SpecialForm(_, _): T;
            default: Nil;
        };
    }

    public static function isObject_h(hv: HValue) {
        return switch (hv) {
            case Object(_, _): T;
            default: Nil;
        };
    }

    public static function rest(list: HValue): HValue {
        return List(list.toList().slice(1));
    }

    // Since the variadic binop macro uses cons and it's one of the first
    // things in the Hiss prelude, might as well let this one stand as a Haxe function.
    public static function cons(hv: HValue, hl: HValue): HValue {
        if (hl == Nil || hl.length_h() == 0) return List([hv]);
        var l = hl.toList().copy();
        l.insert(0, hv);
        return List(l);
    }

    public static function eq(a: HValue, interp: CCInterp, b: HValue): HValue {
        // Throw an error if trying to compare with interpstrings
        switch (a) {
            case InterpString(_): a = interp.eval(a);
            default:
        }
        switch (b) {
            case InterpString(_): b = interp.eval(b);
            default:
        }

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
                    if (!interp.truthy(eq(l1[i], interp, l2[i]))) return Nil;
                    i++;
                }
                return T;
            case Quote(aa) | Quasiquote(aa) | Unquote(aa) | UnquoteList(aa):
                var bb = HaxeTools.extract(b, Quote(e) | Quasiquote(e) | Unquote(e) | UnquoteList(e) => e);
                return eq(aa, interp, bb);
            case SpecialForm(fun, _):
                return switch (b) {
                    case SpecialForm(fun2, _) if (fun == fun2): T;
                    default: Nil;
                };
            default:
                throw 'eq is not implemented for $a and $b';
        }
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
            case Function(_, meta) | Macro(_, meta) | SpecialForm(_, meta):
                '${meta.name}(${meta.argNames})';
            case Nil:
                'nil';
            case Null:
                'null';
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
            #if traceReader
            case Comment:
                'comment';
            #end
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
}