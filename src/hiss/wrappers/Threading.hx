package hiss.wrappers;

import sys.thread.Deque;
import sys.thread.Lock;
import sys.thread.Mutex;
import sys.thread.Thread;
import sys.thread.Tls;

// Because many targets implement the threading API with abstracts, those types need to be wrapped
// in classes before they can be imported to the Hiss environment.

// On the C++ target, references to the underlying class instances will not be counted for some
// reason, so a VERY hacky form of manual reference preservation/deletion is required


class HDeque {
    var instance: Deque<Dynamic>;
    public function new() { instance = new Deque<Dynamic>(); }
    public function add(i: Dynamic) { instance.add(i); }
    public function pop(block) { return instance.pop(block); }
    public function push(i: Dynamic) { instance.push(i); }
}

class HLock {
    var instance: Lock;
    public function new() { instance = new Lock(); }
    public function release() { instance.release(); }
    public function wait(?timeout: Float) { return instance.wait(timeout); }
}

class HMutex {
    var instance: Mutex;
    public function new() { instance = new Mutex(); }
    public function acquire() { instance.acquire(); }
    public function release() { instance.release(); }
    public function tryAcquire() { return instance.tryAcquire(); }
}

class HThread {
    var instance: Thread;
    function new(i: Thread) { instance = i; }
    public static function create(callb: () -> Void) { return new HThread(Thread.create(callb)); }
    public static function current() { return Thread.current(); }
    public static function readMessage(block: Bool = true) { return Thread.readMessage(block); }
    public function sendMessage(msg: Dynamic) { instance.sendMessage(msg); }
}