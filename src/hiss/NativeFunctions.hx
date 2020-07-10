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

        // If hiss-native-function-max-args is defined when compiling Hiss,
        // any Hiss function with number of arguments up to/including the defined value,
        // will be passable as a native function in the target language.
        var maxArgCompilerFlag = Context.definedValue("hiss-native-function-max-args");
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

        for (argCount in 0...maxArgCount+1) {
            var argListExpr = "(";
            var funcallExpr = "funcall(false, List([fun,";
            for (argNum in 1...argCount+1) {
                argListExpr += 'arg$argNum: Dynamic,';
                funcallExpr += 'Quote(arg$argNum.toHValue()),';
            }
            if (argCount > 0)
                argListExpr = argListExpr.substr(0, argListExpr.length - 1);
            argListExpr += ")";
            funcallExpr = funcallExpr.substr(0, funcallExpr.length - 1);
            funcallExpr += "]), List([Dict([])]), (_val) -> {val = _val;})";

            var fullBodyExpr = '{ return $argListExpr -> { var val = null; $funcallExpr; return val.value(true);}; }';
            trace(fullBodyExpr);

            var newField = {
                name: "toNativeFunction" + argCount,
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
        }

        return fields;
    }
}