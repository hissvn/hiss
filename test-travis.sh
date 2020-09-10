#! /bin/bash

haxelib install ihx
haxelib install haxe-strings
haxelib install uuid
haxelib install utest
haxelib install hxnodejs
haxelib install hxcpp

# For travis builds, use && to fail as soon as any target fails a test
./test-all.sh yes