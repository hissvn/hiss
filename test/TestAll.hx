package test;

import hiss.StaticFiles;
import test.HissTestCase;

class TestAll {
  public static function main() {
    StaticFiles.compileWith("test-stdlib2.hiss");
    utest.UTest.run([
      new HissTestCase("test-stdlib2.hiss"),
      
      // Internal Tests. These were helpful while implementing and re-implementing core components,
      // but they're slow and not really worth it now.
      //new test.HStreamTestCase(),
      //new test.HissReaderTestCase(),
      //new test.NativeObjectTestCase(),
    ]);
    
  }
}