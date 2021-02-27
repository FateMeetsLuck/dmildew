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
import std.conv: to;
import std.net.curl;
debug import std.stdio;
import std.string: indexOf;
import std.typecons;
import std.uni: toLower;

import mildew.environment;
import mildew.exceptions;
import mildew.interpreter;
import mildew.stdlib.json;
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

private class ScriptXMLHttpRequest
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


    void checkResponseType()
    {
        try 
        {
            if((_status >= 200 && _status <= 299) && _readyState == ReadyState.DONE 
            && indexOf(_responseHeaders["content-type"], "application/json") != -1
            && _responseText.length > 0)
            {
                string text = cast(string)_responseText.dup;
                if(text[0] == '[')
                    _response = JSONReader.consumeArray(text);
                else if(text[0] == '{')
                    _response = JSONReader.consumeObject(text);
            }
            else
            {
                _response = ScriptAny(cast(string)_responseText);
            }
        } catch(Exception ex)
        {
            throw new ScriptRuntimeException(ex.msg);
        }       
    }

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
    Exception _exception;
    ushort _status;
    string[string] _responseHeaders;
    ScriptAny _response;
    ubyte[] _responseText; // just a string for now
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
        _XMLHttpRequestPrototype.addGetterProperty("onabort", new ScriptFunction(
                "XMLHttpRequest.prototype.onabort",
                &native_XMLHttpRequest_p_onabort));
        _XMLHttpRequestPrototype.addSetterProperty("onabort", new ScriptFunction(
                "XMLHttpRequest.prototype.onabort",
                &native_XMLHttpRequest_p_onabort));
        _XMLHttpRequestPrototype.addGetterProperty("onprogress", new ScriptFunction(
                "XMLHttpRequest.prototype.onprogress",
                &native_XMLHttpRequest_p_onprogress));
        _XMLHttpRequestPrototype.addSetterProperty("onprogress", new ScriptFunction(
                "XMLHttpRequest.prototype.onprogress",
                &native_XMLHttpRequest_p_onprogress));
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
                "XMLHttpRequest.prototype.response",
                &native_XMLHttpRequest_p_response));
        _XMLHttpRequestPrototype.addGetterProperty("responseText", new ScriptFunction(
                "XMLHttpRequest.prototype.responseText",
                &native_XMLHttpRequest_p_responseText));
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
    auto key = toLower(args[0].toString());
    if(key in req._responseHeaders)
        return ScriptAny(req._responseHeaders[key]);
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_XMLHttpRequest_p_onabort(Environment env, ScriptAny* thisObj,
                                                     ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto req = thisObj.toNativeObject!ScriptXMLHttpRequest;
    if(req is null)
        throw new ScriptRuntimeException("Invalid XMLHttpRequest object");
    if(args.length < 1)
    {
        if(req._onAbort)
            return ScriptAny(req._onProgress);
        else
            return ScriptAny(null);
    }
    if(args[0].type != ScriptAny.Type.FUNCTION)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    req._onAbort = args[0].toValue!ScriptFunction;
    return args[0];
}

private ScriptAny native_XMLHttpRequest_p_onprogress(Environment env, ScriptAny* thisObj,
                                                     ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto req = thisObj.toNativeObject!ScriptXMLHttpRequest;
    if(req is null)
        throw new ScriptRuntimeException("Invalid XMLHttpRequest object");
    if(args.length < 1)
    {
        if(req._onProgress)
            return ScriptAny(req._onProgress);
        else
            return ScriptAny(null);
    }
    if(args[0].type != ScriptAny.Type.FUNCTION)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    req._onProgress = args[0].toValue!ScriptFunction;
    return args[0];
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
    req._done = false;
    req._abort = false;
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
    case "HEAD":
        req._http.method = HTTP.Method.head;
        break;
    case "PATCH":
        req._http.method = HTTP.Method.patch;
        break;
    case "OPTIONS":
        req._http.method = HTTP.Method.options;
        break;
    case "TRACE":
        req._http.method = HTTP.Method.trace;
        break;
    case "CONNECT":
        req._http.method = HTTP.Method.connect;
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
        synchronized(req)
        {
            req._status = line.code;
        }
    };

    req._http.onReceive = (ubyte[] data) {
        import core.thread: Thread;

        if(req._responseText.length == 0)
        {
            if(!req._async)
            {
                req._readyState = ScriptXMLHttpRequest.ReadyState.HEADERS_RECEIVED;
                if(req._onReadyStateChange)
                    vm.runFunction(req._onReadyStateChange, *thisObj, []);
            }
            else
            {
                synchronized(req)
                {
                    req._readyState = ScriptXMLHttpRequest.ReadyState.HEADERS_RECEIVED;
                    req._eventQueue ~= tuple(ScriptXMLHttpRequest.EventType.RS_CHANGE, 
                            ScriptAny(ScriptXMLHttpRequest.ReadyState.HEADERS_RECEIVED));
                }
            }
        }
        req._responseText ~= data;
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
                synchronized(req)
                {
                    req._eventQueue ~= tuple(ScriptXMLHttpRequest.EventType.RS_CHANGE, 
                        ScriptAny(ScriptXMLHttpRequest.ReadyState.LOADING));
                }
            }
        }

        return data.length;
    };

    req._http.onProgress = (size_t dlTotal, size_t dlNow, size_t ulTotal, size_t ulNow) {
        synchronized(req)
        {
            ScriptObject event = new ScriptObject(
                req._abort ? "AbortEvent" : "LoadEvent", 
                null);
            event["loaded"] = ScriptAny(dlNow);
            event["total"] = ScriptAny(dlTotal);
            event["lengthComputable"] = dlTotal == 0 ? ScriptAny(false) : ScriptAny(true);
            if(!req._async)
            {
                if(req._abort)
                {
                    if(req._onAbort)
                        vm.runFunction(req._onAbort, *thisObj, [ScriptAny(event)]);
                }
                else if(req._onProgress)
                    vm.runFunction(req._onProgress, *thisObj, [ScriptAny(event)]);
            }
            else
            {
                if(req._abort)
                {
                    req._eventQueue ~= tuple(ScriptXMLHttpRequest.EventType.ABORT,
                        ScriptAny(event));
                }
                else req._eventQueue ~= tuple(ScriptXMLHttpRequest.EventType.PROGRESS,
                    ScriptAny(event));
            }

            if(req._abort)
            {    
                return HTTP.requestAbort;
            }
        }
        return 0;
    };

    req._http.onReceiveHeader = (in char[] key, in char[] value) {
        synchronized(req) 
        {
            req._responseHeaders[toLower(key)] = value.idup;
        }
    };

    req._http.onSend = (void[] data) { // this is never called even with send params
        if(req._abort)
        {
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
        synchronized(req)
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
    return ScriptAny(req._response);
}

private ScriptAny native_XMLHttpRequest_p_responseText(Environment env, ScriptAny* thisObj,
                                                   ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto req = thisObj.toNativeObject!ScriptXMLHttpRequest;
    if(req is null)
        throw new ScriptRuntimeException("Invalid XMLHttpRequest object");
    return ScriptAny(cast(string)req._responseText);
}

private ScriptAny native_XMLHttpRequest_send(Environment env, ScriptAny* thisObj,
                                             ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.string: indexOf;
    
    auto req = thisObj.toNativeObject!ScriptXMLHttpRequest;
    if(req is null)
        throw new ScriptRuntimeException("Invalid XMLHttpRequest object");
    req._done = false;
    auto vm = env.g.interpreter.vm;
    if(args.length > 0)
    {
        auto content = args[0].toString();
        req._http.setPostData(content, "text/plain");
    }
    if(req._async)
    {
        auto fiberFunc = new ScriptFunction("http", 
            function ScriptAny(Environment env, ScriptAny* thisObj,
                ScriptAny[] args, ref NativeFunctionError nfe) 
        {
            import core.thread: Thread;
            auto vm = env.g.interpreter.vm;
            auto request = thisObj.toNativeObject!ScriptXMLHttpRequest;
            auto tid = spawn({
                receive((shared ScriptXMLHttpRequest httpRequest)
                {
                    auto httpRequestUnshared = cast(ScriptXMLHttpRequest)httpRequest;
                    try 
                    {
                        httpRequestUnshared._http.perform();
                        synchronized(httpRequestUnshared)
                        {
                            httpRequestUnshared._readyState = ScriptXMLHttpRequest.ReadyState.DONE;
                            httpRequestUnshared._eventQueue ~= tuple(ScriptXMLHttpRequest.EventType.RS_CHANGE,
                                    ScriptAny(ScriptXMLHttpRequest.ReadyState.DONE)); 
                            httpRequestUnshared._done = true;
                        }
                    }
                    catch(CurlException cex)
                    {
                        synchronized(httpRequestUnshared)
                        {
                            httpRequestUnshared._done = true;
                        }
                    } 
                    catch(Exception ex)
                    {
                        synchronized(httpRequestUnshared)
                        {
                            httpRequestUnshared._exception = ex;
                        }
                    }
                });
            });
            send(tid, cast(shared)request);

            ScriptXMLHttpRequest.Event[] deferredEvents;
            while(!request._done && request._exception is null)
            {
                synchronized(request)
                {
                    if(request._eventQueue.length > 0)
                    {
                        auto event = request._eventQueue[0];
                        request._eventQueue = request._eventQueue[1..$];
                        if(event[0] == ScriptXMLHttpRequest.EventType.PROGRESS)
                        {
                            if(request._onProgress)
                                vm.runFunction(request._onProgress, *thisObj, [event[1]]);
                        }
                        else if(event[0] == ScriptXMLHttpRequest.EventType.ABORT)
                        {
                            if(request._onAbort)
                                vm.runFunction(request._onAbort, *thisObj, [event[1]]);
                        }
                        else
                        {
                            deferredEvents ~= event;
                        }
                    }
                }
                yield();
            }

            deferredEvents ~= request._eventQueue;

            if(request._exception !is null)
                throw new ScriptRuntimeException(request._exception.msg);

            if(deferredEvents.length > 0)
            {
                foreach(event ; deferredEvents)
                {
                    if(event[0] == ScriptXMLHttpRequest.EventType.RS_CHANGE)
                    {
                        // resync
                        request._readyState = cast(ScriptXMLHttpRequest.ReadyState)event[1].toValue!ushort;
                        request.checkResponseType();
                        if(request._onReadyStateChange)
                            vm.runFunction(request._onReadyStateChange, *thisObj, []);
                    }
                }
                deferredEvents = null;
            }

            return ScriptAny();
        }, false);

        vm.addFiber("http", fiberFunc, *thisObj, []);
    }
    else 
    {
        if(req._readyState != ScriptXMLHttpRequest.ReadyState.OPENED)
            throw new ScriptRuntimeException("Invalid ready state (not opened)");
        try 
        {
            req._http.perform();
        }
        catch(CurlException ex)
        {
            if(indexOf(ex.msg, "aborted") != -1)
            {
                if(req._onAbort)
                {
                    auto event = new ScriptObject("AbortEvent", null);
                    event["lengthComputable"] = ScriptAny(false);
                    event["loaded"] = ScriptAny(req._responseText.length);
                    event["total"] = ScriptAny(0);
                    vm.runFunction(req._onAbort, *thisObj, [ScriptAny(event)]);
                }
                return ScriptAny.UNDEFINED;
             }
             else throw new ScriptRuntimeException(ex.msg);
        }
        catch(Exception ex)
        {
            throw new ScriptRuntimeException(ex.msg);
        }
        req.checkResponseType();
        if(req._readyState == ScriptXMLHttpRequest.ReadyState.LOADING)
        {
            req._readyState = ScriptXMLHttpRequest.ReadyState.DONE;
            req.checkResponseType();
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


