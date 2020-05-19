package test;

import hiss.HissRepl;
import test.HAssert;

class SampleNativeObject {
    public static var staticMessage = "Hello, Haxe world! Meet Hiss world!";
    public var instanceMessage = "Easier to implement.";

    private var secret:String;
    public function new () {
        this.secret = "not work";
    }

    public static function staticMessage2(arg: String) {
        return 'I wonder if this will $arg';
    }

    public function instanceMessage2() {
        return 'I bet this will $secret';
    }
}

class SampleNativeObject2 {

    var name: String;
    var age: Int;

    public function new (name: String, age: Int) {
        this.name = name;
        this.age = age;
    }

    public function canoodle() {
        return '$name is ${if (age < 50) "not" else ""} old enough to canoodle';
    }
}

/**
    Test Hiss features for working with native Haxe objects
**/
class NativeObjectTestCase extends utest.Test {
    var repl: HissRepl;

    public function setup() {
        repl = new HissRepl();
    }

    public function testGetStaticField() {
        repl.interp.importClass(SampleNativeObject);

        var val = repl.eval('(get-property Sample-native-object "staticMessage")');
        //trace(val);
        HAssert.hvalEquals(String("Hello, Haxe world! Meet Hiss world!"), val);
    }

    public function testGetInstanceField() {
        repl.interp.importObject("object", new SampleNativeObject());

        var val = repl.eval('(get-property object "instanceMessage")');
        //trace(val);
        HAssert.hvalEquals(String("Easier to implement."), val);
    }

    public function testCallStaticFunction() {
        repl.interp.importClass(SampleNativeObject);
        var val = repl.eval('(call-method Sample-native-object "staticMessage2" \'("work"))');
        //trace(val);
        HAssert.hvalEquals(String("I wonder if this will work"), val);
    }

    public function testCallInstanceFunction() {
        repl.interp.importObject("object", new SampleNativeObject());
        var val = repl.eval('(call-method object "instanceMessage2" \'())');
        //trace(val);
        HAssert.hvalEquals(String("I bet this will not work"), val);
    }

    public function testConstructObject() {
        // Construct the one without args, make sure secret works
        repl.interp.importClass(SampleNativeObject);

        var val = repl.eval('(setq fork (create-instance Sample-native-object \'()))');
        //trace(val);
        val = repl.eval('(call-method fork "instanceMessage2" \'())');
        //trace(val);
        HAssert.hvalEquals(String("I bet this will not work"), val);
    }

    public function testConstructObject2() {
        // construct the complicated one with args, make sure everything works
        repl.interp.importClass(SampleNativeObject2);
        var val = repl.eval('(setq fork (create-instance Sample-native-object-2 \'("nat" 22)))');
        //trace(val);
        val = repl.eval('(call-method fork "canoodle" \'())');
        //trace(val);
        HAssert.hvalEquals(String("nat is not old enough to canoodle"), val);
    }
}