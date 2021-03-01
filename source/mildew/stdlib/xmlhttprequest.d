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
import mildew.stdlib.buffers;
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
        LOADSTART,
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
            if(_readyState == ReadyState.DONE && "content-type" in _responseHeaders)
            {
                immutable mimeType = _overriddenMimeType != "" ? _overriddenMimeType : _responseHeaders["content-type"];
                if(indexOf(mimeType, "json") != -1)
                {
                    _response = JSONReader.consumeValue(cast(string)_responseText);
                }
                else if(indexOf(mimeType, "text/") != - 1)
                {
                    _response = ScriptAny(cast(string)_responseText);
                }
                else
                {
                    _response = ScriptAny(
                        new ScriptObject("ArrayBuffer",
                            getArrayBufferPrototype(), 
                            new ScriptArrayBuffer(_responseText)));
                }
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
    bool _started = false;
    long _timeout = 0;
    string _overriddenMimeType = "";

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
        _XMLHttpRequestPrototype.addGetterProperty("onerror", new ScriptFunction(
                "XMLHttpRequest.prototype.onerror",
                &native_XMLHttpRequest_p_onerror));
        _XMLHttpRequestPrototype.addSetterProperty("onerror", new ScriptFunction(
                "XMLHttpRequest.prototype.onerror",
                &native_XMLHttpRequest_p_onerror));
        _XMLHttpRequestPrototype.addGetterProperty("onload", new ScriptFunction(
                "XMLHttpRequest.prototype.onload",
                &native_XMLHttpRequest_p_onload));
        _XMLHttpRequestPrototype.addSetterProperty("onload", new ScriptFunction(
                "XMLHttpRequest.prototype.onload",
                &native_XMLHttpRequest_p_onload));
        _XMLHttpRequestPrototype.addGetterProperty("onloadend", new ScriptFunction(
                "XMLHttpRequest.prototype.onloadend",
                &native_XMLHttpRequest_p_onloadend));
        _XMLHttpRequestPrototype.addSetterProperty("onloadend", new ScriptFunction(
                "XMLHttpRequest.prototype.onloadend",
                &native_XMLHttpRequest_p_onloadend));
        _XMLHttpRequestPrototype.addGetterProperty("onloadstart", new ScriptFunction(
                "XMLHttpRequest.prototype.onloadstart",
                &native_XMLHttpRequest_p_onloadstart));
        _XMLHttpRequestPrototype.addSetterProperty("onloadstart", new ScriptFunction(
                "XMLHttpRequest.prototype.onloadstart",
                &native_XMLHttpRequest_p_onloadstart));
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
        _XMLHttpRequestPrototype.addGetterProperty("ontimeout", new ScriptFunction(
                "XMLHttpRequest.prototype.ontimeout",
                &native_XMLHttpRequest_p_ontimeout));
        _XMLHttpRequestPrototype.addSetterProperty("ontimeout", new ScriptFunction(
                "XMLHttpRequest.prototype.ontimeout",
                &native_XMLHttpRequest_p_ontimeout));
        _XMLHttpRequestPrototype["open"] = new ScriptFunction("XMLHttpRequest.prototype.open",
                &native_XMLHttpRequest_open);
        _XMLHttpRequestPrototype["overrideMimeType"] = new ScriptFunction("XMLHttpRequest.prototype.overrideMimeType",
                &native_XMLHttpRequest_overrideMimeType);
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
        _XMLHttpRequestPrototype.addGetterProperty("timeout", new ScriptFunction(
                "XMLHttpRequest.prototype.timeout",
                &native_XMLHttpRequest_p_timeout));
        _XMLHttpRequestPrototype.addSetterProperty("timeout", new ScriptFunction(
                "XMLHttpRequest.prototype.timeout",
                &native_XMLHttpRequest_p_timeout));
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
            return ScriptAny(req._onAbort);
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

private ScriptAny native_XMLHttpRequest_p_onerror(Environment env, ScriptAny* thisObj,
                                                     ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto req = thisObj.toNativeObject!ScriptXMLHttpRequest;
    if(req is null)
        throw new ScriptRuntimeException("Invalid XMLHttpRequest object");
    if(args.length < 1)
    {
        if(req._onError)
            return ScriptAny(req._onError);
        else
            return ScriptAny(null);
    }
    if(args[0].type != ScriptAny.Type.FUNCTION)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    req._onError = args[0].toValue!ScriptFunction;
    return args[0];
}

private ScriptAny native_XMLHttpRequest_p_onload(Environment env, ScriptAny* thisObj,
                                                     ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto req = thisObj.toNativeObject!ScriptXMLHttpRequest;
    if(req is null)
        throw new ScriptRuntimeException("Invalid XMLHttpRequest object");
    if(args.length < 1)
    {
        if(req._onLoad)
            return ScriptAny(req._onLoad);
        else
            return ScriptAny(null);
    }
    if(args[0].type != ScriptAny.Type.FUNCTION)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    req._onLoad = args[0].toValue!ScriptFunction;
    return args[0];
}

private ScriptAny native_XMLHttpRequest_p_onloadend(Environment env, ScriptAny* thisObj,
                                                     ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto req = thisObj.toNativeObject!ScriptXMLHttpRequest;
    if(req is null)
        throw new ScriptRuntimeException("Invalid XMLHttpRequest object");
    if(args.length < 1)
    {
        if(req._onLoadEnd)
            return ScriptAny(req._onLoadEnd);
        else
            return ScriptAny(null);
    }
    if(args[0].type != ScriptAny.Type.FUNCTION)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    req._onLoadEnd = args[0].toValue!ScriptFunction;
    return args[0];
}

private ScriptAny native_XMLHttpRequest_p_onloadstart(Environment env, ScriptAny* thisObj,
                                                     ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto req = thisObj.toNativeObject!ScriptXMLHttpRequest;
    if(req is null)
        throw new ScriptRuntimeException("Invalid XMLHttpRequest object");
    if(args.length < 1)
    {
        if(req._onLoadStart)
            return ScriptAny(req._onLoadStart);
        else
            return ScriptAny(null);
    }
    if(args[0].type != ScriptAny.Type.FUNCTION)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    req._onLoadStart = args[0].toValue!ScriptFunction;
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

private ScriptAny native_XMLHttpRequest_p_ontimeout(Environment env,
                                                    ScriptAny* thisObj,
                                                    ScriptAny[] args,
                                                    ref NativeFunctionError nfe)
{
    auto req = thisObj.toNativeObject!ScriptXMLHttpRequest;
    if(req is null)
        throw new ScriptRuntimeException("Invalid XMLHttpRequest object");
    if(args.length < 1)
    {
        if(req._onTimeout)
            return ScriptAny(req._onTimeout);
        else
            return ScriptAny(null);
    }
    if(args[0].type != ScriptAny.Type.FUNCTION)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    req._onTimeout = args[0].toValue!ScriptFunction;
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
                "ProgressEvent", 
                null);
            event["loaded"] = ScriptAny(dlNow);
            event["total"] = ScriptAny(dlTotal);
            event["lengthComputable"] = dlTotal == 0 ? ScriptAny(false) : ScriptAny(true);
            if(!req._async)
            {
                if(req._onLoadStart && req._started)
                {
                    req._started = false;
                    vm.runFunction(req._onLoadStart, *thisObj, [ScriptAny(event)]);
                }

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
                if(req._started)
                {
                    req._started = false;
                    req._eventQueue ~= tuple(ScriptXMLHttpRequest.EventType.LOADSTART,
                        ScriptAny(event));
                }
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

private ScriptAny native_XMLHttpRequest_overrideMimeType(Environment env, ScriptAny* thisObj,
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
    req._overriddenMimeType = args[0].toString();
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
    req._started = true;
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
                            
                            auto loadedEvent = new ScriptObject("ProgressEvent", null);
                            loadedEvent["lengthComputable"] = ScriptAny(true);
                            loadedEvent["loaded"] = ScriptAny(httpRequestUnshared._responseText.length);
                            loadedEvent["total"] = ScriptAny(httpRequestUnshared._responseText.length);
                            httpRequestUnshared._eventQueue ~= tuple(ScriptXMLHttpRequest.EventType.LOAD,
                                    ScriptAny(loadedEvent));

                            httpRequestUnshared._eventQueue ~= tuple(ScriptXMLHttpRequest.EventType.LOADEND,
                                    ScriptAny(loadedEvent));
                            
                            httpRequestUnshared._done = true;
                        }
                    }
                    catch(CurlException cex)
                    {
                        synchronized(httpRequestUnshared)
                        {
                            if(indexOf(cex.msg, "aborted") == -1)
                            {
                                auto event = new ScriptObject("ProgressEvent", null);
                                event["lengthComputable"] = ScriptAny(false);
                                event["loaded"] = ScriptAny(httpRequestUnshared._responseText.length);
                                event["total"] = ScriptAny(0);
                                httpRequestUnshared._eventQueue ~= tuple(ScriptXMLHttpRequest.EventType.ERROR,
                                        ScriptAny(event));
                                httpRequestUnshared._eventQueue ~= tuple(ScriptXMLHttpRequest.EventType.LOADEND,
                                        ScriptAny(event));
                                if(indexOf(cex.msg, "Timeout") != -1)
                                {
                                    httpRequestUnshared._eventQueue ~= tuple(ScriptXMLHttpRequest.EventType.TIMEOUT,
                                        ScriptAny(event));
                                }
                            }
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
                        else if(event[0] == ScriptXMLHttpRequest.EventType.ERROR)
                        {
                            if(request._onError)
                                vm.runFunction(request._onError, *thisObj, [event[1]]);
                        }
                        else if(event[0] == ScriptXMLHttpRequest.EventType.LOADEND)
                        {
                            if(request._onLoadEnd)
                                vm.runFunction(request._onLoadEnd, *thisObj, [event[1]]);
                        }
                        else if(event[0] == ScriptXMLHttpRequest.EventType.LOADSTART)
                        {
                            if(request._onLoadStart)
                                vm.runFunction(request._onLoadStart, *thisObj, [event[1]]);
                        }
                        else if(event[0] == ScriptXMLHttpRequest.EventType.TIMEOUT)
                        {
                            if(request._onTimeout)
                                vm.runFunction(request._onTimeout, *thisObj, [event[1]]);
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
                    else if(event[0] == ScriptXMLHttpRequest.EventType.LOAD)
                    {
                        if(request._onLoad)
                            vm.runFunction(request._onLoad, *thisObj, [event[1]]);
                    }
                    else if(event[0] == ScriptXMLHttpRequest.EventType.LOADEND)
                    {
                        if(request._onLoadEnd)
                            vm.runFunction(request._onLoadEnd, *thisObj, [event[1]]);
                    }
                    else if(event[0] == ScriptXMLHttpRequest.EventType.ERROR)
                    {
                        if(request._onError)
                            vm.runFunction(request._onError, *thisObj, [event[1]]);
                    }
                    else if(event[0] == ScriptXMLHttpRequest.EventType.TIMEOUT)
                    {
                        if(request._onTimeout)
                            vm.runFunction(request._onTimeout, *thisObj, [event[1]]);
                    }
                    /*else if(event[0] == ScriptXMLHttpRequest.EventType.PROGRESS)
                    {
                        if(request._onProgress)
                            vm.runFunction(request._onProgress, *thisObj, [event[1]]);
                    }
                    else if(event[0] == ScriptXMLHttpRequest.EventType.ABORT)
                    {
                        if(request._onAbort)
                            vm.runFunction(request._onAbort, *thisObj, [event[1]]);
                    }
                    */
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
            auto event = new ScriptObject(
                "ProgressEvent", 
                null
            );
            event["lengthComputable"] = ScriptAny(false);
            event["loaded"] = ScriptAny(req._responseText.length);
            event["total"] = ScriptAny(0);
            if(indexOf(ex.msg, "aborted") != -1)
            {
                if(req._onAbort)
                {
                    vm.runFunction(req._onAbort, *thisObj, [ScriptAny(event)]);
                }
                if(req._onLoadEnd)
                {
                    vm.runFunction(req._onLoadEnd, *thisObj, [ScriptAny(event)]);
                }
             }
             else
             {
                if(indexOf(ex.msg, "Timeout") != -1 && req._onTimeout)
                {
                    vm.runFunction(req._onTimeout, *thisObj, [ScriptAny(event)]);
                }
                else if(req._onError)
                {
                    vm.runFunction(req._onError, *thisObj, [ScriptAny(event)]);
                }
             }
            return ScriptAny.UNDEFINED;
        }
        catch(Exception ex)
        {
            throw new ScriptRuntimeException(ex.msg);
        }
        req.checkResponseType();
        if(req._readyState == ScriptXMLHttpRequest.ReadyState.LOADING)
        {
            auto event = new ScriptObject("ProgressEvent", null);
            event["lengthComputable"] = ScriptAny(true);
            event["loaded"] = ScriptAny(req._responseText.length);
            event["total"] = ScriptAny(req._responseText.length);
            req._readyState = ScriptXMLHttpRequest.ReadyState.DONE;
            req.checkResponseType();
            if(req._onReadyStateChange)
            {
                vm.runFunction(req._onReadyStateChange, *thisObj, []);
            }
            if(req._onLoad)
            {
                vm.runFunction(req._onLoad, *thisObj, [ScriptAny(event)]);
            }
            if(req._onLoadEnd)
            {
                vm.runFunction(req._onLoadEnd, *thisObj, [ScriptAny(event)]);
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

private ScriptAny native_XMLHttpRequest_p_timeout(Environment env, ScriptAny* thisObj,
                                                  ScriptAny[] args, ref NativeFunctionError nfe)
{
    import core.time: dur;

    auto req = thisObj.toNativeObject!ScriptXMLHttpRequest;
    if(args.length > 0)
    {
        try 
        {
            immutable timeout = args[0].toValue!long;
            req._timeout = timeout;
            req._http.operationTimeout(dur!"msecs"(timeout));
        }
        catch(CurlException ex)
        {
            throw new ScriptRuntimeException("Must call open before setting timeout");
        }
    }
    return ScriptAny(req._timeout);
}

