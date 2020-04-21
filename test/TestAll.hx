package test;

class TestAll {
  public static function main() {
    utest.UTest.run([
      new test.HissTestCase("test/std.hiss"),
      new test.HStreamTestCase(),
      new test.HissReaderTestCase(),
    ]);
    
  }
}