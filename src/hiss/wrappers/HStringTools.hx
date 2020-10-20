package hiss.wrappers;

import StringTools;

class HStringTools {
    public static var startsWith = StringTools.startsWith;
    public static var endsWith = StringTools.endsWith;
    public static var lpad =  StringTools.lpad;
    public static var rpad =  StringTools.rpad;
    public static var trim =  StringTools.trim;
    public static var ltrim = StringTools.ltrim;
    public static var rtrim = StringTools.rtrim;

    public static var replace = StringTools.replace; // Will be imported but then redefined by the hiss definition
}