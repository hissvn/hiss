package hiss.wrappers;

class HDate {
    var _instance:Date;

    static function _fromHaxeDate(date:Date):HDate {
        var hd = new HDate(2020, 0, 0, 0, 0, 0);
        hd._instance = date;
        return hd;
    }

    public function new(year:Int, month:Int, day:Int, hour:Int, min:Int, sec:Int) {
        _instance = new Date(year, month, day, hour, min, sec);
    }

    public static function fromString(s:String):HDate {
        return _fromHaxeDate(Date.fromString(s));
    }

    public static function fromTime(t:Float):HDate {
        return _fromHaxeDate(Date.fromTime(t));
    }

    public static function now():HDate {
        return _fromHaxeDate(Date.now());
    }

    // To be more ergonomic, by default these all call on now() if no instance is provided:
    public static function getDate(?date:HDate):Int {
        if (date == null)
            date = now();
        return date._instance.getDate();
    }

    public static function getDay(?date:HDate):Int {
        if (date == null)
            date = now();
        return date._instance.getDay();
    }

    public static function getYear(?date:HDate):Int {
        if (date == null)
            date = now();
        return date._instance.getFullYear();
    }

    public static function getHours(?date:HDate):Int {
        if (date == null)
            date = now();
        return date._instance.getHours();
    }

    public static function getMinutes(?date:HDate):Int {
        if (date == null)
            date = now();
        return date._instance.getMinutes();
    }

    public static function getMonth(?date:HDate):Int {
        if (date == null)
            date = now();
        return date._instance.getMonth();
    }

    public static function getSeconds(?date:HDate):Int {
        if (date == null)
            date = now();
        return date._instance.getSeconds();
    }

    public static function getTime(?date:HDate):Float {
        if (date == null)
            date = now();
        return date._instance.getTime();
    }

    public static function getTimezoneOffset(?date:HDate):Int {
        if (date == null)
            date = now();
        return date._instance.getTimezoneOffset();
    }

    // TODO the UTC functions might be useful someday
}
