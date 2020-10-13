#! /bin/bash

# Supply the first argument if calling this script from Travis CI.
# In that case, test-all.sh will fail as soon as one target fails.
# python3 will also be used instead of python when running shell commands on xenial.
end=""
pysuffix=""
if [ ! -z "$1" ]; then
    end="&& \\"
    if [ "${TRAVIS_OS_NAME}" = "linux" ]; then
        pysuffix="3"
    fi
fi

eval "haxe build-scripts/test/test-interp.hxml $end

haxe build-scripts/repl/build-py-repl.hxml && \
haxe build-scripts/test/test-py$pysuffix.hxml $end

haxe build-scripts/test/test-js.hxml $end

haxe build-scripts/repl/build-nodejs-repl.hxml && \
haxe build-scripts/test/test-nodejs.hxml $end

haxe build-scripts/repl/build-cpp-repl.hxml && \
haxe build-scripts/test/test-cpp.hxml"