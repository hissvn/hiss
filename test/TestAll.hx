package test;

import hiss.StaticFiles;

class TestAll {
  public static function main() {
    StaticFiles.compileWith("test-std.hiss");
    StaticFiles.compileWith("module.hiss");
    utest.UTest.run([
      new test.HissTestCase("test-std.hiss"),
      
      // Internal Tests. These were helpful while implementing and re-implementing core components,
      // but they're slow and not really worth it now.
      //new test.HStreamTestCase(),
      //new test.HissReaderTestCase(),
      //new test.NativeObjectTestCase(),
    ]);
    
  }
}