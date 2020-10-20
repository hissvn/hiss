package hiss.wrappers;

import sys.thread.Deque;
import sys.thread.Lock;
import sys.thread.Mutex;
import sys.thread.Thread;
import sys.thread.Tls;

// Because many targets implement the threading API with abstracts, those types need to be wrapped
// in classes before they can be imported to the Hiss environment.

class HDeque {
    var _instance: Deque<Dynamic>;
    public function new() { _instance = new Deque<Dynamic>(); }
    public function add(i: Dynamic) { _instance.add(i); }
    public function pop(block) { return _instance.pop(block); }
    public function push(i: Dynamic) { _instance.push(i); }
}

class HLock {
    var _instance: Lock;
    public function new() { _instance = new Lock(); }
    public function release() { _instance.release(); }
    public function wait(?timeout: Float) { return _instance.wait(timeout); }
}

class HMutex {
    var _instance: Mutex;
    public function new() { _instance = new Mutex(); }
    public function acquire() { _instance.acquire(); }
    public function release() { _instance.release(); }
    public function tryAcquire() { return _instance.tryAcquire(); }
}

class HThread {
    var _instance: Thread;
    function new(i: Thread) { _instance = i; }
    public static function create(callb: () -> Void) { return new HThread(Thread.create(callb)); }
    public static function current() { return Thread.current(); }
    public static function readMessage(block: Bool = true) { return Thread.readMessage(block); }
    public function sendMessage(msg: Dynamic) { _instance.sendMessage(msg); }
}