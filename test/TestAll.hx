package test;

import haxe.Log;
import haxe.PosInfos;
import hiss.StaticFiles;

import utest.Runner;
import utest.ui.Report;

class TestAll {
    public static function main() {
        var runner = new Runner();
        runner.addCases(test.cases);
        Report.create(runner);
        runner.run();
    }
}
