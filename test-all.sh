#! /bin/bash

# If the first argument is supplied, test-all.sh will fail as soon as one target fails.
end=""
if [ ! -z "$1" ]; then
    end="&& \\"
fi

# Build repls for each target that has one, so the tests can pipe input to them
eval "haxe build-scripts/repl/build-cpp-repl.hxml $end
haxe build-scripts/repl/build-nodejs-repl.hxml $end
haxe build-scripts/repl/build-py-repl.hxml $end

haxe build-scripts/test/test-interp.hxml $end
haxe build-scripts/test/test-py.hxml $end
haxe build-scripts/test/test-js.hxml $end
haxe build-scripts/test/test-nodejs.hxml $end
haxe build-scripts/test/test-cpp.hxml"