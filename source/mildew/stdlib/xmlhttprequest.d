/**
This module implements the XMLHttpRequest class.

────────────────────────────────────────────────────────────────────────────────

Copyright (C) 2021 pillager86.rf.gd

This program is free software: you can redistribute it and/or modify it under 
the terms of the GNU General Public License as published by the Free Software 
Foundation, either version 3 of the License, or (at your option) any later 
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with 
this program.  If not, see <https://www.gnu.org/licenses/>.
*/
module mildew.stdlib.xmlhttprequest;

import std.concurrency;
import std.net.curl;
debug import std.stdio;
import std.typecons;

import mildew.environment;
import mildew.exceptions;
import mildew.interpreter;
import mildew.types;
import mildew.vm;

/**
 * Initializes the XMLHttpRequest class library.
 * Params:
 *   interpreter = The Interpreter instance to store the XMLHttpRequest constructor in
 */
void initializeXMLHttpRequestLibrary(Interpreter interpreter)
{
    auto ctor = new ScriptFunction("XMLHttpRequest", &native_XMLHttpRequest_ctor, true);

    ctor["prototype"] = getXMLHttpRequestPrototype();
    ctor["prototype"]["constructor"] = ctor;

    interpreter.forceSetGlobal("XMLHttpRequest", ctor, false);
}

package:

class ScriptXMLHttpRequest
{
    enum ReadyState : ushort {
        UNSENT = 0,
        OPENED = 1,
        HEADERS_RECEIVED = 2,
        LOADING = 3,
        DONE = 4
    }

    enum EventType {
        LOAD_START,
        PROGRESS,
        ABORT,
        ERROR,
        LOAD,
        TIMEOUT,
        LOADEND,

        RS_CHANGE
    }

    alias Event = Tuple!(EventType, ScriptAny);

    /*

    void setRequestHeader(in string name, in string value)
    {
        _http.addRequestHeader(name, value);
    }*/

private:
    HTTP _http;
    bool _async;
    bool _abort = false;
    bool _done = false;

    ReadyState _readyState = ReadyState.UNSENT;
    ScriptFunction _onReadyStateChange;

    // event
    ScriptFunction _onLoadStart;
    ScriptFunction _onProgress;
    ScriptFunction _onAbort;
    ScriptFunction _onError;
    ScriptFunction _onLoad;
    ScriptFunction _onTimeout;
    ScriptFunction _onLoadEnd;
    Event[] _eventQueue; // for async


    // response
    ushort _status;
    string[string] _responseHeaders;
    ubyte[] _response; // just a string for now
}

private ScriptObject _XMLHttpRequestPrototype;

private ScriptObject getXMLHttpRequestPrototype()
{
    if(_XMLHttpRequestPrototype is null)
    {
        _XMLHttpRequestPrototype = new ScriptObject("XMLHttpRequest", null);
        _XMLHttpRequestPrototype["abort"] = new ScriptFunction("XMLHttpRequest.prototype.abort",
                &native_XMLHttpRequest_abort);
        _XMLHttpRequestPrototype["getAllResponseHeaders"] = new ScriptFunction(
                "XMLHttpRequest.prototype.getAllResponseHeaders", 
                &native_XMLHttpRequest_getAllResponseHeaders);
        _XMLHttpRequestPrototype["getResponseHeader"] = new ScriptFunction(
                "XMLHttpRequest.prototype.getResponseHeader",
                &native_XMLHttpRequest_getResponseHeader);
        _XMLHttpRequestPrototype.addGetterProperty("onreadystatechange", new ScriptFunction(
                "XMLHttpRequest.prototype.onreadystatechange",
                &native_XMLHttpRequest_p_onreadystatechange));
        _XMLHttpRequestPrototype.addSetterProperty("onreadystatechange", new ScriptFunction(
                "XMLHttpRequest.prototype.onreadystatechange",
                &native_XMLHttpRequest_p_onreadystatechange));
        _XMLHttpRequestPrototype["open"] = new ScriptFunction("XMLHttpRequest.prototype.open",
                &native_XMLHttpRequest_open);
        _XMLHttpRequestPrototype.addGetterProperty("readyState", new ScriptFunction(
                "XMLHttpRequest.prototype.readyState",
                &native_XMLHttpRequest_p_readyState));                
        _XMLHttpRequestPrototype.addGetterProperty("response", new ScriptFunction(
                "XMLHttpRequest.prototype.respone",
                &native_XMLHttpRequest_p_response));
        _XMLHttpRequestPrototype["send"] = new ScriptFunction("XMLHttpRequest.prototype.send",
                &native_XMLHttpRequest_send);
        _XMLHttpRequestPrototype["setRequestHeader"] = new ScriptFunction(
                "XMLHttpRequest.prototype.setRequestHeader",
                &native_XMLHttpRequest_setRequestHeader);
        _XMLHttpRequestPrototype.addGetterProperty("status", new ScriptFunction(
                "XMLHttpRequest.prototype.status",
                &native_XMLHttpRequest_p_status));
    }
    return _XMLHttpRequestPrototype;
}

private ScriptAny native_XMLHttpRequest_ctor(Environment env, ScriptAny* thisObj,
                                             ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(!thisObj.isObject)
        throw new ScriptRuntimeException("XMLHttpRequest must be called with new");
    
    auto http = new ScriptXMLHttpRequest();
    (cast(ScriptObject)*thisObj).nativeObject = http;
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_XMLHttpRequest_abort(Environment env, ScriptAny* thisObj,
                                              ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto req = thisObj.toNativeObject!ScriptXMLHttpRequest;
    if(req is null)
        throw new ScriptRuntimeException("Invalid XMLHttpRequest object");
    req._status = 0;
    req._abort = true;
    req._readyState = ScriptXMLHttpRequest.ReadyState.UNSENT;
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_XMLHttpRequest_getAllResponseHeaders(Environment env, ScriptAny* thisObj,
                                                            ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto req = thisObj.toNativeObject!ScriptXMLHttpRequest;
    if(req is null)
        throw new ScriptRuntimeException("Invalid XMLHttpRequest object");
    auto headers = "";
    foreach(key, value ; req._responseHeaders)
    {
        headers ~= key ~ ": " ~ value ~ "\n";
    }
    return ScriptAny(headers);
}

private ScriptAny native_XMLHttpRequest_getResponseHeader(Environment env, ScriptAny* thisObj,
                                                          ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto req = thisObj.toNativeObject!ScriptXMLHttpRequest;
    if(req is null)
        throw new ScriptRuntimeException("Invalid XMLHttpRequest object");
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    auto key = args[0].toString;
    if(key in req._responseHeaders)
        return ScriptAny(req._responseHeaders[key]);
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_XMLHttpRequest_p_onreadystatechange(Environment env,
                                                             ScriptAny* thisObj,
                                                             ScriptAny[] args,
                                                             ref NativeFunctionError nfe)
{
    auto req = thisObj.toNativeObject!ScriptXMLHttpRequest;
    if(req is null)
        throw new ScriptRuntimeException("Invalid XMLHttpRequest object");
    if(args.length < 1)
    {
        if(req._onReadyStateChange)
            return ScriptAny(req._onReadyStateChange);
        else
            return ScriptAny(null);
    }
    if(args[0].type != ScriptAny.Type.FUNCTION)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    req._onReadyStateChange = args[0].toValue!ScriptFunction;
    return args[0];
}

private ScriptAny native_XMLHttpRequest_open(Environment env, ScriptAny* thisObj,
                                             ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.uni: toUpper;
    auto req = thisObj.toNativeObject!ScriptXMLHttpRequest;
    if(req is null)
        throw new ScriptRuntimeException("Invalid XMLHttpRequest object");

    auto vm = env.g.interpreter.vm;
    
    if(args.length < 2)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }

    auto method = args[0].toString();
    auto url = args[1].toString();
    req._http = HTTP(url);
    switch(method.toUpper)
    {
    case "GET":
        req._http.method = HTTP.Method.get;
        break;
    case "POST":
        req._http.method = HTTP.Method.post;
        break;
    case "PUT":
        req._http.method = HTTP.Method.put;
        break;
    case "DELETE":
        req._http.method = HTTP.Method.del;
        break;
    default:
        throw new ScriptRuntimeException("Invalid HTTP method specified");
    }

    req._async = args.length > 2 ? cast(bool)args[2] : true;
    string user = args.length > 3 ? args[3].toString() : null;
    string pass = args.length > 4 ? args[4].toString() : null;

    if(user)
        req._http.addRequestHeader("user", user);
    if(pass)
        req._http.addRequestHeader("password", pass);

    // TODO all events
    req._http.onReceiveStatusLine = (HTTP.StatusLine line) {
        req._status = line.code;
    };

    req._http.onReceive = (ubyte[] data) {
        import core.thread: Thread;

        synchronized(req)
        {
            if(req._response.length == 0)
            {
                req._readyState = ScriptXMLHttpRequest.ReadyState.HEADERS_RECEIVED;
                if(!req._async)
                {
                    if(req._onReadyStateChange)
                        vm.runFunction(req._onReadyStateChange, *thisObj, []);
                }
                else
                {
                    req._eventQueue ~= tuple(ScriptXMLHttpRequest.EventType.RS_CHANGE, 
                            ScriptAny(ScriptXMLHttpRequest.ReadyState.HEADERS_RECEIVED));
                }
            }
            req._response ~= data;
            if(req._readyState == ScriptXMLHttpRequest.ReadyState.HEADERS_RECEIVED)
            {
                req._readyState = ScriptXMLHttpRequest.ReadyState.LOADING;
                if(!req._async)
                {
                    if(req._onReadyStateChange)
                        vm.runFunction(req._onReadyStateChange, *thisObj, []);
                }
                else
                {
                    synchronized 
                    {
                        req._eventQueue ~= tuple(ScriptXMLHttpRequest.EventType.RS_CHANGE, 
                            ScriptAny(ScriptXMLHttpRequest.ReadyState.LOADING));
                    }
                }
            }
        }
        return data.length;
    };

    req._http.onProgress = (size_t dlTotal, size_t dlNow, size_t ulTotal, size_t ulNow) {
        if(dlTotal == dlNow && (req._readyState == ScriptXMLHttpRequest.ReadyState.LOADING
         || req._readyState == ScriptXMLHttpRequest.ReadyState.HEADERS_RECEIVED))
        {
            req._readyState = ScriptXMLHttpRequest.ReadyState.DONE;
            if(!req._async)
            {
                if(req._onReadyStateChange)
                    vm.runFunction(req._onReadyStateChange, *thisObj, []);
            }
            else
            {
                synchronized
                {
                    req._eventQueue ~= tuple(ScriptXMLHttpRequest.EventType.RS_CHANGE, 
                        ScriptAny(req._readyState));
                }
            }
        }
        return 0;
    };

    req._http.onReceiveHeader = (in char[] key, in char[] value) {
        synchronized(req) 
        {
            req._responseHeaders[key.idup] = value.idup;
        }
    };

    req._http.onSend = (void[] data) {
        if(req._abort)
        {
            req._abort = false;
            return HTTP.requestAbort;
        }  
        return data.length;
    };

    req._readyState = ScriptXMLHttpRequest.ReadyState.OPENED;
    if(!req._async)
    {
        if(req._onReadyStateChange)
            vm.runFunction(req._onReadyStateChange, *thisObj, []);
    }
    else
    {
        synchronized
        {
            req._eventQueue ~= tuple(ScriptXMLHttpRequest.EventType.RS_CHANGE, 
                ScriptAny(ScriptXMLHttpRequest.ReadyState.OPENED));
        }
    }

    return ScriptAny.UNDEFINED;
}

private ScriptAny native_XMLHttpRequest_p_readyState(Environment env, ScriptAny* thisObj,
                                                     ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto req = thisObj.toNativeObject!ScriptXMLHttpRequest;
    if(req is null)
        throw new ScriptRuntimeException("Invalid XMLHttpRequest object");
    return ScriptAny(req._readyState);
}

private ScriptAny native_XMLHttpRequest_p_response(Environment env, ScriptAny* thisObj,
                                                   ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto req = thisObj.toNativeObject!ScriptXMLHttpRequest;
    if(req is null)
        throw new ScriptRuntimeException("Invalid XMLHttpRequest object");
    return ScriptAny(cast(string)req._response);
}

private ScriptAny native_XMLHttpRequest_send(Environment env, ScriptAny* thisObj,
                                             ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto req = thisObj.toNativeObject!ScriptXMLHttpRequest;
    if(req is null)
        throw new ScriptRuntimeException("Invalid XMLHttpRequest object");
    req._done = false;
    auto vm = env.g.interpreter.vm;
    if(req._async)
    {
        auto fiberFunc = new ScriptFunction("http", 
            function ScriptAny(Environment env, ScriptAny* thisObj,
                ScriptAny[] args, ref NativeFunctionError nfe) 
        {
            auto vm = env.g.interpreter.vm;
            auto request = thisObj.toNativeObject!ScriptXMLHttpRequest;
            auto tid = spawn({
                receive((shared ScriptXMLHttpRequest httpRequest)
                {
                    auto httpRequestUnshared = cast(ScriptXMLHttpRequest)httpRequest;
                    httpRequestUnshared._http.perform();
                    synchronized
                    {
                        if(httpRequestUnshared._readyState == ScriptXMLHttpRequest.ReadyState.LOADING)
                        {
                            httpRequestUnshared._readyState = ScriptXMLHttpRequest.ReadyState.DONE;
                            httpRequestUnshared._eventQueue ~= tuple(ScriptXMLHttpRequest.EventType.RS_CHANGE,
                                ScriptAny(ScriptXMLHttpRequest.ReadyState.DONE)); 
                        }
                    }
                    httpRequestUnshared._done = true;
                });
            });
            send(tid, cast(shared)request);

            while(!request._done)
            {
                synchronized(request)
                {
                    while(request._eventQueue != null)
                    {
                        ScriptXMLHttpRequest.Event event;
                        event = request._eventQueue[0];
                        request._eventQueue = request._eventQueue[1..$];
                        if(event[0] == ScriptXMLHttpRequest.EventType.RS_CHANGE)
                        {
                            // resync
                            request._readyState = cast(ScriptXMLHttpRequest.ReadyState)event[1].toValue!ushort;
                            if(request._onReadyStateChange)
                                vm.runFunction(request._onReadyStateChange, *thisObj, []);
                        }
                    }
                }
                yield();
            }

            if(request._eventQueue)
            {
                foreach(event ; request._eventQueue)
                {
                    if(event[0] == ScriptXMLHttpRequest.EventType.RS_CHANGE)
                    {
                        // resync
                        request._readyState = cast(ScriptXMLHttpRequest.ReadyState)event[1].toValue!ushort;
                        if(request._onReadyStateChange)
                            vm.runFunction(request._onReadyStateChange, *thisObj, []);
                    }
                }
                request._eventQueue = null;
            }

            return ScriptAny();
        }, false);

        vm.addFiber("http", fiberFunc, *thisObj, []);
    }
    else 
    {
        if(req._readyState != ScriptXMLHttpRequest.ReadyState.OPENED)
            throw new ScriptRuntimeException("Invalid ready state (not opened)");
        req._http.perform();
        if(req._readyState == ScriptXMLHttpRequest.ReadyState.LOADING)
        {
            req._readyState = ScriptXMLHttpRequest.ReadyState.DONE;
            if(req._onReadyStateChange)
            {
                vm.runFunction(req._onReadyStateChange, *thisObj, []);
            }   
        }
    }
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_XMLHttpRequest_setRequestHeader(Environment env, ScriptAny* thisObj,
                                                         ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto req = thisObj.toNativeObject!ScriptXMLHttpRequest;
    if(req is null)
        throw new ScriptRuntimeException("Invalid XMLHttpRequest object");
    if(args.length < 2)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    auto key = args[0].toString();
    auto value = args[1].toString();
    req._http.addRequestHeader(key, value);
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_XMLHttpRequest_p_status(Environment env, ScriptAny* thisObj,
                                               ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto req = thisObj.toNativeObject!ScriptXMLHttpRequest;
    if(req is null)
        throw new ScriptRuntimeException("Invalid XMLHttpRequest object");
    return ScriptAny(req._status);
}


