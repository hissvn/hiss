package hiss;

import hiss.HTypes;
using hiss.HissTools;

typedef HKeyValuePair = {
    key: HValue,
    value: HValue
};

/**
    Allows mapping any Hiss type to any other Hiss type in constant time.
**/
class HDict {
    var map: Map<String, Array<HKeyValuePair>> = [];
    var interp: CCInterp;

    public function new (interp: CCInterp, ?map: Map<String, Array<HKeyValuePair>>) {
        this.interp = interp;
        if (map != null) this.map = map;
    }

    /** Iterate on Hiss lists of the form (key value), which can be destructured in Hiss for loops **/
    public function iterator(): Iterator<HValue> {
        var kvIterator = keyValueIterator();
        return {
            next: () -> {
                var pair = kvIterator.next();
                return List([pair.key, pair.value]);
            },

            hasNext: () -> kvIterator.hasNext()
        };
    }

    /** Allow key => value iteration in Haxe **/
    public function keyValueIterator(): KeyValueIterator<HValue, HValue> {
        return new HDictIterator(map.keyValueIterator());
    }

    public function copy() { return new HDict(interp, map.copy()); }

    public function get(key: HValue): HValue {
        if (!map.exists(key.toPrint())) return Nil;
        var hashMatches = map[key.toPrint()];

        for (match in hashMatches) {
            if (match.key.eq(interp, key).truthy()) {
                return match.value;
            }
        }

        return Nil;
    }

    public function put(key: HValue, value: HValue) {
        if (!map.exists(key.toPrint())) map[key.toPrint()] = [];
        var hashMatches = map[key.toPrint()];

        for (match in hashMatches) {
            if (match.key.eq(interp, key).truthy()) {
                match.value = value;
                return;
            }
        }

        hashMatches.push({
            key: key,
            value: value
        });
    }

    public function exists(key: HValue) {
        if (!map.exists(key.toPrint())) return false;
        var hashMatches = map[key.toPrint()];

        for (match in hashMatches) {
            if (match.key.eq(interp, key).truthy()) {
                return true;
            }
        }

        return false;
    }

    public function erase(key: HValue) {
        if (!map.exists(key.toPrint())) return;
        var hashMatches = map[key.toPrint()];
        
        var idx = 0;
        while (idx < hashMatches.length) {
            var match = hashMatches[idx];
            if (match.key.eq(interp, key).truthy()) {
                hashMatches.splice(idx, 1);
                return;
            }
            ++idx;
        }
    }

    // TODO objects of the same type will be mapped in linear time because their print representations are the same.
    // One way to fix this is give an id to HValue.Object instances when constructing/importing objects.
    // The risk/complexity of that is making sure the same object doesn't somehow get a different index

}

class HDictIterator {
    var kvIterator: KeyValueIterator<String, Array<HKeyValuePair>>;
    var hvkIterator: Iterator<HKeyValuePair> = null;

    public function new (it: KeyValueIterator<String, Array<HKeyValuePair>>) {
        kvIterator = it;
    }

    public function next(): HKeyValuePair {
        if (hvkIterator != null && hvkIterator.hasNext()) {
            return hvkIterator.next();
        }

        if (kvIterator.hasNext()) {
            hvkIterator = kvIterator.next().value.iterator();
            return next();
        }

        return null;
    }

    public function hasNext(): Bool {
        if (hvkIterator != null && hvkIterator.hasNext()) {
            return true;
        }

        return kvIterator.hasNext();
    }
}