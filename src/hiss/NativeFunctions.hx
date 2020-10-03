package hiss;

import haxe.macro.Context;
import haxe.macro.Expr;

/**
    Generates the CCInterp function toNativeFunction(),
    which wraps Hiss functions as function objects to be passed
    around as objects in the target language.
**/
class NativeFunctions {
    public static macro function build(): Array<Field> {
        var fields = Context.getBuildFields();

        // 5 seems like a reasonable default number of arguments
        // to support native function interchangeability
        var maxArgCount = 5;

        // If nativeFunctionMaxArgs is defined when compiling Hiss,
        // any Hiss function with number of arguments up to/including the defined value,
        // will be passable as a native function in the target language.
        var maxArgCompilerFlag = Context.definedValue("nativeFunctionMaxArgs");
        if (maxArgCompilerFlag != null) {
            maxArgCount = Std.parseInt(maxArgCompilerFlag);
        }

        fields.push({
            name: "nativeFunctionMaxArgs",
            doc: null,
            meta: [],
            access: [APublic],
            kind: FFun({
                ret: macro : Dynamic,
                args: [],
                expr: macro return $v{maxArgCount}
            }),
            pos: Context.currentPos()
        });

        var fullBodyExpr = "switch (fun) {";

        for (argCount in 0...maxArgCount+1) {
            var argListExpr = "(";
            var funcallExpr = "funcall(false, List([fun,";
            for (argNum in 1...argCount+1) {
                argListExpr += '?arg$argNum: Dynamic,';
                funcallExpr += 'Quote(arg$argNum.toHValue()),';
            }
            if (argCount > 0)
                argListExpr = argListExpr.substr(0, argListExpr.length - 1);
            argListExpr += ")";
            funcallExpr = funcallExpr.substr(0, funcallExpr.length - 1);
            funcallExpr += "]), emptyEnv(), (_val) -> {val = _val;})";

            fullBodyExpr += 'case Function(_, _, args) if (args != null && args.length == $argCount):
                                return $argListExpr -> { var val = null; $funcallExpr; return val.value(this, true);};\n';
        }

        fullBodyExpr += "case Function(_, _, args) if (args != null && args.length >" + maxArgCount + "):
                            throw 'Function has too many args for conversion to native function';
                        case Function(_, _, args) if (args == null):
                            throw 'Function has no args specified, cannot be converted';
                        default:
                            throw 'Cannot convert non-function $fun to native function';
                        }";

        var newField = {
            name: "toNativeFunction",
            doc: null,
            meta: [],
            access: [APublic],
            kind: FFun({
                ret: macro : Dynamic,
                args: [{
                    name: "fun",
                    type: macro : HValue}
                ],
                expr: Context.parse(fullBodyExpr, Context.currentPos())
            }),
            pos: Context.currentPos()
        };
        fields.push(newField);

        return fields;
    }
}