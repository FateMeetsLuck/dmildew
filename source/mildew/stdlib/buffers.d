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
import mildew.stdlib.generator;
import mildew.types;

/**
 * Initializes the ArrayBuffer and its views library.
 * Params:
 *  interpreter = The Interpreter instance to load this library into
 */
void initializeBuffersLibrary(Interpreter interpreter)
{
    ScriptAny arrayBufferCtor = new ScriptFunction("ArrayBuffer", &native_ArrayBuffer_ctor);
    arrayBufferCtor["isView"] = new ScriptFunction("ArrayBuffer.isView", &native_ArrayBuffer_s_isView);
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
        a%1$sCtor["name"] = ScriptAny("%1$s");
        a%1$sCtor["isView"] = new ScriptFunction("%1$s.isView", &native_TArray_s_isView!%1$s);
        a%1$sCtor["from"] = new ScriptFunction("%1$s.from", &native_TArray_s_from!%1$s);
        a%1$sCtor["of"] = new ScriptFunction("%1$s.of", &native_TArray_s_of!%1$s);
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
        _arrayBufferPrototype.addGetterProperty("byteLength", new ScriptFunction(
            "ArrayBuffer.prototype.byteLength", &native_ArrayBuffer_p_byteLength));
        _arrayBufferPrototype["isView"] = new ScriptFunction("ArrayBuffer.protototype.isView",
                &native_TArray_isView!ScriptArrayBuffer);
        _arrayBufferPrototype["slice"] = new ScriptFunction("ArrayBuffer.prototype.slice",
                &native_ArrayBuffer_slice);
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
        _a%1$sPrototype["at"] = new ScriptFunction("%1$s.prototype.at",
                &native_TArray_at!%1$s);
        _a%1$sPrototype.addGetterProperty("buffer", new ScriptFunction("%1$s.prototype.buffer",
                &native_TArray_p_buffer!%1$s));
        _a%1$sPrototype.addGetterProperty("byteLength", new ScriptFunction("%1$s.prototype.byteLength",
                &native_TArray_p_byteLength!%1$s));
        _a%1$sPrototype.addGetterProperty("byteOffset", new ScriptFunction("%1$s.prototype.byteOffset",
                &native_TArray_p_byteOffset!%1$s));
        _a%1$sPrototype["copyWithin"] = new ScriptFunction("%1$s.prototype.copyWithin",
                &native_TArray_copyWithin!%1$s);
        _a%1$sPrototype["entries"] = new ScriptFunction("%1$s.prototype.entries",
                &native_TArray_entries!%1$s);
        _a%1$sPrototype["every"] = new ScriptFunction("%1$s.prototype.every",
                &native_TArray_every!%1$s);
        _a%1$sPrototype["fill"] = new ScriptFunction("%1$s.prototype.fill",
                &native_TArray_fill!%1$s);
        _a%1$sPrototype["filter"] = new ScriptFunction("%1$s.prototype.filter",
                &native_TArray_filter!%1$s);
        _a%1$sPrototype["find"] = new ScriptFunction("%1$s.prototype.find",
                &native_TArray_find!%1$s);
        _a%1$sPrototype["findIndex"] = new ScriptFunction("%1$s.prototype.findIndex",
                &native_TArray_findIndex!%1$s);
        _a%1$sPrototype["forEach"] = new ScriptFunction("%1$s.prototype.forEach",
                &native_TArray_forEach!%1$s);
        _a%1$sPrototype["includes"] = new ScriptFunction("%1$s.prototype.includes",
                &native_TArray_includes!%1$s);
        _a%1$sPrototype["indexOf"] = new ScriptFunction("%1$s.prototype.indexOf",
                &native_TArray_indexOf!%1$s);
        _a%1$sPrototype["isView"] = new ScriptFunction("%1$s.prototype.isView",
                &native_TArray_isView!%1$s);
        _a%1$sPrototype["join"] = new ScriptFunction("%1$s.prototype.join",
                &native_TArray_join!%1$s);
        _a%1$sPrototype["keys"] = new ScriptFunction("%1$s.prototype.keys",
                &native_TArray_keys!%1$s);
        _a%1$sPrototype["lastIndexOf"] = new ScriptFunction("%1$s.prototype.lastIndexOf",
                &native_TArray_lastIndexOf!%1$s);
        _a%1$sPrototype.addGetterProperty("length", new ScriptFunction("%1$s.prototype.length",
                &native_TArray_p_length!%1$s));
        _a%1$sPrototype["map"] = new ScriptFunction("%1$s.prototype.map",
                &native_TArray_map!%1$s);
        _a%1$sPrototype.addGetterProperty("name", new ScriptFunction("%1$s.prototype.name",
                &native_TArray_p_name!%1$s));
        _a%1$sPrototype["reduce"] = new ScriptFunction("%1$s.prototype.reduce",
                &native_TArray_reduce!%1$s);
        _a%1$sPrototype["reduceRight"] = new ScriptFunction("%1$s.prototype.reduceRight",
                &native_TArray_reduceRight!%1$s);
        _a%1$sPrototype["reverse"] = new ScriptFunction("%1$s.prototype.reverse",
                &native_TArray_reverse!%1$s);
        _a%1$sPrototype["set"] = new ScriptFunction("%1$s.prototype.set",
                &native_TArray_set!%1$s);
        _a%1$sPrototype["slice"] = new ScriptFunction("%1$s.prototype.slice",
                &native_TArray_slice!%1$s);
        _a%1$sPrototype["some"] = new ScriptFunction("%1$s.prototype.some",
                &native_TArray_some!%1$s);
        _a%1$sPrototype["sort"] = new ScriptFunction("%1$s.prototype.sort",
                &native_TArray_sort!%1$s);
        _a%1$sPrototype["subarray"] = new ScriptFunction("%1$s.prototype.subarray",
                &native_TArray_subarray!%1$s);
        _a%1$sPrototype["values"] = new ScriptFunction("%1$s.prototype.values",
                &native_TArray_values!%1$s);
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
    if(args.length == 0)
    {
        auto ab = new ScriptArrayBuffer(0);
        thisObj.toValue!ScriptObject.nativeObject = ab;
    }
    else if(args.length > 0 && args[0].isNumber)
    {
        size_t size = args.length > 0 ? args[0].toValue!size_t : 0;
        auto ab = new ScriptArrayBuffer(size);
        thisObj.toValue!ScriptObject.nativeObject = ab;
    }
    else if(args.length > 0 && args[0].isNativeObjectType!AbstractArrayBuffer)
    {
        auto ab = new ScriptArrayBuffer(0);
        auto aab = args[0].toNativeObject!AbstractArrayBuffer; // @suppress(dscanner.suspicious.unmodified)
        final switch(aab.type)
        {
        case AbstractArrayBuffer.Type.ARRAY_BUFFER:
            ab.data = (cast(ScriptArrayBuffer)aab).data;
            break;
        case AbstractArrayBuffer.Type.INT8_ARRAY: {
            auto a = cast(Int8Array)aab;
            ab.data = (cast(ubyte*)(a.data.ptr))[0..a.data.length];
            break;
        }
        case AbstractArrayBuffer.Type.UINT8_ARRAY: {
            auto a = cast(Uint8Array)aab;
            ab.data = a.data;
            break;
        }
        case AbstractArrayBuffer.Type.INT16_ARRAY: {
            auto a = cast(Int16Array)aab;
            ab.data = (cast(ubyte*)(a.data.ptr))[0..a.data.length*short.sizeof];
            break;
        }
        case AbstractArrayBuffer.Type.UINT16_ARRAY: {
            auto a = cast(Uint16Array)aab;
            ab.data = (cast(ubyte*)(a.data.ptr))[0..a.data.length*ushort.sizeof];
            break;
        }
        case AbstractArrayBuffer.Type.INT32_ARRAY: {
            auto a = cast(Int32Array)aab;
            ab.data = (cast(ubyte*)(a.data.ptr))[0..a.data.length*int.sizeof];
            break;
        }
        case AbstractArrayBuffer.Type.UINT32_ARRAY: {
            auto a = cast(Uint32Array)aab;
            ab.data = (cast(ubyte*)(a.data.ptr))[0..a.data.length*uint.sizeof];
            break;
        }
        case AbstractArrayBuffer.Type.FLOAT32_ARRAY: {
            auto a = cast(Float32Array)aab;
            ab.data = (cast(ubyte*)(a.data.ptr))[0..a.data.length*float.sizeof];
            break;
        }
        case AbstractArrayBuffer.Type.FLOAT64_ARRAY: {
            auto a = cast(Float64Array)aab;
            ab.data = (cast(ubyte*)(a.data.ptr))[0..a.data.length*double.sizeof];
            break;
        }
        case AbstractArrayBuffer.Type.BIGINT64_ARRAY: {
            auto a = cast(BigInt64Array)aab;
            ab.data = (cast(ubyte*)(a.data.ptr))[0..a.data.length*long.sizeof];
            break;
        }
        case AbstractArrayBuffer.Type.BIGUINT64_ARRAY: {
            auto a = cast(BigUint64Array)aab;
            ab.data = (cast(ubyte*)(a.data.ptr))[0..a.data.length*ulong.sizeof];
            break;
        }
        }
        thisObj.toValue!ScriptObject.nativeObject = ab;
    }
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_ArrayBuffer_p_byteLength(Environment env, ScriptAny* thisObj,
                                                  ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto ab = thisObj.toNativeObject!ScriptArrayBuffer;
    if(ab is null)
        throw new ScriptRuntimeException("This is not an ArrayBuffer");
    return ScriptAny(ab.data.length);    
}

private ScriptAny native_ArrayBuffer_s_isView(Environment env, ScriptAny* thisObj,
                                              ScriptAny[] args, ref NativeFunctionError nfe)
{
    return ScriptAny(false);
}

private ScriptAny native_ArrayBuffer_slice(Environment env, ScriptAny* thisObj,
                                           ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto ab = thisObj.toNativeObject!ScriptArrayBuffer;
    if(ab is null)
        throw new ScriptRuntimeException("This is not an ArrayBuffer");
    long start = args.length > 0 ? args[0].toValue!long : 0;
    long end = args.length > 1 ? args[1].toValue!long : ab.data.length;
    if(start < 0) start += ab.data.length;
    if(end < 0) end += ab.data.length;
    if(start < 0 || start >= ab.data.length)
        start = 0;
    if(end < 0 || end > ab.data.length)
        end = ab.data.length;
    if(end < start)
    {
        immutable temp = end;
        end = start;
        start = temp;
    }
    auto sliced = new ScriptArrayBuffer(0);
    sliced.data = ab.data[start..end];
    return ScriptAny(new ScriptObject("ArrayBuffer", getArrayBufferPrototype, sliced));
}

private ScriptAny native_TArray_ctor(A)(Environment env, ScriptAny* thisObj,
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
            a.data[] = data[0..$];
        else 
            a.data[] = (cast(E*)data.ptr)[0..data.length/E.sizeof];
        thisObj.toValue!ScriptObject.nativeObject = a;
    }
    else if(isIterable(args[0]))
    {
        immutable arr = native_TArray_s_from!A(env, thisObj, [args[0]], nfe);
        auto a = arr.toNativeObject!A; // @suppress(dscanner.suspicious.unmodified)
        thisObj.toValue!ScriptObject.nativeObject = a;
    }
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_TArray_at(A)(Environment env, ScriptAny* thisObj,
                                      ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto a  = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    long index = args[0].toValue!long;
    if(index < 0) index += a.data.length;
    if(index < 0 || index >= a.data.length)
        return ScriptAny.UNDEFINED;
    return ScriptAny(a.data[index]);
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


private ScriptAny native_TArray_copyWithin(A)(Environment env, ScriptAny* thisObj,
                                              ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    long target = args.length > 0 ? args[0].toValue!long : a.data.length;
    long start = args.length > 1 ? args[1].toValue!long : 0;
    long end = args.length > 2 ? args[2].toValue!long : a.data.length;

    if(target < 0) target += a.data.length;
    if(start < 0) start += a.data.length;
    if(end < 0) end += a.data.length;

    if(target < 0 || target >= a.data.length)
        target = a.data.length;
    if(start < 0 || start >= a.data.length)
        start  = 0;
    if(end < 0 || end >= a.data.length)
        end = a.data.length;
    if(end <= start)
        return *thisObj;
    for(long i = 0; i < (end - start); ++i)
    {
        if(i + target >= a.data.length || i + start >= a.data.length)
            break;
        a.data[i+target] = a.data[i+start];
    }
    return *thisObj;
}

private ScriptAny native_TArray_entries(A)(Environment env, ScriptAny* thisObj,
                                           ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.concurrency: yield;

    auto a = thisObj.toNativeObject!A; // @suppress(dscanner.suspicious.unmodified)
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    auto genFunc = new ScriptFunction("Iterator", 
        delegate ScriptAny(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
        {
            auto arr = args[0].toNativeObject!A;
            foreach(index, value ; arr.data)
            {
                auto entry = new ScriptAny[2];
                entry[0] = ScriptAny(index);
                entry[1] = ScriptAny(value);
                yield!ScriptAny(ScriptAny(entry));
            }
            return ScriptAny.UNDEFINED;
        }
    );
    auto generator = new ScriptGenerator(env, genFunc, [*thisObj]);
    auto iterator = new ScriptObject("Iterator", getGeneratorPrototype, generator);
    return ScriptAny(iterator);
}

private ScriptAny native_TArray_every(A)(Environment env, ScriptAny* thisObj,
                                         ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto a = thisObj.toNativeObject!A; // @suppress(dscanner.suspicious.unmodified)
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    if(args.length < 1)
        return ScriptAny(false);
    if(args[0].type != ScriptAny.Type.FUNCTION)
        return ScriptAny(false);
    auto theThisArg = args.length > 1 ? args[1] : getLocalThis(env, args[0]);
    bool result = true;
    size_t counter = 0;
    foreach(element ; a.data)
    {
        auto temp = native_Function_call(env, &args[0], 
            [ theThisArg, ScriptAny(element), ScriptAny(counter), *thisObj ], nfe);
        if(env.g.interpreter.vm.hasException || nfe != NativeFunctionError.NO_ERROR)
            return temp;
        result = result && temp;
        if(!result)
            return ScriptAny(result);
        ++counter;
    }
    return ScriptAny(result);
}

private ScriptAny native_TArray_fill(A)(Environment env, ScriptAny* thisObj,
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    alias E = typeof(A.data[0]);
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    if(args.length < 1)
        return *thisObj;

    long start = args.length > 1 ? args[1].toValue!long : 0;
    long end = args.length > 2 ? args[2].toValue!long : a.data.length;

    if(start < 0) start += a.data.length;
    if(end < 0) end += a.data.length;

    if(start < 0 || start >= a.data.length)
        start = 0;
    if(end < 0 || end >= a.data.length)
        end = a.data.length;
    for(size_t i = start; i < end; ++i)
        a.data[i] = args[0].toValue!E;
    return *thisObj;
}

private ScriptAny native_TArray_filter(A)(Environment env, ScriptAny* thisObj,
                                          ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
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
    ScriptAny thisToUse = args.length > 1 ? args[1] : getLocalThis(env, args[0]);
    auto result = new A(0);
    size_t counter = 0;
    foreach(element ; a.data)
    {
        auto temp = native_Function_call(env, &args[0], 
            [thisToUse, ScriptAny(element), ScriptAny(counter), *thisObj], nfe);
        if(env.g.interpreter.vm.hasException || nfe != NativeFunctionError.NO_ERROR)
            return temp;
        if(temp)
            result.data ~= element;
        ++counter;
    }
    return ScriptAny(new ScriptObject(A.stringof, thisObj.toValue!ScriptObject.prototype, result));
}

private ScriptAny native_TArray_find(A)(Environment env, ScriptAny* thisObj, 
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    if(args.length < 1)
        return ScriptAny.UNDEFINED;
    if(args[0].type != ScriptAny.Type.FUNCTION)
        return ScriptAny.UNDEFINED;
    auto thisToUse = args.length > 1 ? args[1] : getLocalThis(env, args[0]);
    for(size_t i = 0; i < a.data.length; ++i)
    {
        auto temp = native_Function_call(env, &args[0], 
            [thisToUse, ScriptAny(a.data[i]), ScriptAny(i), *thisObj], nfe);
        if(env.g.interpreter.vm.hasException || nfe != NativeFunctionError.NO_ERROR)
            return temp;
        if(temp)
            return ScriptAny(a.data[i]);
    }

    return ScriptAny.UNDEFINED;
}

private ScriptAny native_TArray_findIndex(A)(Environment env, ScriptAny* thisObj, 
                                             ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    if(args.length < 1)
        return ScriptAny.UNDEFINED;
    if(args[0].type != ScriptAny.Type.FUNCTION)
        return ScriptAny.UNDEFINED;
    auto thisToUse = args.length > 1 ? args[1] : getLocalThis(env, args[0]);
    for(size_t i = 0; i < a.data.length; ++i)
    {
        auto temp = native_Function_call(env, &args[0], 
            [thisToUse, ScriptAny(a.data[i]), ScriptAny(i), *thisObj], nfe);
        if(env.g.interpreter.vm.hasException || nfe != NativeFunctionError.NO_ERROR)
            return temp;
        if(temp)
            return ScriptAny(i);
    }

    return ScriptAny(-1);
}

private ScriptAny native_TArray_forEach(A)(Environment env, ScriptAny* thisObj,
                                           ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
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
    auto thisToUse = args.length > 1 ? args[1] : getLocalThis(env, args[0]);
    for(size_t i = 0; i < a.data.length; ++i)
    {
        auto temp = native_Function_call(env, &args[0],
            [thisToUse, ScriptAny(a.data[i]), ScriptAny(i), *thisObj], nfe);
        if(env.g.interpreter.vm.hasException || nfe != NativeFunctionError.NO_ERROR)
            return temp;
    }
    return ScriptAny.UNDEFINED;
}

/**
 * Creates an Array from any iterable
 */
ScriptAny native_TArray_s_from(A)(Environment env, ScriptAny* thisObj,
                                  ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.format: format;
    alias E = typeof(A.data[0]);
    if(args.length < 1)
        mixin(format("return ScriptAny(new ScriptObject(\"%1$s\", get%1$sPrototype, new A(0)));", A.stringof));
    ScriptAny func = args.length > 1 ? args[1] : ScriptAny.UNDEFINED;
    auto thisToUse = args.length > 2 ? args[2] : getLocalThis(env, func);
    
    auto result = new A(0);
    if(args[0].type == ScriptAny.Type.ARRAY)
    {
        auto arr = args[0].toValue!ScriptArray.array;
        for(size_t i = 0; i < arr.length; ++i)
        {
            if(func.type == ScriptAny.Type.FUNCTION)
            {
                auto temp = native_Function_call(env, &func, [thisToUse, arr[i], ScriptAny(i), args[0]], nfe);
                if(env.g.interpreter.vm.hasException || nfe != NativeFunctionError.NO_ERROR)
                    return temp;
                result.data ~= temp.toValue!E;
            }
            else
            {
                result.data ~= arr[i].toValue!E;
            }
        }
    }
    else if(args[0].type == ScriptAny.Type.STRING)
    {
        size_t index = 0;
        foreach(dchar ch ; args[0].toString())
        {
            if(func.type == ScriptAny.Type.FUNCTION)
            {
                auto temp = native_Function_call(env, &func, 
                    [thisToUse, ScriptAny([ch]), ScriptAny(index), args[0]], nfe);
                if(env.g.interpreter.vm.hasException || nfe != NativeFunctionError.NO_ERROR)
                    return temp;
                result.data ~= temp.toValue!E;
            }
            else
            {
                result.data ~= cast(E)ch;
            }
            ++index;
        }       
    }
    else if(args[0].isNativeObjectType!AbstractArrayBuffer)
    {
        auto aab = args[0].toNativeObject!AbstractArrayBuffer; // @suppress(dscanner.suspicious.unmodified)
        if(!aab.isView)
            throw new ScriptRuntimeException("ArrayBuffer must be cast to view");
        string HANDLE_TYPED_ARRAY(A)()
        {
            import std.format: format;
            return format(q{
            {
                auto a = cast(%1$s)aab;
                for(size_t i = 0; i < a.data.length; ++i)
                {
                    if(func.type == ScriptAny.Type.FUNCTION)
                    {
                        auto temp = native_Function_call(env, &func,
                            [thisToUse, ScriptAny(a.data[i]), ScriptAny(i), args[0]], nfe);
                        if(env.g.interpreter.vm.hasException || nfe != NativeFunctionError.NO_ERROR)
                            return temp;
                        result.data ~= temp.toValue!E;
                    }
                    else 
                    {
                        result.data ~= cast(E)a.data[i];
                    }
                }
            }
            }, A.stringof);
        }
        final switch(aab.type)
        {
        case AbstractArrayBuffer.Type.ARRAY_BUFFER:
            break; // already handled
        case AbstractArrayBuffer.Type.INT8_ARRAY:
            mixin(HANDLE_TYPED_ARRAY!Int8Array);
            break;
        case AbstractArrayBuffer.Type.UINT8_ARRAY:
            mixin(HANDLE_TYPED_ARRAY!Uint8Array);
            break;
        case AbstractArrayBuffer.Type.INT16_ARRAY:
            mixin(HANDLE_TYPED_ARRAY!Int16Array);
            break;
        case AbstractArrayBuffer.Type.UINT16_ARRAY:
            mixin(HANDLE_TYPED_ARRAY!Uint16Array);
            break;
        case AbstractArrayBuffer.Type.INT32_ARRAY:
            mixin(HANDLE_TYPED_ARRAY!Int32Array);
            break;
        case AbstractArrayBuffer.Type.UINT32_ARRAY:
            mixin(HANDLE_TYPED_ARRAY!Uint32Array);
            break;
        case AbstractArrayBuffer.Type.FLOAT32_ARRAY:
            mixin(HANDLE_TYPED_ARRAY!Float32Array);
            break;
        case AbstractArrayBuffer.Type.FLOAT64_ARRAY:
            mixin(HANDLE_TYPED_ARRAY!Float64Array);
            break;
        case AbstractArrayBuffer.Type.BIGINT64_ARRAY:
            mixin(HANDLE_TYPED_ARRAY!BigInt64Array);
            break;
        case AbstractArrayBuffer.Type.BIGUINT64_ARRAY:
            mixin(HANDLE_TYPED_ARRAY!BigUint64Array);
            break;
        }
    }
    else if(args[0].isNativeObjectType!ScriptGenerator)
    {
        auto nextIteration = native_Generator_next(env, &args[0], [], nfe).toValue!ScriptObject;
        size_t counter = 0;
        while(!nextIteration["done"])
        {
            auto value = nextIteration["value"];
            if(func.type == ScriptAny.Type.FUNCTION)
            {
                auto temp = native_Function_call(env, &func, [thisToUse, value, ScriptAny(counter), args[0]], nfe);
                if(env.g.interpreter.vm.hasException || nfe != NativeFunctionError.NO_ERROR)
                    return temp;
                result.data ~= temp.toValue!E;
            }
            else
            {
                result.data ~= value.toValue!E;
            }
            ++counter;
            nextIteration = native_Generator_next(env, &args[0], [], nfe).toValue!ScriptObject;
        }
    }

    mixin(format("return ScriptAny(new ScriptObject(\"%1$s\", get%1$sPrototype, result));", A.stringof));
}

private ScriptAny native_TArray_includes(A)(Environment env, ScriptAny* thisObj,
                                            ScriptAny[] args, ref NativeFunctionError nfe)
{
    alias E = typeof(A.data[0]);
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    if(a.data.length < 1)
        return ScriptAny(false);
    long indexToStart = args.length > 1 ? args[1].toValue!long : 0;
    if(indexToStart < 0) indexToStart += a.data.length;

    if(indexToStart < 0 || indexToStart >= a.data.length)
        indexToStart = a.data.length;
    for(size_t i = indexToStart; i < a.data.length; ++i)
        if(args[0].toValue!E == a.data[i])
            return ScriptAny(true);
    return ScriptAny(false);
}

private ScriptAny native_TArray_indexOf(A)(Environment env, ScriptAny* thisObj,
                                            ScriptAny[] args, ref NativeFunctionError nfe)
{
    alias E = typeof(A.data[0]);
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    if(a.data.length < 1)
        return ScriptAny(-1);
    long indexToStart = args.length > 1 ? args[1].toValue!long : 0;
    if(indexToStart < 0) indexToStart += a.data.length;

    if(indexToStart < 0 || indexToStart >= a.data.length)
        indexToStart = a.data.length;
    immutable value = args[0].toValue!E;
    for(size_t i = indexToStart; i < a.data.length; ++i)
        if(value == a.data[i])
            return ScriptAny(i);
    return ScriptAny(-1);
}

// only use this for typed arrays and not buffer
private ScriptAny native_TArray_s_isView(A)(Environment env, ScriptAny* thisObj,
                                            ScriptAny[] args, ref NativeFunctionError nfe)
{
    return ScriptAny(true);
}

private ScriptAny native_TArray_isView(A)(Environment env, ScriptAny* thisObj,
                                          ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    return ScriptAny(a.isView());
}

private ScriptAny native_TArray_join(A)(Environment env, ScriptAny* thisObj, 
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.conv: to;
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    auto join = ",";
    if(args.length > 0)
        join = args[0].toString();
    string result = "";
    for(size_t i = 0; i < a.data.length; ++i)
    {
        result ~= to!string(a.data[i]);
        if(i < a.data.length - 1)
            result ~= join;
    }
    return ScriptAny(result);
}

private ScriptAny native_TArray_keys(A)(Environment env, ScriptAny* thisObj,
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.concurrency: yield;
    auto a = thisObj.toNativeObject!A; // @suppress(dscanner.suspicious.unmodified)
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    auto genFunc = new ScriptFunction("Iterator", 
        delegate ScriptAny(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
        {
            auto a = args[0].toNativeObject!A;
            foreach(key, value ; a.data)
                yield!ScriptAny(ScriptAny(key));
            return ScriptAny.UNDEFINED;
        }
    );
    auto generator = new ScriptGenerator(env, genFunc, [ *thisObj ]);
    auto iterator = new ScriptObject("Iterator", getGeneratorPrototype, generator);
    return ScriptAny(iterator);
}

private ScriptAny native_TArray_lastIndexOf(A)(Environment env, ScriptAny* thisObj,
                                               ScriptAny[] args, ref NativeFunctionError nfe)
{
    alias E = typeof(A.data[0]);
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    if(args.length < 1)
        return ScriptAny(-1);
    long indexToStart = args.length > 1 ? args[1].toValue!long : a.data.length - 1;
    if(indexToStart < 0) indexToStart += a.data.length;
    if(indexToStart < 0 || indexToStart >= a.data.length)
        indexToStart = a.data.length - 1;
    immutable value = args[0].toValue!E;
    if(a.data.length == 0)
        return ScriptAny(-1);
    for(long i = indexToStart; i >= 0; --i)
    {
        if(value == a.data[i])
            return ScriptAny(i);
    }
    return ScriptAny(-1);    
}

private ScriptAny native_TArray_p_length(A)(Environment env, ScriptAny* thisObj,
                                            ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    return ScriptAny(a.data.length);
}

private ScriptAny native_TArray_map(A)(Environment env, ScriptAny* thisObj,
                                      ScriptAny[] args, ref NativeFunctionError nfe)
{
    alias E = typeof(A.data[0]);
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
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
    ScriptAny thisToUse = args.length > 1 ? args[1] : ScriptAny.UNDEFINED;
    auto result = new A(0);
    for(size_t i = 0; i < a.data.length; ++i)
    {
        auto temp = native_Function_call(env, &args[0], 
            [thisToUse, ScriptAny(a.data[i]), ScriptAny(i), *thisObj], nfe);
        if(env.g.interpreter.vm.hasException || nfe != NativeFunctionError.NO_ERROR)
            return temp;
        result.data ~= temp.toValue!E;
    }
    return ScriptAny(new ScriptObject(A.stringof, thisObj.toValue!ScriptObject.prototype, result));
}

private ScriptAny native_TArray_p_name(A)(Environment env, ScriptAny* thisObj,
                                          ScriptAny[] args, ref NativeFunctionError nfe)
{
    return ScriptAny(A.stringof);
}

private ScriptAny native_TArray_s_of(A)(Environment env, ScriptAny* thisObj,
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    alias E = typeof(A.data[0]);
    auto results = new A(0);
    foreach(arg ; args)
        results.data ~= arg.toValue!E;
    mixin(format("return ScriptAny(new ScriptObject(\"%1$s\", get%1$sPrototype, results));", A.stringof));
}

private ScriptAny native_TArray_reduce(A)(Environment env, ScriptAny* thisObj,
                                          ScriptAny[] args, ref NativeFunctionError nfe)
{
    alias E = typeof(A.data[0]);
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    if(args.length < 0)
    { 
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    if(args[0].type != ScriptAny.Type.FUNCTION)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    auto accumulator = args.length > 1 ? args[1].toValue!E : (a.data.length > 0? a.data[0] : cast(E)0);
    immutable start = args.length < 2 ? 0 : 1;
    if(a.data.length == 0 && args.length < 2)
        throw new ScriptRuntimeException("Reduce with no accumulator may not be called on empty array");
    for(size_t i = start; i < a.data.length; ++i)
    {
        accumulator = native_Function_call(env, &args[0], 
            [getLocalThis(env, args[0]), ScriptAny(accumulator), ScriptAny(a.data[i]), 
            ScriptAny(i), *thisObj], nfe).toValue!E;
        if(env.g.interpreter.vm.hasException || nfe != NativeFunctionError.NO_ERROR)
            return ScriptAny(accumulator);
    }
    return ScriptAny(accumulator);
}

private ScriptAny native_TArray_reduceRight(A)(Environment env, ScriptAny* thisObj,
                                               ScriptAny[] args, ref NativeFunctionError nfe)
{
    alias E = typeof(A.data[0]);
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    if(args.length < 0)
    { 
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    if(args[0].type != ScriptAny.Type.FUNCTION)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    auto accumulator = args.length > 1 ? 
        args[1].toValue!E : 
        (a.data.length > 0? a.data[a.data.length-1] : cast(E)0);
    immutable long start = cast(long)a.data.length - 1;
    if(a.data.length == 0 && args.length < 2)
        throw new ScriptRuntimeException("Reduce right with no accumulator may not be called on empty array");
    for(long i = start; i > 0; --i)
    {
        accumulator = native_Function_call(env, &args[0], 
            [getLocalThis(env, args[0]), ScriptAny(accumulator), ScriptAny(a.data[i-1]), 
            ScriptAny(i-1), *thisObj], nfe).toValue!E;
        if(env.g.interpreter.vm.hasException || nfe != NativeFunctionError.NO_ERROR)
            return ScriptAny(accumulator);
    }
    return ScriptAny(accumulator);
}

private ScriptAny native_TArray_reverse(A)(Environment env, ScriptAny* thisObj,
                                           ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.algorithm.mutation: reverse;
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    reverse(a.data);
    return *thisObj;
}

private ScriptAny native_TArray_set(A)(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    alias E = typeof(A.data[0]);
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
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
    // do this the easy way and convert all arguments to a ScriptAny[]
    auto arr = native_Array_s_from(env, thisObj, [args[0]], nfe).toValue!(ScriptAny[]);
    immutable offset = args.length > 1 ? args[1].toValue!size_t : 0;
    if(offset + arr.length > a.data.length)
        throw new ScriptRuntimeException("Set parameter exceeds array size");
    for(size_t i = offset; i < offset + arr.length; ++i)
    {
        a.data[i] = arr[i-offset].toValue!E;
    }
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_TArray_slice(A)(Environment env, ScriptAny* thisObj, 
                                         ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    long start = args.length > 0 ? args[0].toValue!long : 0;
    long end = args.length > 1 ? args[1].toValue!long : a.data.length;
    if(start < 0) start += a.data.length;
    if(end < 0) end += a.data.length;
    if(start < 0 || start >= a.data.length)
        start = 0;
    if(end < 0 || end > a.data.length)
        end = a.data.length;
    if(end < start)
    {
        immutable temp = end;
        end = start;
        start = temp;
    }
    auto sliced = new A(end-start);
    sliced.data[] = a.data[start..end];
    return ScriptAny(new ScriptObject(A.stringof, thisObj.toValue!ScriptObject.prototype, sliced));
}

private ScriptAny native_TArray_some(A)(Environment env, ScriptAny* thisObj, 
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
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
    ScriptAny thisToUse = args.length > 1 ? args[1] : getLocalThis(env, args[0]);
    for(size_t i = 0; i < a.data.length; ++i)
    {
        auto temp = native_Function_call(env, &args[0], 
            [thisToUse, ScriptAny(a.data[i]), ScriptAny(i), *thisObj], nfe);
        if(env.g.interpreter.vm.hasException || nfe != NativeFunctionError.NO_ERROR || temp)
            return temp;
    }
    return ScriptAny(false);
}

private ScriptAny native_TArray_sort(A)(Environment env, ScriptAny* thisObj,
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.algorithm: sort;
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    if(a.data.length <= 1)
        return *thisObj; // already sorted if empty or one element
    if(args.length < 1 || args[0].type != ScriptAny.Type.FUNCTION)
    {
        sort(a.data);
    }
    else
    {
        // use bubble sort
        for(size_t i = 0; i < a.data.length-1; ++i)
        {
            for(size_t j = 0; j < a.data.length - i - 1; ++j)
            {
                auto temp = native_Function_call(env, &args[0], 
                    [getLocalThis(env, args[0]), ScriptAny(a.data[j]), 
                    ScriptAny(a.data[j+1])], nfe);
                if(env.g.interpreter.vm.hasException || nfe != NativeFunctionError.NO_ERROR)
                    return temp;
                if(temp.toValue!int > 0)
                {
                    immutable swap = a.data[j+1]; // @suppress(dscanner.suspicious.unmodified)
                    a.data[j+1] = a.data[j];
                    a.data[j] = swap;
                }
            }
        }
    }
    return *thisObj;
}

private ScriptAny native_TArray_subarray(A)(Environment env, ScriptAny* thisObj, 
                                         ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto a = thisObj.toNativeObject!A;
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    long start = args.length > 0 ? args[0].toValue!long : 0;
    long end = args.length > 1 ? args[1].toValue!long : a.data.length;
    if(start < 0) start += a.data.length;
    if(end < 0) end += a.data.length;
    if(start < 0 || start >= a.data.length)
        start = 0;
    if(end < 0 || end > a.data.length)
        end = a.data.length;
    if(end < start)
    {
        immutable temp = end;
        end = start;
        start = temp;
    }
    auto sliced = new A(0);
    sliced.data = a.data[start..end];
    return ScriptAny(new ScriptObject(A.stringof, thisObj.toValue!ScriptObject.prototype, sliced));
}

private ScriptAny native_TArray_values(A)(Environment env, ScriptAny* thisObj,
                                          ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.concurrency: yield;
    auto a = thisObj.toNativeObject!A; // @suppress(dscanner.suspicious.unmodified)
    if(a is null)
        throw new ScriptRuntimeException("This is not a " ~ A.stringof);
    auto genFunc = new ScriptFunction("Iterator",
        delegate ScriptAny(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
        {
            auto a = args[0].toNativeObject!A;
            foreach(value ; a.data)
                yield!ScriptAny( ScriptAny(value) );
            return ScriptAny.UNDEFINED;
        }
    );
    auto generator = new ScriptGenerator(env, genFunc, [*thisObj]);
    auto iterator = new ScriptObject("Iterator", getGeneratorPrototype, generator);
    return ScriptAny(iterator);
}