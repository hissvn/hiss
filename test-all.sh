#! /bin/bash

haxelib install ihx
haxelib install haxe-strings
haxelib install uuid
haxelib install utest
haxe build-scripts/test/test-interp.hxml && \
haxe build-scripts/test/test-py.hxml && \
haxe build-scripts/test/test-js.hxml && \
haxe build-scripts/test/test-nodejs.hxml && \
haxe build-scripts/test/test-cpp.hxml