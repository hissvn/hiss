if [ ! -z "$HISS_TARGET" ]; then
    platform=$HISS_TARGET
elif [ ! -z "$1" ]; then
    platform=$1
else
    platform=interp
fi
haxe build-scripts/test/test-$platform.hxml