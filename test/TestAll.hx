package test;

import haxe.Log;
import haxe.PosInfos;
import hiss.StaticFiles;
import hiss.HissTestCase;

class TestAll {
    public static function main() {
        StaticFiles.compileWith("test-stdlib2.hiss");
        utest.UTest.run([
            new HissTestCase(
                "test-stdlib2.hiss",
                [
                    // Functions to ignore in testing:
                    "version",
                    "home-dir",
                    "exit",
                    "quit",
                    "print",
                    "prints",
                    "test",
                ]),
      
            // Interop feature tests
            new test.NativeFunctionTestCase(),
            new test.TruthyTestCase(),

            // Internal Tests. These are/were helpful while implementing and re-implementing core components,
            // but eventually they will lose their usefulness as things become testable within Hiss scripts
            //new test.HStreamTestCase(),
            //new test.HissReaderTestCase(),
            //new test.NativeObjectTestCase(),
        ]);
    }
}