/**
This module implements the Promise class.

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
module mildew.stdlib.promise;

debug import std.stdio;

import mildew.environment;
import mildew.exceptions;
import mildew.interpreter;
import mildew.types;
import mildew.vm;

/**
 * Initializes the Promise class library.
 * Params:
 *  interpreter = The Interpreter instance to store the Promise constructor in.
 */
void initializePromiseLibrary(Interpreter interpreter)
{
    ScriptAny promiseCtor = new ScriptFunction("Promise", &native_Promise_ctor, true);
    promiseCtor["prototype"] = getPromisePrototype;
    promiseCtor["prototype"]["constructor"] = promiseCtor;
    promiseCtor["all"] = new ScriptFunction("Promise.all", &native_Promise_s_all);
    promiseCtor["reject"] = new ScriptFunction("Promise.reject", &native_Promise_s_reject);
    promiseCtor["resolve"] = new ScriptFunction("Promise.resolve", &native_Promise_s_resolve);

    interpreter.forceSetGlobal("Promise", promiseCtor, false);
}

private ScriptObject _promisePrototype;

/// get the promise prototype
private ScriptObject getPromisePrototype() 
{
    if(_promisePrototype is null)
    {
        _promisePrototype = new ScriptObject("Promise", null);
        _promisePrototype["catch"] = new ScriptFunction("Promise.prototype.catch", &native_Promise_catch);
        _promisePrototype["finally"] = new ScriptFunction("Promise.prototype.finally", &native_Promise_finally);
        _promisePrototype["then"] = new ScriptFunction("Promise.prototype.then", &native_Promise_then);
    }
    return _promisePrototype;
}

/// Promise class
private class ScriptPromise 
{
    /// The state of the promise
    enum State 
    {
        PENDING, RESOLVED, REJECTED, PROMISE
    }

    /// ctor
    this(VirtualMachine vm)
    {
        _vm = vm;
    }

private:

    int _deferredState = 0;
    State _state = State.PENDING;
    ScriptAny _value = ScriptAny.UNDEFINED;
    Handler[] _deferreds;
    VirtualMachine _vm;
}

private class Handler
{
    this(ScriptFunction onF, ScriptFunction onR, ScriptPromise p)
    {
        onFulfilled = onF;
        onRejected = onR;
        promise = p;
    }

    ScriptFunction onFulfilled;
    ScriptFunction onRejected;
    ScriptPromise promise;
}

// Helper functions

private void doResolve(ScriptFunction fn, ScriptPromise promise)
{
    ScriptAny resolver = new ScriptFunction("resolve", 
        delegate ScriptAny(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe){
            if(args.length < 1)
            {
                nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
                return ScriptAny.UNDEFINED;
            }
            resolve(promise, args[0]);
            return args[0];
        }
    );
    ScriptAny rejector = new ScriptFunction("rejector",
        delegate ScriptAny(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe){
            if(args.length < 1)
            {
                nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
                return ScriptAny.UNDEFINED;
            }
            reject(promise, args[0]);
            return args[0];
        }
    );
    try 
    {
        ScriptAny self = new ScriptObject("Promise", getPromisePrototype, promise);
        promise._vm.runFunction(fn, self, [resolver, rejector]);
    }
    catch(ScriptRuntimeException ex)
    {
        reject(promise, ScriptAny(ex.msg));
    }
}

private void finale(ScriptPromise promise)
{
    if(promise._deferredState == 1) 
    {
        foreach(deferred; promise._deferreds)
            handle(promise, deferred);
        promise._deferreds = [];
    }
    if(promise._deferredState == 2)
    {
        foreach(deferred ; promise._deferreds)
            handle(promise, deferred);
        promise._deferreds = null;
    }
}

private ScriptAny getThen(VirtualMachine vm, ScriptAny obj)
{
    auto then = obj.lookupField("then");
    if(then != ScriptAny.UNDEFINED)
        return then; // has to be field not property for now
    return ScriptAny.UNDEFINED;
}

private void handle(ScriptPromise promise, Handler deferred)
{
    while(promise._state == ScriptPromise.State.PROMISE)
    {
        promise = promise._value.toNativeObject!ScriptPromise;
    }

    if(promise._state == ScriptPromise.State.PENDING)
    {
        if(promise._deferredState == 0)
        {
            promise._deferredState = 1;
            promise._deferreds = [ deferred ];
            return;
        }
        if(promise._deferredState == 1)
        {
            promise._deferredState = 2;
            promise._deferreds ~= deferred;
            return;
        }
        promise._deferreds ~= deferred;
        return;
    }
    handleResolved(promise, deferred);
}

private void handleResolved(ScriptPromise promise, Handler deferred)
{
    auto fiberFunc = new ScriptFunction("resolver", 
        delegate ScriptAny(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe){
            auto callback = promise._state == ScriptPromise.State.RESOLVED 
                ? deferred.onFulfilled 
                : deferred.onRejected;
            if(callback is null)
            {
                if(promise._state == ScriptPromise.State.RESOLVED)
                    resolve(deferred.promise, promise._value);
                else
                    reject(deferred.promise, promise._value);
                return ScriptAny.UNDEFINED;
            }
            ScriptAny prom = new ScriptObject("Promise", getPromisePrototype, promise);
            try 
            {
                auto ret = promise._vm.runFunction(callback, prom, [promise._value]);
                resolve(deferred.promise, ret);
            }
            catch(ScriptRuntimeException ex)
            {
                reject(deferred.promise, ScriptAny(ex.msg));
            }
            return ScriptAny.UNDEFINED;
        }
    );
    ScriptAny self = new ScriptObject("Promise", getPromisePrototype, promise);
    promise._vm.addFiberFirst("Promise", fiberFunc, self, []);
}

private void resolve(ScriptPromise promise, ScriptAny newValue)
{
    if(newValue.toNativeObject!ScriptPromise is promise)
    {
        reject(promise, ScriptAny("A promise cannot be resolved with itself"));
        return;
    }
    if(newValue.isObject)
    {
        auto then = getThen(promise._vm, newValue); // @suppress(dscanner.suspicious.unmodified)
        if(then.type != ScriptAny.Type.FUNCTION)
        {
            // reject(promise, ScriptAny("No gettable then: " ~ then.toString ~ " of " ~ newValue.toString));
            // return;
        }
        if(newValue.isNativeObjectType!ScriptPromise)
        {
            promise._state = ScriptPromise.State.PROMISE;
            promise._value = newValue;
            finale(promise);
            return;
        }
        else if(then.type == ScriptAny.Type.FUNCTION)
        {
            auto thenFunc = then.toValue!ScriptFunction;
            auto copy = thenFunc.bindCopy(newValue);
            doResolve(copy, promise);
            return;
        }
    }
    promise._state = ScriptPromise.State.RESOLVED;
    promise._value = newValue;
    finale(promise);
}

private void reject(ScriptPromise promise, ScriptAny reason)
{
    promise._state = ScriptPromise.State.REJECTED;
    promise._value = reason;
    finale(promise);
}

private ScriptPromise valuePromise(Environment env, ScriptAny value)
{
    auto promise = new ScriptPromise(env.g.interpreter.vm);
    promise._state = ScriptPromise.State.RESOLVED;
    promise._value = value;
    return promise;
}

/**
 * Creates a new Promise with the constructor and wraps it in a ScriptAny. This overload takes a ScriptFunction
 */
ScriptAny newPromise(Environment env, ScriptFunction action)
{
    auto promise = new ScriptPromise(env.g.interpreter.vm);
    ScriptAny thisObj = new ScriptObject("Promise", getPromisePrototype, promise);
    NativeFunctionError nfe;
    native_Promise_ctor(env, &thisObj, [ScriptAny(action)], nfe);
    return thisObj;
}


private ScriptAny native_Promise_ctor(Environment env, ScriptAny* thisObj,
                                      ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(!thisObj.isObject)
        throw new ScriptRuntimeException("Promise must be constructed with new keyword");

    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    
    auto promise = new ScriptPromise(env.g.interpreter.vm);

    if(args[0].isNull)
    {
        thisObj.toValue!ScriptObject.nativeObject = promise;
        return ScriptAny.UNDEFINED;
    }

    if(args[0].type != ScriptAny.Type.FUNCTION)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    auto fn = args[0].toValue!ScriptFunction;

    thisObj.toValue!ScriptObject.nativeObject = promise;
    doResolve(fn, promise);

    return ScriptAny.UNDEFINED;
}

private ScriptAny native_Promise_s_all(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    if(!isIterable(args[0]))
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }

    ScriptAny[] promises = native_Array_s_from(env, thisObj, [args[0]], nfe).toValue!(ScriptAny[]);
    int numResolved = 0;
    ScriptAny[] results = new ScriptAny[promises.length];
    auto action = new ScriptFunction("Promise.all::action", delegate ScriptAny
        (Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe){
            auto resolver = args[0].toValue!ScriptFunction;
            auto rejector = args[1].toValue!ScriptFunction;
            for(auto i = 0; i < promises.length; ++i)
            {
                ScriptFunction createResolve(int index)
                {
                    return new ScriptFunction("Promise.all::each::resolve", delegate ScriptAny
                        (Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe) {
                            results[index] = args[0];
                            if(++numResolved == promises.length)
                                return env.g.interpreter.vm.runFunction(resolver, *thisObj, [ScriptAny(results)]);
                            return ScriptAny.UNDEFINED;
                        }
                    );
                }
                auto onResolve = createResolve(i);
                auto onReject = new ScriptFunction("Promise::all::each::reject", delegate ScriptAny
                    (Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe){
                        auto e = args.length > 0 ? args[0] : ScriptAny.UNDEFINED;
                        return env.g.interpreter.vm.runFunction(rejector, *thisObj, [e]);
                    }
                );
                auto promise = promises[i].toNativeObject!ScriptPromise;
                if(promise is null)
                    throw new ScriptRuntimeException("Thenables are not yet supported");
                native_Promise_then(env, &promises[i], [ScriptAny(onResolve), ScriptAny(onReject)], nfe);
                if(nfe != NativeFunctionError.NO_ERROR)
                    return ScriptAny.UNDEFINED;
            }
            return ScriptAny.UNDEFINED;
        }
    );

    return newPromise(env, action);
}

private ScriptAny native_Promise_catch(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    return native_Promise_then(env, thisObj, [ScriptAny(null), args[0]], nfe);
}

private ScriptAny native_Promise_finally(Environment env, ScriptAny* thisObj,
                                         ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    if(args[0].type != ScriptAny.Type.FUNCTION)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    auto f = args[0].toValue!ScriptFunction;
    ScriptAny onResolve = new ScriptFunction("finally_then", 
        delegate ScriptAny(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe){
            auto value = args[0];
            auto a = native_Promise_s_resolve(env, thisObj, [
                env.g.interpreter.vm.runFunction(f, *thisObj, [])
                ], nfe);
            auto then = new ScriptFunction("_then", delegate ScriptAny
                (Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe){
                    return value;
                }
            );
            return native_Promise_then(env, &a, [ScriptAny(then)], nfe);
        }
    );
    ScriptAny onReject = new ScriptFunction("finally_reject", 
        delegate ScriptAny(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe){
            auto err = args[0];
            auto a = native_Promise_s_resolve(env, thisObj, [
                env.g.interpreter.vm.runFunction(f, *thisObj, [])
            ], nfe);
            auto then = new ScriptFunction("_then", delegate ScriptAny
                (Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe){
                    throw new ScriptRuntimeException(err.toString());
                }
            );
            return native_Promise_then(env, &a, [ScriptAny(then)], nfe);
        }
    );
    return native_Promise_then(env, thisObj, [onResolve, onReject], nfe);
}

private ScriptAny native_Promise_s_reject(Environment env, ScriptAny* thisObj,
                                          ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto value = args.length > 0 ? args[0] : ScriptAny.UNDEFINED;
    auto action = new ScriptFunction("::action", delegate ScriptAny
        (Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe){
            auto rejector = args.length > 1 ? args[1].toValue!ScriptFunction() : null;
            if(!rejector) return ScriptAny.UNDEFINED;
            return env.g.interpreter.vm.runFunction(rejector, *thisObj, [value]);
        }
    );
    return newPromise(env, action);
}

private ScriptAny native_Promise_s_resolve(Environment env, ScriptAny* thisObj,
                                           ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny.UNDEFINED;
    if(args[0].isObject)
    {
        try 
        {
            auto then = args[0]["then"]; // only then fields supported
            if(then.type == ScriptAny.Type.FUNCTION)
            {
                return newPromise(env, then.toValue!ScriptFunction.bindCopy(args[0]));
            }
        }
        catch(ScriptRuntimeException ex)
        {
            auto action = new ScriptFunction("_action", delegate ScriptAny
                (Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe){
                    if(args.length < 2)
                        throw new ScriptRuntimeException("Impossible state");
                    auto reject = args[1].toValue!ScriptFunction;
                    if(reject is null)
                        throw new ScriptRuntimeException("Impossible state also");
                    return env.g.interpreter.vm.runFunction(reject, *thisObj, [ScriptAny(ex.msg)]);
                }
            );
            return newPromise(env, action);
        }
    }
    auto promise = valuePromise(env, args[0]);
    return ScriptAny(new ScriptObject("Promise", getPromisePrototype, promise));
}

private ScriptAny native_Promise_then(Environment env, ScriptAny* thisObj,
                                      ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto onFulfilled = args.length > 0 ? args[0] : ScriptAny(null);
    auto onRejected = args.length > 1 ? args[1] : ScriptAny(null);

    auto promise = thisObj.toNativeObject!ScriptPromise;
    if(promise is null)
    {
        throw new ScriptRuntimeException("Thenable support is not yet implemented");
    }

    auto res = new ScriptPromise(env.g.interpreter.vm);
    handle(promise, new Handler(onFulfilled.toValue!ScriptFunction,
        onRejected.toValue!ScriptFunction,
        res));
    return ScriptAny(new ScriptObject("Promise", getPromisePrototype, res));
}



