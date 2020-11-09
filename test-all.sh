#! /bin/bash

# Supply the first argument if calling this script from Travis CI.
# In that case, test-all.sh will fail as soon as one target fails.
# python3 will also be used instead of python when running shell commands on xenial.
end=""
if [ ! -z "$1" ]; then
    end="&& \\"
fi

eval "haxe build-scripts/test/test-interp.hxml $end
haxe build-scripts/test/test-py.hxml $end
haxe build-scripts/test/test-js.hxml $end
haxe build-scripts/test/test-nodejs.hxml $end
haxe build-scripts/test/test-cpp.hxml"