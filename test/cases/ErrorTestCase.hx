package test.cases;

import hiss.HissTestCase;
import hiss.StaticFiles;

class ErrorTestCase extends HissTestCase {
    public function new() {
        StaticFiles.compileWith("ErrorTestCase.hiss");
        super("ErrorTestCase.hiss");
        interp.setErrorHandler((error) -> {});
    }
}
