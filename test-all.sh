#! /bin/bash

# If the first argument is supplied, test-all.sh will fail as soon as one target fails.
end=""
pysuffix=""
if [ ! -z "$1" ]; then
    end="&& \\"
    pysuffix="3"
fi

eval "haxe build-scripts/test/test-interp.hxml $end

haxe build-scripts/repl/build-py-repl.hxml && \
haxe build-scripts/test/test-py$pysuffix.hxml $end

haxe build-scripts/test/test-js.hxml $end

haxe build-scripts/repl/build-nodejs-repl.hxml && \
haxe build-scripts/test/test-nodejs.hxml $end

haxe build-scripts/repl/build-cpp-repl.hxml && \
haxe build-scripts/test/test-cpp.hxml"