package test;

class TestAll {
  public static function main() {
    utest.UTest.run([
      //new HissTestCase("test/std.hiss"),
      new HStreamTestCase(),
    ]);
    
  }
}