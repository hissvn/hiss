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

    // To be more ergonomic, by default these all call on now() if no instance is provided:
    public static function getDate(?date: HDate):Int {
        if (date == null) date = now();
        return date.instance.getDate();
    }

    public static function getDay(?date: HDate):Int {
        if (date == null) date = now();
        return date.instance.getDay();
    }

    public static function getYear(?date: HDate):Int {
        if (date == null) date = now();
        return date.instance.getFullYear();
    }

    public static function getHours(?date: HDate):Int {
        if (date == null) date = now();
        return date.instance.getHours();
    }

    public static function getMinutes(?date: HDate):Int {
        if (date == null) date = now();
        return date.instance.getMinutes();
    }

    public static function getMonth(?date: HDate):Int {
        if (date == null) date = now();
        return date.instance.getMonth();
    }

    public static function getSeconds(?date: HDate):Int {
        if (date == null) date = now();
        return date.instance.getSeconds();
    }

    public static function getTime(?date: HDate):Float {
        if (date == null) date = now();
        return date.instance.getTime();
    }

    public static function getTimezoneOffset(?date: HDate):Int {
        if (date == null) date = now();
        return date.instance.getTimezoneOffset();
    }

    // TODO the UTC functions might be useful someday
}