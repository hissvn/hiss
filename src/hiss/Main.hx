package hiss;

@:build(hiss.Hiss.build("src/hiss/Main.hiss"))
class Main {
	public static function main() {
		trace("Hello, compiled Hiss!");
	}
}
