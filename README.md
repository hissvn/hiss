# hiss

[![Build Status](https://travis-ci.org/hissvn/hiss.svg?branch=master)](https://travis-ci.org/hissvn/hiss)

An embedded Lisp compatible with Haxe, C++, JavaScript, and Python.

## Compile Options

### Production

* nativeFunctionMaxArgs - Hiss functions can be converted to native functions of your target language. Functions with more than this number of arguments will fail to convert. Default: 5
* ignoreWarnings - If defined, Hiss won't print any warning messages

### Debugging

* throwErrors - Instead of handling exceptions, Hiss will throw them immediately so you can see their original callstack
* traceCallstack - Print info on the Haxe Callstack as your program runs
* traceMacros - Print the macroexpansion whenever a macro is called
* traceReader - Print every expression parsed by the Reader
* traceContinuations - Print debugging info on call/cc usage
* traceClassImports - Print debugging info when importing native classes