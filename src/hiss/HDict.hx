package hiss;

import hiss.HTypes;
using hiss.HissTools;
using hiss.Stdlib;

typedef HKeyValuePair = {
    key: HValue,
    value: HValue
};

/**
    Allows mapping any Hiss type to any other Hiss type in constant time.

    Is an Iterable and key-value iterable
**/
class HDict {
    var _map: Map<String, Array<HKeyValuePair>> = [];
    var _interp: CCInterp;

    public function new (interp: CCInterp, ?map: Map<String, Array<HKeyValuePair>>) {
        this._interp = interp;
        if (map != null) this._map = map;
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
        return new HDictIterator(_map.keyValueIterator());
    }

    public function copy() { return new HDict(_interp, _map.copy()); }

    public function get_h(key: HValue): HValue {
        if (!_map.exists(key.toPrint())) return Nil;
        var hashMatches = _map[key.toPrint()];

        for (match in hashMatches) {
            if (_interp.truthy(_interp.eq_ih(match.key, key))) {
                return match.value;
            }
        }

        return Nil;
    }

    public function put_hd(key: HValue, value: HValue) {
        if (!_map.exists(key.toPrint())) _map[key.toPrint()] = [];
        var hashMatches = _map[key.toPrint()];

        for (match in hashMatches) {
            if (_interp.truthy(_interp.eq_ih(match.key, key))) {
                match.value = value;
                return;
            }
        }

        hashMatches.push({
            key: key,
            value: value
        });
    }

    public function exists_h(key: HValue) {
        if (!_map.exists(key.toPrint())) return false;
        var hashMatches = _map[key.toPrint()];

        for (match in hashMatches) {
            if (_interp.truthy(_interp.eq_ih(match.key, key))) {
                return true;
            }
        }

        return false;
    }

    public function erase_hd(key: HValue) {
        if (!_map.exists(key.toPrint())) return;
        var hashMatches = _map[key.toPrint()];
        
        var idx = 0;
        while (idx < hashMatches.length) {
            var match = hashMatches[idx];
            if (_interp.truthy(_interp.eq_ih(match.key, key))) {
                hashMatches.splice(idx, 1);
                return;
            }
            ++idx;
        }
    }

    public static function makeDict_cc(interp: CCInterp, args: HValue, env: HValue, cc: Continuation) {
        var dict = new HDict(interp);

        var idx = 0;
        while (idx < args.length_h()) {
            var key = args.nth_h(Int(idx));
            var value = args.nth_h(Int(idx+1));
            dict.put_hd(key, value);
            idx += 2;
        }

        cc(Dict(dict));
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