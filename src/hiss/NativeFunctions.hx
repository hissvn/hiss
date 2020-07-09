package hiss;

import haxe.macro.Context;
import haxe.macro.Expr;

class NativeFunctions {
    public static macro function build(maxArgCount: Int): Array<Field> {
        var fields = Context.getBuildFields();

        for (argCount in 0...maxArgCount) {
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