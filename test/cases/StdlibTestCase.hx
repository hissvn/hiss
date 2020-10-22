package test.cases;

import hiss.HissTestCase;
import hiss.StaticFiles;

class StdlibTestCase extends HissTestCase {
    public function new() {
        StaticFiles.compileWith("StdlibTestCase.hiss");
        super("StdlibTestCase.hiss");
    }
}
