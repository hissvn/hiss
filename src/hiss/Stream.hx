package hiss;

import sys.io.File;
import haxe.ds.Option;

using StringTools;

class Stream {
	var content:String;

	public function new(file:String) {
		// Banish ye Windows line-endings
		content = File.getContent(file).replace('\r', '');
	}

	public function peek(chars:Int) {
		if (content.length < chars)
			return None;
		return Some(content.substr(0, chars));
	}

	public function isEmpty() {
		return content.length > 0;
	}
}
