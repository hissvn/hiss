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
    public function add_d(i: Dynamic) { _instance.add(i); }
    public function pop_d(block) { return _instance.pop(block); }
    public function push_d(i: Dynamic) { _instance.push(i); }
}

class HLock {
    var _instance: Lock;
    public function new() { _instance = new Lock(); }
    public function release_d() { _instance.release(); }
    public function wait_d(?timeout: Float) { return _instance.wait(timeout); }
}

class HMutex {
    var _instance: Mutex;
    public function new() { _instance = new Mutex(); }
    public function acquire_d() { _instance.acquire(); }
    public function release_d() { _instance.release(); }
    public function tryAcquire_d() { return _instance.tryAcquire(); }
}

class HThread {
    var _instance: Thread;
    function new(i: Thread) { _instance = i; }
    public static function create_d(callb: () -> Void) { return new HThread(Thread.create(callb)); }
    public static function current() { return Thread.current(); }
    public static function readMessage_d(block: Bool = true) { return Thread.readMessage(block); }
    public function sendMessage_d(msg: Dynamic) { _instance.sendMessage(msg); }
}