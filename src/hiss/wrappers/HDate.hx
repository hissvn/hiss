package hiss.wrappers;

class HDate {
    var instance:Date;

    static function fromHaxeDate(date:Date):HDate {
        var hd = new HDate(2020, 0, 0, 0, 0, 0);
        hd.instance = date;
        return hd;
    }

    public function new(year:Int, month:Int, day:Int, hour:Int, min:Int, sec:Int) {
        instance = new Date(year, month, day, hour, min, sec);
    }

    public static function fromString(s:String):HDate {
        return fromHaxeDate(Date.fromString(s));
    }

    public static function fromTime(t:Float):HDate {
        return fromHaxeDate(Date.fromTime(t));
    }

    public static function now():HDate {
        return fromHaxeDate(Date.now());
    }

    public function getDate():Int {
        return instance.getDate();
    }

    public function getDay():Int {
        return instance.getDay();
    }

    public function getFullYear():Int {
        return instance.getFullYear();
    }

    public function getHours():Int {
        return instance.getHours();
    }

    public function getMinutes():Int {
        return instance.getMinutes();
    }

    public function getMonth():Int {
        return instance.getMonth();
    }

    public function getSeconds():Int {
        return instance.getSeconds();
    }

    public function getTime():Float {
        return instance.getTime();
    }

    public function getTimezoneOffset():Int {
        return instance.getTimezoneOffset();
    }

    // TODO the UTC functions might be useful someday
}