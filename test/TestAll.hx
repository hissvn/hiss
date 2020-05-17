package test;

import hiss.StaticFiles;

class TestAll {
  public static function main() {
    StaticFiles.compileWith("test-std.hiss");
    utest.UTest.run([
      new test.HissTestCase("test-std.hiss"),
      new test.HStreamTestCase(),
      new test.HissReaderTestCase(),
      //new test.NativeObjectTestCase(),
    ]);
    
  }
}