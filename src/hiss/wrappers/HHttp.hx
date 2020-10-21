package hiss.wrappers;

import haxe.Http;

import hiss.HTypes;
import hiss.HissTools;
using hiss.HissTools;
using hiss.Stdlib;

/**
    More complicated than most hiss type wrappers.
**/
class HHttp {
    var _instance: Http;

    public function new(url: String) {
        _instance = new Http(url);
    }

    // setters
    public function setHeader_d(name: String, value: String) {
        _instance.setHeader(name, value);
    }

    // TODO a setHeader helper for sending UTF-8 json

    public function setParameter_d(name:String, value:String) {
        _instance.setParameter(name, value);
    }

    // TODO how to handle setPostBytes()?

    public function setPostData_d(?data:String) {
        _instance.setPostData(data);
    }

    // TODO this method is conditionally defined for now, but requestUrl() should probably be added to HttpNodeJs upstream.
    // https://github.com/HaxeFoundation/haxe/issues/9896
    #if !nodejs
    public static function requestUrl(url:String) : String {
        return Http.requestUrl(url);
    }
    #end

    public static function request_dcc(interp: CCInterp, args: HValue, env: HValue, cc: Continuation) {
        // First arg: an HHttp object
        var http: Http = args.first().value(interp)._instance;
        // Second (optional) arg: whether to send as POST request
        var post = if (args.length_h() > 1) args.second().value(interp) else false;

        http.onData = (dataString: String) -> {
            cc(dataString.toHValue());
        };

        http.onError = interp.error;

        // TODO onStatus() might be important in some way although it doesn't fit into the Hiss CC model

        http.request(post);
    }

    // TODO make an onBytes() version of request()
}