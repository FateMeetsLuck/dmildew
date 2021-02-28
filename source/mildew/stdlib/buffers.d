/**
This module implements the ArrayBuffer and its associated views.

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
module mildew.stdlib.buffers;

import std.format;

import mildew.environment;
import mildew.exceptions;
import mildew.interpreter;
import mildew.types;

/**
 * Initializes the ArrayBuffer and its views library.
 * Params:
 *  interpreter = The Interpreter instance to load this library into
 */
void initializeBuffersLibrary(Interpreter interpreter)
{
    ScriptAny arrayBufferCtor = new ScriptFunction("ArrayBuffer", &native_ArrayBuffer_ctor);
    arrayBufferCtor["prototype"] = getArrayBufferPrototype();
    arrayBufferCtor["prototype"]["constructor"] = arrayBufferCtor;
    interpreter.forceSetGlobal("ArrayBuffer", arrayBufferCtor, false);

    mixin(SET_CONSTRUCTOR!(Int8Array));
    mixin(SET_CONSTRUCTOR!(Uint8Array));
    mixin(SET_CONSTRUCTOR!(Int16Array));
    mixin(SET_CONSTRUCTOR!(Uint16Array));
    mixin(SET_CONSTRUCTOR!(Int32Array));
    mixin(SET_CONSTRUCTOR!(Uint32Array));
    mixin(SET_CONSTRUCTOR!(Float32Array));
    mixin(SET_CONSTRUCTOR!(Float64Array));
    mixin(SET_CONSTRUCTOR!(BigInt64Array));
    mixin(SET_CONSTRUCTOR!(BigUint64Array));
}

private string SET_CONSTRUCTOR(A)()
{
    return format(q{
        ScriptAny a%1$sCtor = new ScriptFunction("%1$s", &native_TArray_ctor!(%1$s));
        a%1$sCtor["BYTES_PER_ELEMENT"] = ScriptAny((typeof(%1$s.data[0]).sizeof));
        a%1$sCtor["prototype"] = get%1$sPrototype();
        a%1$sCtor["prototype"]["constructor"] = a%1$sCtor;
        interpreter.forceSetGlobal("%1$s", a%1$sCtor, false);
    }, A.stringof);
}

/**
 * Base class
 */
abstract class AbstractArrayBuffer
{
    /// Constructor
    this(Type t)
    {
        _type = t;
    }

    /// An optimized RTTI
    enum Type 
    {
        ARRAY_BUFFER, // untyped view
        INT8_ARRAY,
        UINT8_ARRAY,
        INT16_ARRAY,
        UINT16_ARRAY,
        INT32_ARRAY,
        UINT32_ARRAY,
        FLOAT32_ARRAY,
        FLOAT64_ARRAY,
        BIGINT64_ARRAY,
        BIGUINT64_ARRAY
    }

    abstract long getIndex(long index); // convert -1 to appropriate index

    /// read-only type property
    auto type() const { return _type; }

    private Type _type;

    /// whether or not the instance is a view or read-only
    bool isView() const { return _type != Type.ARRAY_BUFFER; }

    override string toString() const
    {
        throw new Exception("Each base class is supposed to override toString");
    }
}

/// ArrayBuffer
class ScriptArrayBuffer : AbstractArrayBuffer
{
    /// constructor
    this(size_t length)
    {
        super(Type.ARRAY_BUFFER);
        data = new ubyte[length];
    }

    /// construct from binary data
    this(ubyte[] rawBytes)
    {
        super(Type.ARRAY_BUFFER);
        data = rawBytes;
    }

    override long getIndex(long index) const { return -1; }

    /// read-only data
    ubyte[] data;

    override string toString() const
    {
        return format("%s", data);
    }
}


private ScriptObject _arrayBufferPrototype;

/// Gets the ArrayBuffer prototype
ScriptObject getArrayBufferPrototype()
{
    if(_arrayBufferPrototype is null)
    {
        _arrayBufferPrototype = new ScriptObject("ArrayBuffer", null);
        _arrayBufferPrototype["isView"] = new ScriptFunction("ArrayBuffer.protototype.isView",
                &native_TArray_isView!ScriptArrayBuffer);
    }
    return _arrayBufferPrototype;
}

/// macro for defining all the subtypes
private string DEFINE_BUFFER_VIEW(string className, AbstractArrayBuffer.Type t, alias ElementType)()
{
    import std.conv: to;
    return format(q{
class %1$s : AbstractArrayBuffer
{
    import std.conv: to;
    this(size_t length)
    {
        super(%2$s);
        data = new %3$s[length];
    }

    override long getIndex(long index) const 
    {
        if(index < 0)
            index = data.length + index;
        if(index < 0 || index >= data.length)
            return -1;
        return index;      
    }

    override string toString() const 
    {
        return to!string(data);
    }

    size_t byteOffset;
    %3$s[] data;
}

private ScriptObject _a%1$sPrototype;
ScriptObject get%1$sPrototype() 
{
    if(_a%1$sPrototype is null)
    {
        _a%1$sPrototype = new ScriptObject("%1$s", null);
        _a%1$sPrototype.addGetterProperty("buffer", new ScriptFunction("%1$s.prototype.buffer",
                &native_TArray_p_buffer!%1$s));
        _a%1$sPrototype.addGetterProperty("byteLength", new ScriptFunction("%1$s.prototype.byteLength",
                &native_TArray_p_byteLength!%1$s));
        _a%1$sPrototype.addGetterProperty("byteOffset", new ScriptFunction("%1$s.prototype.byteOffset",
                &native_TArray_p_byteOffset!%1$s));
        _a%1$sPrototype["isView"] = new ScriptFunction("%1$s.prototype.isView",
                &native_TArray_isView!%1$s);
        _a%1$sPrototype.addGetterProperty("length", new ScriptFunction("%1$s.prototype.length",
                &native_TArray_p_length!%1$s));
    }
    return _a%1$sPrototype;
}

    }, className, t.stringof, ElementType.stringof);
}

mixin(DEFINE_BUFFER_VIEW!("Int8Array", AbstractArrayBuffer.Type.INT8_ARRAY, byte));
mixin(DEFINE_BUFFER_VIEW!("Uint8Array", AbstractArrayBuffer.Type.UINT8_ARRAY, ubyte));
mixin(DEFINE_BUFFER_VIEW!("Int16Array", AbstractArrayBuffer.Type.INT16_ARRAY, short));
mixin(DEFINE_BUFFER_VIEW!("Uint16Array", AbstractArrayBuffer.Type.UINT16_ARRAY, ushort));
mixin(DEFINE_BUFFER_VIEW!("Int32Array", AbstractArrayBuffer.Type.INT32_ARRAY, int));
mixin(DEFINE_BUFFER_VIEW!("Uint32Array", AbstractArrayBuffer.Type.UINT32_ARRAY, uint));
mixin(DEFINE_BUFFER_VIEW!("Float32Array", AbstractArrayBuffer.Type.FLOAT32_ARRAY, float));
mixin(DEFINE_BUFFER_VIEW!("Float64Array", AbstractArrayBuffer.Type.FLOAT64_ARRAY, double));
mixin(DEFINE_BUFFER_VIEW!("BigInt64Array", AbstractArrayBuffer.Type.BIGINT64_ARRAY, long));
mixin(DEFINE_BUFFER_VIEW!("BigUint64Array", AbstractArrayBuffer.Type.BIGUINT64_ARRAY, ulong));

private ScriptAny native_ArrayBuffer_ctor(Environment env, ScriptAny* thisObj,
                                          ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(!thisObj.isObject)
        throw new ScriptRuntimeException("ArrayBuffer constructor must be called with new");
    size_t size = args.length > 0 ? args[0].toValue!size_t : 0;
    auto arrayBuffer = new ScriptArrayBuffer(size);
    thisObj.toValue!ScriptObject.nativeObject = arrayBuffer;
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_TArray_ctor(A)
                                    (Environment env, ScriptAny* thisObj,
                                     ScriptAny[] args, ref NativeFunctionError nfe)
{
    import mildew.types.bindings: isIterable, native_Array_s_from;
    alias E = typeof(A.data[0]);

    if(!thisObj.isObject)
        throw new ScriptRuntimeException(A.stringof ~ " constructor must be called with new");
    if(args.length < 1)
    {
        thisObj.toValue!ScriptObject.nativeObject = new A(0);
    }
    else if(args[0].isNumber)
    {
        size_t size = args.length > 0 ? args[0].toValue!size_t : 0;
        auto a = new A(size);
        thisObj.toValue!ScriptObject.nativeObject = a;
    }
    else if(args[0].isNativeObjectType!ScriptArrayBuffer)
    {
        auto arrayBuffer = args[0].toNativeObject!ScriptArrayBuffer;
        if(arrayBuffer.data.length == 0)
        {
            thisObj.toValue!ScriptObject.nativeObject = new A(0);
            return ScriptAny.UNDEFINED;
        }

        auto offset = args.length > 1 ? args[1].toValue!size_t : 0;
        if(offset >= arrayBuffer.data.length)
            offset = 0;
        auto data = arrayBuffer.data[offset..$];
        size_t plusOne = data.length % E.sizeof == 0 ? 0 : 1;

        auto a = new A(data.length / E.sizeof + plusOne * E.sizeof);
        a.byteOffset = offset;
        static if(is(A==Uint8Array))
            a.data = data;
        else 
            a.data = (cast(E*)data.ptr)[0..data.length/E.sizeof];
        thisObj.toValue!ScriptObject.nativeObject = a;
    }
    else if(isIterable(args[0]))
    {
        auto arr = native_Array_s_from(env, thisObj, [args[0]], nfe).toValue!(ScriptAny[]);
        auto a = new A(arr.length);
        for(auto i = 0; i < arr.length; ++i)
        {
            a.data[i] = arr[i].toValue!E;
        }
        thisObj.toValue!ScriptObject.nativeObject = a;
    }
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_TArray_p_buffer(A)(Environment env, ScriptAny* thisObj,
                                            ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto a  = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    alias E = typeof(A.data[0]);
    auto arrayBuffer = new ScriptArrayBuffer((cast(ubyte*)a.data.ptr)[0..E.sizeof*a.data.length]);
    return ScriptAny(new ScriptObject("ArrayBuffer", getArrayBufferPrototype, arrayBuffer));
}

private ScriptAny native_TArray_p_byteLength(A)(Environment env, ScriptAny* thisObj,
                                                ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    alias E = typeof(A.data[0]);
    return ScriptAny(a.data.length * E.sizeof);
}

private ScriptAny native_TArray_p_byteOffset(A)(Environment env, ScriptAny* thisObj,
                                                ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    return ScriptAny(a.byteOffset);
}

private ScriptAny native_TArray_isView(A)(Environment env, ScriptAny* thisObj,
                                          ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    return ScriptAny(a.isView());
}

private ScriptAny native_TArray_p_length(A)(Environment env, ScriptAny* thisObj,
                                            ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    return ScriptAny(a.data.length);
}

