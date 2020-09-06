#! /bin/bash

haxelib install ihx
haxelib install haxe-strings
haxelib install uuid
haxelib install utest
haxelib install hxnodejs
haxelib install hxcpp
haxe build-scripts/test/test-interp.hxml && \
haxe build-scripts/test/test-py3.hxml && \
haxe build-scripts/test/test-js.hxml && \
haxe build-scripts/test/test-nodejs.hxml && \
haxe build-scripts/test/test-cpp.hxml