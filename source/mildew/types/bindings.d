/**
This module implements the __proto__ field given to each special object such as ScriptObject, ScriptFunction,
ScriptArray, and ScriptString, as well as the static methods for Object, Array, Function, and String
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
module mildew.types.bindings;

import mildew.environment;
import mildew.interpreter;
import mildew.types.any;
import mildew.types.array;
import mildew.types.func;
import mildew.types.string;
import mildew.types.object;

package(mildew):

/**
 * Initializes the bindings of builtin types such as Object, Function, String, and Array. This function is not
 * required because these objects already have their __proto__ set correctly when constructed.
 */
void initializeTypesLibrary(Interpreter interpreter)
{
    ScriptAny Object_ctor = new ScriptFunction("Object", &native_Object_constructor, true);
    Object_ctor["prototype"] = getObjectPrototype();
    Object_ctor["prototype"]["constructor"] = Object_ctor;
    // static Object methods
    Object_ctor["create"] = new ScriptFunction("Object.create", &native_Object_s_create);
    Object_ctor["entries"] = new ScriptFunction("Object.entries", &native_Object_s_entries);
    Object_ctor["getOwnPropertyDescriptor"] = new ScriptFunction("Object.getOwnPropertyDescriptor", 
            &native_Object_s_getOwnPropertyDescriptor);
    Object_ctor["keys"] = new ScriptFunction("Object.keys", &native_Object_s_keys);
    Object_ctor["values"] = new ScriptFunction("Object.values", &native_Object_s_values);
    ScriptAny String_ctor = new ScriptFunction("String", &native_String_ctor, true);
    String_ctor["prototype"] = getStringPrototype();
    String_ctor["prototype"]["constructor"] = String_ctor;
    String_ctor["fromCharCode"] = new ScriptFunction("String.fromCharCode",
            &native_String_s_fromCharCode);
    String_ctor["fromCodePoint"] = new ScriptFunction("String.fromCodePoint",
            &native_String_s_fromCodePoint);

    interpreter.forceSetGlobal("Object", Object_ctor, false); // maybe should be const
    interpreter.forceSetGlobal("String", String_ctor, false);
}

ScriptObject getObjectPrototype()
{
    if(_objectPrototype is null)
    {
        _objectPrototype = new ScriptObject("object"); // this is the base prototype for all objects
    }
    return _objectPrototype;
}

ScriptObject getArrayPrototype()
{
    if(_arrayPrototype is null)
    {
        _arrayPrototype = new ScriptObject("array", null);
        _arrayPrototype["concat"] = new ScriptFunction("Array.prototype.concat", &native_Array_concat);
        _arrayPrototype["join"] = new ScriptFunction("Array.prototype.join", &native_Array_join);
        _arrayPrototype["pop"] = new ScriptFunction("Array.prototype.pop", &native_Array_pop);
        _arrayPrototype["push"] = new ScriptFunction("Array.prototype.push", &native_Array_push);
        _arrayPrototype["slice"] = new ScriptFunction("Array.prototype.slice", &native_Array_slice);
        _arrayPrototype["splice"] = new ScriptFunction("Array.prototype.splice", &native_Array_splice);
    }
    return _arrayPrototype;
}

ScriptObject getFunctionPrototype()
{
    import mildew.exceptions: ScriptRuntimeException;
    if(_functionPrototype is null)
    {
        _functionPrototype = new ScriptObject("function", null);
        _functionPrototype["apply"] = new ScriptFunction("Function.prototype.apply", &native_Function_apply);
        _functionPrototype["call"] = new ScriptFunction("Function.prototype.call", &native_Function_call);
    }
    return _functionPrototype;
}

ScriptObject getStringPrototype()
{
    if(_stringPrototype is null)
    {
        _stringPrototype = new ScriptObject("string", null);
        _stringPrototype["charAt"] = new ScriptFunction("String.prototype.charAt", &native_String_charAt);
        _stringPrototype["charCodeAt"] = new ScriptFunction("String.prototype.charCodeAt", 
                &native_String_charCodeAt);
        _stringPrototype["codePointAt"] = new ScriptFunction("String.prototype.codePointAt",
                &native_String_codePointAt);
        _stringPrototype["concat"] = new ScriptFunction("String.prototype.concat", &native_String_concat);
        _stringPrototype["endsWith"] = new ScriptFunction("String.prototype.endsWith", &native_String_endsWith);
        _stringPrototype["includes"] = new ScriptFunction("String.prototype.includes", &native_String_includes);
        _stringPrototype["indexOf"] = new ScriptFunction("String.prototype.indexOf", &native_String_indexOf);
        _stringPrototype["lastIndexOf"] = new ScriptFunction("String.prototype.lastIndexOf",
                &native_String_lastIndexOf);
        _stringPrototype["padEnd"] = new ScriptFunction("String.prototype.padEnd", &native_String_padEnd);
        _stringPrototype["padStart"] = new ScriptFunction("String.prototype.padStart",
                &native_String_padStart);
        _stringPrototype["repeat"] = new ScriptFunction("String.prototype.repeat", &native_String_repeat);
        _stringPrototype["replace"] = new ScriptFunction("String.prototype.replace", &native_String_replace);
        _stringPrototype["replaceAll"] = new ScriptFunction("String.prototype.replaceAll",
                &native_String_replaceAll);
        _stringPrototype["slice"] = new ScriptFunction("String.prototype.slice", &native_String_slice);
        _stringPrototype["split"] = new ScriptFunction("String.prototype.split", &native_String_split);
        _stringPrototype["startsWith"] = new ScriptFunction("String.prototype/startsWith", &native_String_startsWith);
        _stringPrototype["substring"] = new ScriptFunction("String.prototype.substring", &native_String_substring);
        _stringPrototype["toLowerCase"] = new ScriptFunction("String.prototype.toLowerCase",
                &native_String_toLowerCase);
        _stringPrototype["toUpperCase"] = new ScriptFunction("String.prototype.toUpperCase", 
                &native_String_toUpperCase);
    }
    return _stringPrototype;
}

private ScriptObject _objectPrototype;
private ScriptObject _arrayPrototype;
private ScriptObject _functionPrototype;
private ScriptObject _stringPrototype;

//
// Object methods /////////////////////////////////////////////////////////////
//

private ScriptAny native_Object_constructor(Environment c, ScriptAny* thisObj, ScriptAny[] args, 
        ref NativeFunctionError nfe)
{
    if(args.length >= 1)
    {
        if(args[0].isObject)
            *thisObj = args[0];
    }
    return ScriptAny.UNDEFINED;
}

/**
 * Object.create: This can be called by the script to create a new object whose prototype is the
 * parameter.
 */
private ScriptAny native_Object_s_create(Environment context,  // @suppress(dscanner.style.phobos_naming_convention)
                                        ScriptAny* thisObj, 
                                        ScriptAny[] args, 
                                        ref NativeFunctionError nfe)
{
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }

    if(!args[0].isObject)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }

    auto newObj = new ScriptObject("", args[0].toValue!ScriptObject);

    return ScriptAny(newObj);
}

/// Returns an array of 2-element arrays representing the key and value of each dictionary entry
private ScriptAny native_Object_s_entries(Environment context,
                                        ScriptAny* thisObj,
                                        ScriptAny[] args,
                                        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny.UNDEFINED;
    
    if(!args[0].isObject)
        return ScriptAny.UNDEFINED;
    
    ScriptAny[][] entries;
    foreach(key, value ; args[0].toValue!ScriptObject.dictionary)
    {
        entries ~= [ScriptAny(key), value];
    }
    return ScriptAny(entries);
}

/// Returns a possible getter or setter for an object
private ScriptAny native_Object_s_getOwnPropertyDescriptor(Environment context,
                                                        ScriptAny* thisObj,
                                                        ScriptAny[] args,
                                                        ref NativeFunctionError nfe)
{
    if(args.length < 2)
        return ScriptAny.UNDEFINED;
    if(!args[0].isObject)
        return ScriptAny.UNDEFINED;
    auto propName = args[1].toString();
    return ScriptAny(args[0].toValue!ScriptObject.getOwnPropertyDescriptor(propName));
}

/// returns an array of keys of an object (or function)
private ScriptAny native_Object_s_keys(Environment context,
                                    ScriptAny* thisObj,
                                    ScriptAny[] args,
                                    ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny.UNDEFINED;
    
    if(!args[0].isObject)
        return ScriptAny.UNDEFINED;

    auto sobj = args[0].toValue!ScriptObject;
    auto keys = ScriptAny(sobj.dictionary.keys);
    return keys;
}

/// returns an array of values of an object (or function)
private ScriptAny native_Object_s_values(Environment context,
                                        ScriptAny* thisObj,
                                        ScriptAny[] args,
                                        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny.UNDEFINED;
    
    if(!args[0].isObject)
        return ScriptAny.UNDEFINED;

    auto sobj = args[0].toValue!ScriptObject;
    auto values = ScriptAny(sobj.dictionary.values);
    return values;
}

//
// Array methods //////////////////////////////////////////////////////////////
//

private ScriptAny native_Array_concat(Environment c, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    if(args.length < 1)
        return *thisObj;
    ScriptAny[] result = thisObj.toValue!ScriptArray.array;
    if(args[0].type != ScriptAny.Type.ARRAY)
    {
        result ~= args[0];
    }
    else
    {
        result ~= args[0].toValue!ScriptArray.array;
    }
    return ScriptAny(result);
}

private ScriptAny native_Array_join(Environment c, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto join = ",";
    if(args.length > 0)
        join = args[0].toString();
    auto arr = thisObj.toValue!(string[]);
    string result = "";
    for(size_t i = 0; i < arr.length; ++i)
    {
        result ~= arr[i];
        if(i < arr.length - 1)
            result ~= join;
    }
    return ScriptAny(result);
}

private ScriptAny native_Array_push(Environment c, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    if(args.length < 0)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray;
    arr.array ~= args[0];
    return ScriptAny(arr.array.length);
}

private ScriptAny native_Array_pop(Environment c, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray;
    if(arr.array.length < 1)
        return ScriptAny.UNDEFINED;
    auto result = arr.array[$-1];
    arr.array = arr.array[0..$-1];
    return result;
}

private ScriptAny native_Array_slice(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto array = thisObj.toValue!(ScriptAny[]);
    if(args.length < 1)
        return ScriptAny(array);
    size_t start = args[0].toValue!size_t;
    if(start >= array.length)
        start = array.length;
    if(args.length < 2)
        return ScriptAny(array[start .. $]);
    size_t end = args[1].toValue!size_t;
    if(end  >= array.length)
        end = array.length;
    return ScriptAny(array[start .. end]);
}

private ScriptAny native_Array_splice(Environment c, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.algorithm: min;
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray;
    if(args.length < 1)
        return ScriptAny.UNDEFINED;
    immutable start = min(args[0].toValue!size_t, arr.array.length - 1);
    if(start >= arr.array.length)
        return ScriptAny.UNDEFINED;
    immutable deleteCount = args.length > 1 ? min(args[1].toValue!size_t, arr.array.length) : arr.array.length - start;
    ScriptAny[] removed = [];
    if(args.length > 2)
        args = args[2 .. $];
    else
        args = [];
    // copy elements up to start
    ScriptAny[] result = arr.array[0 .. start];
    // add new elements supplied as args
    result ~= args;
    // copy removed items to removed array
    removed ~= arr.array[start .. start+deleteCount];
    // add those after start plus delete count
    result ~= arr.array[start+deleteCount .. $];
    // set the original array
    arr.array = result;
    // return the removed items
    return ScriptAny(removed);
}

//
// Function methods ///////////////////////////////////////////////////////////
//

private ScriptAny native_Function_call(Environment c, ScriptAny* thisIsFn, ScriptAny[] args, 
                                       ref NativeFunctionError nfe)
{
    import mildew.exceptions: ScriptRuntimeException;
    // minimum args is 1 because first arg is the this to use
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    // get the function
    if(thisIsFn.type != ScriptAny.Type.FUNCTION)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    auto fn = thisIsFn.toValue!ScriptFunction;
    // set up the "this" to use
    auto thisToUse = args[0];
    // now send the remainder of the args to a called function with this setup
    args = args[1..$];
    try 
    {
        auto interpreter = c.interpreter;
        if(interpreter.usingVM)
        {
            if(fn.type == ScriptFunction.Type.SCRIPT_FUNCTION)
                return interpreter.vm.runFunction(fn, thisToUse, args);
            else if(fn.type == ScriptFunction.Type.NATIVE_FUNCTION)
                return fn.nativeFunction()(c, &thisToUse, args, nfe);
            else if(fn.type == ScriptFunction.Type.NATIVE_DELEGATE)
                return fn.nativeDelegate()(c, &thisToUse, args, nfe);
        }
        if(c !is null)
            return interpreter.callFunction(fn, thisToUse, args);
        else
            return ScriptAny.UNDEFINED;
    }
    catch(ScriptRuntimeException ex)
    {
        nfe = NativeFunctionError.RETURN_VALUE_IS_EXCEPTION;
        return ScriptAny(ex.msg);
    }
}

private ScriptAny native_Function_apply(Environment c, ScriptAny* thisIsFn, ScriptAny[] args,
                                        ref NativeFunctionError nfe)
{
    import mildew.exceptions: ScriptRuntimeException;
    // minimum args is 2 because first arg is the this to use and the second is an array
    if(args.length < 2)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    // get the function
    if(thisIsFn.type != ScriptAny.Type.FUNCTION)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    auto fn = thisIsFn.toValue!ScriptFunction;
    // set up the "this" to use
    auto thisToUse = args[0];
    // set up the arg array
    if(args[1].type != ScriptAny.Type.ARRAY)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    auto argList = args[1].toValue!(ScriptAny[]);
    try 
    {
        auto interpreter = c.interpreter;
        if(interpreter.usingVM)
        {
            if(fn.type == ScriptFunction.Type.SCRIPT_FUNCTION)
                return interpreter.vm.runFunction(fn, thisToUse, args);
            else if(fn.type == ScriptFunction.Type.NATIVE_FUNCTION)
                return fn.nativeFunction()(c, &thisToUse, argList, nfe);
            else if(fn.type == ScriptFunction.Type.NATIVE_DELEGATE)
                return fn.nativeDelegate()(c, &thisToUse, argList, nfe);
        }
        if(interpreter !is null)
            return interpreter.callFunction(fn, thisToUse, argList);
        else
            return ScriptAny.UNDEFINED;
    }
    catch(ScriptRuntimeException ex)
    {
        nfe = NativeFunctionError.RETURN_VALUE_IS_EXCEPTION;
        return ScriptAny(ex.msg);
    }
}

//
// String methods /////////////////////////////////////////////////////////////  
//

/// Creates a string by converting arguments to strings and concatenating them
private ScriptAny native_String_ctor(Environment env, ScriptAny* thisObj,
                                     ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto str = "";
    foreach(arg ; args)
    {
        str ~= arg.toString();
    }
    *thisObj = ScriptAny(str);
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_String_charAt(Environment c, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.utf: UTFException;

    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;

    auto ss = thisObj.toString();
    immutable size_t index = args.length > 0 ? args[0].toValue!size_t : 0;

    if(index >= ss.length)
        return ScriptAny("");

    try
    {
        immutable char ch = ss[index];
        return ScriptAny([ch]);
    }
    catch(UTFException ex)
    {
        return ScriptAny("");
    }
}

private ScriptAny native_String_charCodeAt(Environment c, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;
    if(args.length < 1)
        return ScriptAny.UNDEFINED;

    auto ss = thisObj.toString();
    immutable size_t index = args.length > 0 ? args[0].toValue!size_t : 0;

    if(index >= ss.length)
        return ScriptAny(0);

    return ScriptAny(cast(ubyte)ss[index]);
}

private ScriptAny native_String_codePointAt(Environment env, ScriptAny* thisObj,
                                            ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;

    auto str = thisObj.toString();
    immutable size_t index = args.length >= 1 ? args[0].toValue!size_t: 0;
    size_t counter = 0;
    foreach(dchar dch ; str)
    {
        if(counter == index)
            return ScriptAny(cast(uint)dch);
        ++counter;
    }
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_String_concat(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;
    auto str = thisObj.toString();
    foreach(arg ; args)
    {
        str ~= arg.toString();
    }
    return ScriptAny(str);
}

private ScriptAny native_String_endsWith(Environment env, ScriptAny* thisObj,
                                         ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny(false);
    auto str = thisObj.toString();
    if(args.length < 1)
        return ScriptAny(true);
    auto testStr = args[0].toString();
    size_t limit = args.length > 1 ? args[1].toValue!size_t : str.length;
    if(limit > str.length)
        limit = str.length;
    str = str[0..limit];
    if(testStr.length > str.length)
        return ScriptAny(false);
    return ScriptAny(str[$-testStr.length .. $] == testStr);
}

private ScriptAny native_String_s_fromCharCode(Environment env, ScriptAny* thisObj,
                                               ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.utf: UTFException;
    auto result = "";
    foreach(arg ; args)
    {
        try 
        {
            result ~= cast(char)(arg.toValue!uint % 256);
        }
        catch(UTFException ex)
        {
            return ScriptAny.UNDEFINED;
        }
    }
    return ScriptAny(result);
}

private ScriptAny native_String_s_fromCodePoint(Environment env, ScriptAny* thisObj,
                                                ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.utf: UTFException;
    dstring result = "";
    foreach(arg ; args)
    {
        try 
        {
            result ~= cast(dchar)(arg.toValue!uint);
        }
        catch(UTFException ex)
        {
            return ScriptAny.UNDEFINED;
        }
    }
    return ScriptAny(result);
}

private ScriptAny native_String_includes(Environment env, ScriptAny* thisObj,
                                         ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.string: indexOf;
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny(false);
    auto str = thisObj.toString();
    if(args.length < 1)
        return ScriptAny(true);
    auto search = args[0].toString();
    return ScriptAny(str.indexOf(search) != -1);
}

private ScriptAny native_String_indexOf(Environment env, ScriptAny* thisObj,
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.string: indexOf;
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny(-1);
    auto str = thisObj.toString();
    if(args.length < 1)
        return ScriptAny(0);
    auto searchText = args[0].toString();
    return ScriptAny(str.indexOf(searchText));
}

private ScriptAny native_String_lastIndexOf(Environment env, ScriptAny* thisObj,
                                            ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.string: lastIndexOf;
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny(-1);
    auto str = thisObj.toString();
    if(args.length < 1)
        return ScriptAny(0);
    auto searchText = args[0].toString();
    immutable startIdx = args.length > 1 ? args[1].toValue!long : str.length;
    return ScriptAny(str.lastIndexOf(searchText, startIdx));
}

// TODO match once regular expressions are implemented

// TODO matchAll once regular expressions and Generators are implemented

private ScriptAny native_String_padEnd(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;
    auto str = thisObj.toString();
    if(args.length < 1)
        return *thisObj;
    immutable numPadding = args[0].toValue!long;
    auto padding = args.length > 1 ? args[1].toString(): " ";
    if(str.length > numPadding)
        return *thisObj;
    if(padding.length == 0)
        return *thisObj;
    immutable amountToAdd = (numPadding - str.length) / padding.length;
    for(auto i = 0; i < amountToAdd+1; ++i)
        str ~= padding;
    return ScriptAny(str[0..numPadding]);
}

private ScriptAny native_String_padStart(Environment env, ScriptAny* thisObj,
                                         ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;
    auto str = thisObj.toString();
    if(args.length < 1)
        return *thisObj;
    immutable numPadding = args[0].toValue!long;
    auto padding = args.length > 1 ? args[1].toString(): " ";
    if(padding.length == 0)
        return *thisObj;
    if(str.length > numPadding)
        return *thisObj;
    immutable amountToAdd = (numPadding - str.length) / padding.length;
    string frontString = "";
    for(auto i = 0; i < amountToAdd+1; ++i)
        frontString ~= padding;
    frontString = frontString[0..numPadding-str.length];
    return ScriptAny(frontString ~ str);
}

// TODO not add String.raw but add C# @`...` for true literal strings

private ScriptAny native_String_repeat(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;
    auto str = thisObj.toString();
    auto result = "";
    immutable size_t timesToRepeat = args.length >= 1 ? args[0].toValue!size_t: 0;
    for(size_t i = 0; i < timesToRepeat; ++i)
        result ~= str;
    return ScriptAny(result);
}

// TODO handle regex as first argument once implemented
// TODO handle second argument as possible function
private ScriptAny native_String_replace(Environment env, ScriptAny* thisObj,
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.string: indexOf;
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;
    if(args.length < 2)
        return *thisObj;
    auto str = thisObj.toString();
    auto pattern = args[0].toString();
    immutable replacement = args[1].toString();
    immutable index = str.indexOf(pattern);
    if(index != -1)
    {
        str = str[0..index] ~ replacement ~ str[index+pattern.length..$];
        return ScriptAny(str);
    }
    return *thisObj;
}

// TODO handle regex as first argument once implemented
// TODO handle second argument as possible function
private ScriptAny native_String_replaceAll(Environment env, ScriptAny* thisObj,
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.array: replace;
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;
    if(args.length < 2)
        return *thisObj;
    auto str = thisObj.toString();
    auto pattern = args[0].toString();
    auto replacement = args[1].toString();
    return ScriptAny(str.replace(pattern, replacement));    
}

// TODO String.prototype.search(someRegex)

private ScriptAny native_String_slice(Environment env, ScriptAny* thisObj,
                                      ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.utf : UTFException;
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;
    
    auto str = thisObj.toString();

    long start = args.length > 0 ? args[0].toValue!long : 0;
    long end = args.length > 1 ? args[1].toValue!long : str.length;

    if(start < 0)
        start = str.length + start;
    if(end < 0)
        end = str.length + end;
    
    if(start < 0 || start > str.length)
        start = 0;
    
    if(end < 0 || end > str.length)
        end = str.length;

    try 
    {
        str = str[start..end];
        return ScriptAny(str);
    }
    catch(UTFException ex)
    {
        return ScriptAny.UNDEFINED;
    }
}

private ScriptAny native_String_split(Environment env, ScriptAny* thisObj, 
                                      ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.array: split;
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;
    auto splitter = ",";
    if(args.length > 0)
        splitter = args[0].toString();
    auto splitResult = thisObj.toString().split(splitter);
    return ScriptAny(splitResult);
}

private ScriptAny native_String_startsWith(Environment env, ScriptAny* thisObj,
                                           ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny(false);
    auto str = thisObj.toString();
    string substring = args.length > 0 ? args[0].toString() : "";
    size_t startIndex = args.length > 1 ? args[1].toValue!size_t : 0;
    if(startIndex > str.length)
        startIndex = str.length;
    str = str[startIndex..$];
    if(str.length < substring.length)
        return ScriptAny(false);
    return ScriptAny(str[0..substring.length] == substring);
}

private ScriptAny native_String_substring(Environment env, ScriptAny* thisObj,
                                          ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.conv: to;

    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;
    auto dstr = to!dstring(thisObj.toString());
    long startIndex = args.length > 0 ? args[0].toValue!long : 0;
    long endIndex = args.length > 1 ? args[1].toValue!long : dstr.length;
    if(startIndex < 0)
        startIndex = dstr.length + startIndex;
    if(endIndex < 0)
        endIndex = dstr.length + endIndex;
    if(startIndex < 0 || startIndex >= dstr.length)
        startIndex = 0;
    if(endIndex < 0 || endIndex >= dstr.length)
        endIndex = dstr.length;
    return ScriptAny(dstr[startIndex..endIndex]);
}

private ScriptAny native_String_toLowerCase(Environment env, ScriptAny* thisObj,
                                            ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.uni : toLower;
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;
    return ScriptAny(toLower(thisObj.toString()));
}

private ScriptAny native_String_toUpperCase(Environment env, ScriptAny* thisObj,
                                            ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.uni : toUpper;
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;
    return ScriptAny(toUpper(thisObj.toString()));
}