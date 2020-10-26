import sys.thread.Thread;
import sys.thread.Lock;

typedef Continuation = (String) -> Void;

class Experiment {
    static function t(s:String) {
        trace(s);
    }

    public static function main() {
        begin([for (i in 0...1000) 'hey'], t);
    }

    static function begin(exps:Array<String>, cc:Continuation) {
        if (exps.length == 0)
            return;
        var ccLock = new Lock();
        Thread.create(() -> {
            eval(exps.shift(), (val) -> {
                if (exps.length == 0)
                    cc(val);
                ccLock.release();
            });
        });
        ccLock.wait();
        begin(exps, cc);
    }

    static function eval(exp:String, cc:Continuation) {
        cc(exp + "e");
    }
}
