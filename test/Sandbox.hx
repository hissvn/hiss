@:yield
class NestedIterator {
    public static function stuff(): Iterator<String> {
        @yield return "fork";
        @yield return "knife";
        @yield return "spoon";
        funkyStuff();
    }

    static function funkyStuff(): Iterator<String> {
        @yield return "fork2";
        @yield return "knife2";
        @yield return "spoon2";
    }
}


class Sandbox {
    public static function main() {
        for (str in NestedIterator.stuff()) {
            trace(str);
        }
    }
}