package hiss;

import haxe.macro.Context;
import haxe.macro.Expr;

class BinopsBuilder {
    public static macro function build(): Array<Field> {
        var ops = [
            "+" => "add",
            "-" => "subtract",
            "/" => "divide",
            "*" => "multiply",
            ">" => "greater",
            ">=" => "greaterEqual",
            "<" => "lesser",
            "<=" => "lesserEqual",
            "==" => "equals",
            "%" => "modulo",
            "..." => "range"
        ];

        var fields = Context.getBuildFields();
        for (op in ops.keys()) {
            var opName = ops[op];
            
            var f = {
                ret: null,
                expr: Context.parse('{ return a $op b; }', Context.currentPos()),
                args: [{name: "a", type: null}, {name: "b", type: null}]
            };
            var opField = {
                name: opName,
                doc: null,
                meta: [],
                access: [AStatic, APublic],
                kind: FFun(f),
                pos: Context.currentPos()
            };
            fields.push(opField);
        }
        return fields;
    }
}