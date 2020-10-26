package test.cases;

import utest.Test;
import utest.Assert;
import hiss.CCInterp;
import hiss.StaticFiles;

class ImportClassTestCase extends Test {
    public function new() {
        super();
        StaticFiles.compileWith("ImportClassTestCase.hiss");
    }

    function testClassImport() {
        Assert.pass();

        var interp = new CCInterp();
        interp.importClass(TestClass, {name: "TestClass1"});
        // TODO import it multiple times with different meta and test those

        interp.load("ImportClassTestCase.hiss");
    }
}

class TestClass {
    public var field:String;

    // TODO test that _ fields can't be accessed
    public function new(?fieldValue = "default") {
        field = fieldValue;
    }

    // TODO add methods, static methods, etc. and test them
}
