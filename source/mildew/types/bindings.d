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
import mildew.stdlib.generator;
import mildew.stdlib.regexp;
import mildew.types.any;
import mildew.types.array;
import mildew.types.func;
import mildew.types.string;
import mildew.types.object;

/**
 * Initializes the bindings of builtin types such as Object, Function, String, and Array. This function is not
 * required because these objects already have their __proto__ set correctly when constructed.
 * Documentation for all these classes' methods can be found at https://pillager86.github.io/dmildew/
 * Params:
 *  interpreter = The Interpreter instance to load the constructor-namespaces into.
 */
void initializeTypesLibrary(Interpreter interpreter)
{
    ScriptAny Object_ctor = new ScriptFunction("Object", &native_Object_constructor, true);
    Object_ctor["prototype"] = getObjectPrototype();
    Object_ctor["prototype"]["constructor"] = Object_ctor;
    // static Object methods
    Object_ctor["assign"] = new ScriptFunction("Object.assign", &native_Object_s_assign);
    Object_ctor["create"] = new ScriptFunction("Object.create", &native_Object_s_create);
    Object_ctor["defineProperties"] = new ScriptFunction("Object.defineProperties",
            &native_Object_s_defineProperties);
    Object_ctor["defineProperty"] = new ScriptFunction("Object.defineProperty",
            &native_Object_s_defineProperty);
    Object_ctor["entries"] = new ScriptFunction("Object.entries", &native_Object_s_entries);
    Object_ctor["fromEntries"] = new ScriptFunction("Object.fromEntries", &native_Object_s_fromEntries);
    Object_ctor["getOwnPropertyDescriptor"] = new ScriptFunction("Object.getOwnPropertyDescriptor", 
            &native_Object_s_getOwnPropertyDescriptor);
    Object_ctor["getOwnPropertyDescriptors"] = new ScriptFunction("Object.getOwnPropertyDescriptors",
            &native_Object_s_getOwnPropertyDescriptors);
    Object_ctor["getOwnPropertyNames"] = new ScriptFunction("Object.getOwnPropertyNames", 
            &native_Object_s_getOwnPropertyNames);
    Object_ctor["getPrototypeOf"] = new ScriptFunction("Object.getPrototypeOf", &native_Object_s_getPrototypeOf);
    Object_ctor["is"] = new ScriptFunction("Object.is", &native_Object_s_is);
    Object_ctor["keys"] = new ScriptFunction("Object.keys", &native_Object_s_keys);
    Object_ctor["setPrototypeOf"] = new ScriptFunction("Object.setPrototypeOf", &native_Object_s_setPrototypeOf);
    Object_ctor["values"] = new ScriptFunction("Object.values", &native_Object_s_values);

    ScriptAny Array_ctor = new ScriptFunction("Array", &native_Array_ctor, true);
    Array_ctor["prototype"] = getArrayPrototype();
    Array_ctor["prototype"]["constructor"] = Array_ctor;
    Array_ctor["from"] = new ScriptFunction("Array.from", &native_Array_s_from);
    Array_ctor["isArray"] = new ScriptFunction("Array.isArray", &native_Array_s_isArray);
    Array_ctor["of"] = new ScriptFunction("Array.of", &native_Array_s_of);

    ScriptAny String_ctor = new ScriptFunction("String", &native_String_ctor, true);
    String_ctor["prototype"] = getStringPrototype();
    String_ctor["prototype"]["constructor"] = String_ctor;
    String_ctor["fromCharCode"] = new ScriptFunction("String.fromCharCode",
            &native_String_s_fromCharCode);
    String_ctor["fromCodePoint"] = new ScriptFunction("String.fromCodePoint",
            &native_String_s_fromCodePoint);

    // set the consts NaN and Infinity
    interpreter.forceSetGlobal("Infinity", ScriptAny(double.infinity), true);
    interpreter.forceSetGlobal("NaN", ScriptAny(double.nan), true);

    interpreter.forceSetGlobal("Object", Object_ctor, false); // maybe should be const
    interpreter.forceSetGlobal("Array", Array_ctor, false);
    interpreter.forceSetGlobal("String", String_ctor, false);
}

package(mildew):

ScriptObject getObjectPrototype()
{
    if(_objectPrototype is null)
    {
        _objectPrototype = new ScriptObject("object"); // this is the base prototype for all objects
        _objectPrototype["hasOwnProperty"] = new ScriptFunction("Object.prototype.hasOwnProperty",
                &native_Object_hasOwnProperty);
        _objectPrototype["isPrototypeOf"] = new ScriptFunction("Object.prototype.isPrototypeOf",
                &native_Object_isPrototypeOf);
        _objectPrototype["toString"] = new ScriptFunction("Object.prototype.toString", &native_Object_toString);
    }
    return _objectPrototype;
}

ScriptObject getArrayPrototype()
{
    if(_arrayPrototype is null)
    {
        _arrayPrototype = new ScriptObject("array", null);
        _arrayPrototype["at"] = new ScriptFunction("Array.prototype.at", &native_Array_at);
        _arrayPrototype["concat"] = new ScriptFunction("Array.prototype.concat", &native_Array_concat);
        _arrayPrototype["copyWithin"] = new ScriptFunction("Array.prototype.copyWithin",
                &native_Array_copyWithin);
        _arrayPrototype["every"] = new ScriptFunction("Array.prototype.every", &native_Array_every);
        _arrayPrototype["fill"] = new ScriptFunction("Array.prototype.fill", &native_Array_fill);
        _arrayPrototype["filter"] = new ScriptFunction("Array.prototype.filter", &native_Array_filter);
        _arrayPrototype["find"] = new ScriptFunction("Array.prototype.find", &native_Array_find);
        _arrayPrototype["findIndex"] = new ScriptFunction("Array.prototype.findIndex", &native_Array_findIndex);
        _arrayPrototype["flat"] = new ScriptFunction("Array.prototype.flat", &native_Array_flat);
        _arrayPrototype["flatMap"] = new ScriptFunction("Array.prototype.flatMap", &native_Array_flatMap);
        _arrayPrototype["forEach"] = new ScriptFunction("Array.prototype.forEach", &native_Array_forEach);
        _arrayPrototype["includes"] = new ScriptFunction("Array.prototype.includes", &native_Array_includes);
        _arrayPrototype["indexOf"] = new ScriptFunction("Array.prototype.indexOf", &native_Array_indexOf);
        _arrayPrototype["join"] = new ScriptFunction("Array.prototype.join", &native_Array_join);
        _arrayPrototype["lastIndexOf"] = new ScriptFunction("Array.prototype.lastIndexOf",
                &native_Array_lastIndexOf);
        _arrayPrototype.addGetterProperty("length", new ScriptFunction("Array.prototype.length", 
                &native_Array_p_length));
        _arrayPrototype.addSetterProperty("length", new ScriptFunction("Array.prototype.length", 
                &native_Array_p_length));
        _arrayPrototype["map"] = new ScriptFunction("Array.prototype.map", &native_Array_map);
        _arrayPrototype["pop"] = new ScriptFunction("Array.prototype.pop", &native_Array_pop);
        _arrayPrototype["push"] = new ScriptFunction("Array.prototype.push", &native_Array_push);
        _arrayPrototype["reduce"] = new ScriptFunction("Array.prototype.reduce", &native_Array_reduce);
        _arrayPrototype["reduceRight"] = new ScriptFunction("Array.prototype.reduceRight",
                &native_Array_reduceRight);
        _arrayPrototype["reverse"] = new ScriptFunction("Array.prototype.reverse", &native_Array_reverse);
        _arrayPrototype["shift"] = new ScriptFunction("Array.prototype.shift", &native_Array_shift);
        _arrayPrototype["slice"] = new ScriptFunction("Array.prototype.slice", &native_Array_slice);
        _arrayPrototype["some"] = new ScriptFunction("Array.prototype.some", &native_Array_some);
        _arrayPrototype["sort"] = new ScriptFunction("Array.prototype.sort", &native_Array_sort);
        _arrayPrototype["splice"] = new ScriptFunction("Array.prototype.splice", &native_Array_splice);
        _arrayPrototype["unshift"] = new ScriptFunction("Array.prototype.unshift", &native_Array_unshift);
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
        _functionPrototype["bind"] = new ScriptFunction("Function.prototype.bind", &native_Function_bind);
        _functionPrototype["call"] = new ScriptFunction("Function.prototype.call", &native_Function_call);
        _functionPrototype.addGetterProperty("isGenerator", new ScriptFunction("Function.prototype.isGenerator",
                &native_Function_p_isGenerator));
        _functionPrototype.addGetterProperty("length", new ScriptFunction("Function.prototype.length",
                &native_Function_p_length));
        _functionPrototype.addGetterProperty("name", new ScriptFunction("Function.prototype.name",
                &native_Function_p_name));
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
        _stringPrototype.addGetterProperty("length", new ScriptFunction("String.prototype.length", 
                &native_String_p_length));
        _stringPrototype["match"] = new ScriptFunction("String.prototype.match", &native_String_match);
        _stringPrototype["normalize"] = new ScriptFunction("String.prototype.normalize",
                &native_String_normalize);
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

// Helper methods

private ScriptAny getLocalThis(Environment env, ScriptAny func=ScriptAny.UNDEFINED)
{
    if(func && func.type == ScriptAny.Type.FUNCTION)
    {
        auto fn = func.toValue!ScriptFunction;
        if(fn.boundThis != ScriptAny.UNDEFINED)
            return fn.boundThis;
    }
    bool _; // @suppress(dscanner.suspicious.unmodified)
    ScriptAny* thisObj = env.lookupVariableOrConst("this", _);
    if(thisObj == null)
        return ScriptAny.UNDEFINED;
    return *thisObj;
}

//
// Object methods /////////////////////////////////////////////////////////////
//

private ScriptAny native_Object_constructor(Environment env, ScriptAny* thisObj, ScriptAny[] args, 
        ref NativeFunctionError nfe)
{
    if(args.length >= 1)
    {
        if(args[0].isObject)
            *thisObj = args[0];
    }
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_Object_s_assign(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(args.length < 2)
        return ScriptAny.UNDEFINED;
    if(!args[0].isObject || !args[1].isObject)
        return ScriptAny.UNDEFINED;
    auto objA = args[0].toValue!ScriptObject;
    auto objB = args[1].toValue!ScriptObject;
    foreach(k, v ; objB.dictionary)
    {
        objA.assignField(k, v);
    }
    foreach(k, v ; objB.getters)
    {
        objA.addGetterProperty(k, v);
    }    
    foreach(k, v ; objB.setters)
    {
        objA.addSetterProperty(k, v);
    }
    return ScriptAny(objA);
}

/**
 * Object.create: This can be called by the script to create a new object whose prototype is the
 * parameter.
 */
private ScriptAny native_Object_s_create(Environment env,
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

private ScriptAny native_Object_s_defineProperties(Environment env, ScriptAny* thisObj,
                                                   ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(args.length < 2 || !args[0].isObject || !args[1].isObject)
        return ScriptAny.UNDEFINED;
    auto obj = args[0].toValue!ScriptObject;
    auto propDesc = args[1].toValue!ScriptObject;
    foreach(k,v ; propDesc.dictionary)
    {
        if(v.isObject)
        {
            auto data = v.toValue!ScriptObject;
            if(data.hasOwnFieldOrProperty("value"))
            {
                obj[k] = data["value"];
            }
            else
            {
                if(data.hasOwnFieldOrProperty("get"))
                {
                    auto getter = data["get"].toValue!ScriptFunction;
                    if(getter is null)
                    {
                        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
                        return ScriptAny.UNDEFINED;
                    }
                    obj.addGetterProperty(k, getter);
                }
                if(data.hasOwnFieldOrProperty("set"))
                {
                    auto setter = data["set"].toValue!ScriptFunction;
                    if(setter is null)
                    {
                        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
                        return ScriptAny.UNDEFINED;
                    }
                    obj.addSetterProperty(k, setter);
                }
            }
        }
        else
        {
            nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
            return ScriptAny.UNDEFINED;
        }
    }
    return ScriptAny(obj);
}

private ScriptAny native_Object_s_defineProperty(Environment env, ScriptAny* thisObj,
                                                 ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(args.length < 3 || !args[0].isObject || !args[2].isObject)
        return ScriptAny.UNDEFINED;
    auto obj = args[0].toValue!ScriptObject;
    auto propName = args[1].toString();
    auto propDef = args[2].toValue!ScriptObject;

    if(propDef.hasOwnFieldOrProperty("value"))
    {
        obj[propName] = propDef["value"];
    }
    else
    {
        if(propDef.hasOwnFieldOrProperty("get"))
        {
            auto fn = propDef["get"].toValue!ScriptFunction;
            if(fn is null)
            {
                nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
                return ScriptAny.UNDEFINED;
            }
            obj.addGetterProperty(propName, fn);
        }
        if(propDef.hasOwnFieldOrProperty("set"))
        {
            auto fn = propDef["set"].toValue!ScriptFunction;
            if(fn is null)
            {
                nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
                return ScriptAny.UNDEFINED;
            }
            obj.addSetterProperty(propName, fn);
        }
    }

    return ScriptAny(obj);
}

/// Returns an array of 2-element arrays representing the key and value of each dictionary entry
private ScriptAny native_Object_s_entries(Environment env,
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

// TODO s_freeze, which will require a redo of VM mechanics. May be done once interpreted mode is removed.

private ScriptAny native_Object_s_fromEntries(Environment env, ScriptAny* thisObj,
                                              ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(args.length < 1 || args[0].type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = args[0].toValue!(ScriptAny[]);
    auto obj = new ScriptObject("object", null);
    foreach(element ; arr)
    {
        if(element.type == ScriptAny.Type.ARRAY)
        {
            auto keyValue = element.toValue!(ScriptAny[]);
            if(keyValue.length >= 2)
            {
                obj[keyValue[0].toString()] = keyValue[1];
            }
        }
    }
    return ScriptAny(obj);
}

/// Returns a possible getter or setter or value for an object
private ScriptAny native_Object_s_getOwnPropertyDescriptor(Environment env,
                                                        ScriptAny* thisObj,
                                                        ScriptAny[] args,
                                                        ref NativeFunctionError nfe)
{
    if(args.length < 2)
        return ScriptAny.UNDEFINED;
    if(!args[0].isObject)
        return ScriptAny.UNDEFINED;
    auto propName = args[1].toString();
    return ScriptAny(args[0].toValue!ScriptObject.getOwnPropertyOrFieldDescriptor(propName));
}

private ScriptAny native_Object_s_getOwnPropertyDescriptors(Environment env, ScriptAny* thisObj,
                                                            ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(args.length < 1 || !args[0].isObject)
        return ScriptAny.UNDEFINED;
    auto obj = args[0].toValue!ScriptObject;
    return ScriptAny(obj.getOwnFieldOrPropertyDescriptors());
}

private ScriptAny native_Object_s_getOwnPropertyNames(Environment env, ScriptAny* thisObj,
                                                      ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(args.length < 1 || !args[0].isObject)
        return ScriptAny.UNDEFINED;
    auto obj = args[0].toValue!ScriptObject;
    bool[string] map;
    foreach(k,v ; obj.dictionary)
        map[k] = true;
    foreach(k,v ; obj.getters)
        map[k] = true;
    foreach(k,v ; obj.setters)
        map[k] = true;
    return ScriptAny(map.keys);
}

// not sure about Object.getOwnPropertySymbols

private ScriptAny native_Object_s_getPrototypeOf(Environment env, ScriptAny* thisObj,
                                                 ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(args.length < 1 || !args[0].isObject)
        return ScriptAny.UNDEFINED;
    auto obj = args[0].toValue!ScriptObject;
    return ScriptAny(obj.prototype);
}

private ScriptAny native_Object_hasOwnProperty(Environment env, ScriptAny* thisObj,
                                               ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(!thisObj.isObject)
        return ScriptAny.UNDEFINED;
    auto obj = thisObj.toValue!ScriptObject;
    if(args.length < 1)
        return ScriptAny.UNDEFINED;
    auto propName = args[0].toString();
    return ScriptAny(obj.hasOwnFieldOrProperty(propName));
}

private ScriptAny native_Object_s_is(Environment env, ScriptAny* thisObj,
                                     ScriptAny[] args, ref NativeFunctionError nfe)
{
    /// Two non-reference values can never "is" each other
    if(args.length < 2 || !args[0].isObject || !args[1].isObject)
        return ScriptAny(false);
    auto objA = args[0].toValue!ScriptObject;
    auto objB = args[1].toValue!ScriptObject;
    return ScriptAny(objA is objB);
}

// Object.isExtensible doesn't fit the design yet

// Object.isFrozen doesn't fit the design yet

private ScriptAny native_Object_isPrototypeOf(Environment env, ScriptAny* thisObj,
                                              ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(!thisObj.isObject)
        return ScriptAny(false);
    if(args.length < 1 || !args[0].isObject)
        return ScriptAny(false);
    auto objProto = thisObj.toValue!ScriptObject;
    auto objWithProto = args[0].toValue!ScriptObject;
    return ScriptAny(objProto is objWithProto.prototype);
}

// Object.isSealed doesn't really apply yet

/// returns an array of keys of an object (or function)
private ScriptAny native_Object_s_keys(Environment env,
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

// Object.preventExtensions doesn't really apply yet

// Object.prototype.propertyIsEnumerable doesn't really apply, and may never will

// Object.seal doesn't really apply yet

private ScriptAny native_Object_s_setPrototypeOf(Environment env, ScriptAny* thisObj,
                                                 ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(args.length < 2 || !args[0].isObject)
        return ScriptAny.UNDEFINED;
    auto objToSet = args[0].toValue!ScriptObject;
    auto newProto = args[1].toValue!ScriptObject; // @suppress(dscanner.suspicious.unmodified)
    // this may set a null prototype if newProto is null
    objToSet.prototype = newProto;
    return args[0];
}

private ScriptAny native_Object_toString(Environment env, ScriptAny* thisObj,
                                         ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(!thisObj.isObject)
        return ScriptAny.UNDEFINED;
    return ScriptAny(thisObj.toString());
}

// Object.valueOf does not apply and will NEVER apply because we do not allow the "boxing" of primitive
//  values for no reason.

/// returns an array of values of an object (or function)
private ScriptAny native_Object_s_values(Environment env,
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

private ScriptAny native_Array_ctor(Environment env, ScriptAny* thisObj,
                                    ScriptAny[] args, ref NativeFunctionError nfe)
{
    ScriptAny[] result;
    if(args.length == 1 && args[0].type == ScriptAny.Type.INTEGER)
    {
        result = new ScriptAny[args[0].toValue!long];
    }
    else
    {
        foreach(arg ; args)
            result ~= arg;
    }
    *thisObj = ScriptAny(result);
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_Array_at(Environment env, ScriptAny* thisObj,
                                  ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    if(args.length < 1)
        return ScriptAny.UNDEFINED;
    auto array = thisObj.toValue!(ScriptAny[]);
    long index = args[0].toValue!long;
    if(index < 0)
        index += array.length;
    if(index < 0 || index >= array.length)
        return ScriptAny.UNDEFINED;
    return array[index];
}

private ScriptAny native_Array_concat(Environment env, ScriptAny* thisObj, 
                                      ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    if(args.length < 1)
        return *thisObj;
    ScriptAny[] result = thisObj.toValue!ScriptArray.array;
    foreach(arg ; args)
    {
        if(arg.type != ScriptAny.Type.ARRAY)
        {
            result ~= arg;
        }
        else
        {
            result ~= arg.toValue!ScriptArray.array;
        }
    }
    return ScriptAny(result);
}

private ScriptAny native_Array_copyWithin(Environment env, ScriptAny* thisObj,
                                          ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray;
    long target = args.length > 0 ? args[0].toValue!long : arr.array.length;
    long start = args.length > 1 ? args[1].toValue!long : 0;
    long end = args.length > 2 ? args[2].toValue!long : arr.array.length;
    if(target < 0 || target >= arr.array.length)
        target = arr.array.length;
    if(start < 0 || start >= arr.array.length)
        start  = 0;
    if(end < 0 || end >= arr.array.length)
        end = arr.array.length;
    if(end <= start)
        return *thisObj;
    for(long i = 0; i < (end - start); ++i)
    {
        if(i + target >= arr.array.length || i + start >= arr.array.length)
            break;
        arr.array[i+target] = arr.array[i+start];
    }
    return *thisObj;
}

// TODO: entries once Generators are a thing

private ScriptAny native_Array_every(Environment env, ScriptAny* thisObj,
                                     ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny(false);
    auto arr = thisObj.toValue!ScriptArray;
    if(args.length < 1)
        return ScriptAny(false);
    if(args[0].type != ScriptAny.Type.FUNCTION)
        return ScriptAny(false);
    auto theThisArg = args.length > 1 ? args[1] : getLocalThis(env, args[0]);
    bool result = true;
    size_t counter = 0;
    foreach(element ; arr.array)
    {
        auto temp = native_Function_call(env, &args[0], 
            [ theThisArg, element, ScriptAny(counter), *thisObj ], nfe);
        if(nfe != NativeFunctionError.NO_ERROR)
            return temp;
        result = result && temp;
        ++counter;
    }
    return ScriptAny(result);
}

private ScriptAny native_Array_fill(Environment env, ScriptAny* thisObj,
                                    ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray.array;
    if(args.length < 1)
        return *thisObj;
    // auto value = args[0]; // @suppress(dscanner.suspicious.unmodified)
    long start = args.length > 1 ? args[1].toValue!long : 0;
    long end = args.length > 2 ? args[2].toValue!long : arr.length;
    if(start < 0 || start >= arr.length)
        start = 0;
    if(end < 0 || end >= arr.length)
        end = arr.length;
    for(size_t i = start; i < end; ++i)
        arr[i] = args[0];
    return *thisObj;
}

private ScriptAny native_Array_filter(Environment env, ScriptAny* thisObj,
                                      ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray.array;
    if(args.length < 1)
        return *thisObj;
    if(args[0].type != ScriptAny.Type.FUNCTION)
        return *thisObj;
    ScriptAny thisToUse = args.length > 1 ? args[1] : getLocalThis(env, args[0]);
    ScriptAny[] result;
    size_t counter = 0;
    foreach(element ; arr)
    {
        auto temp = native_Function_call(env, &args[0], 
            [thisToUse, element, ScriptAny(counter), *thisObj], nfe);
        if(nfe != NativeFunctionError.NO_ERROR)
            return temp;
        if(temp)
            result ~= element;
        ++counter;
    }
    return ScriptAny(result);
}

private ScriptAny native_Array_find(Environment env, ScriptAny* thisObj, 
                                    ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray.array;
    if(args.length < 1)
        return ScriptAny.UNDEFINED;
    if(args[0].type != ScriptAny.Type.FUNCTION)
        return ScriptAny.UNDEFINED;
    auto thisToUse = args.length > 1 ? args[1] : getLocalThis(env, args[0]);
    for(size_t i = 0; i < arr.length; ++i)
    {
        auto temp = native_Function_call(env, &args[0], 
            [thisToUse, arr[i], ScriptAny(i), *thisObj], nfe);
        if(nfe != NativeFunctionError.NO_ERROR)
            return temp;
        if(temp)
            return arr[i];
    }

    return ScriptAny.UNDEFINED;
}

private ScriptAny native_Array_findIndex(Environment env, ScriptAny* thisObj, 
                                    ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray.array;
    if(args.length < 1)
        return ScriptAny.UNDEFINED;
    if(args[0].type != ScriptAny.Type.FUNCTION)
        return ScriptAny.UNDEFINED;
    auto thisToUse = args.length > 1 ? args[1] : ScriptAny.UNDEFINED;
    for(size_t i = 0; i < arr.length; ++i)
    {
        auto temp = native_Function_call(env, &args[0], 
            [thisToUse, arr[i], ScriptAny(i), *thisObj], nfe);
        if(nfe != NativeFunctionError.NO_ERROR)
            return temp;
        if(temp)
            return ScriptAny(i);
    }

    return ScriptAny(-1);
}

// Credit for flat and flatMap algorithm:
// https://medium.com/better-programming/javascript-tips-4-array-flat-and-flatmap-implementation-2f81e618bde
private ScriptAny native_Array_flat(Environment env, ScriptAny* thisObj,
                                    ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray.array;
    ScriptAny[] flattened;
    immutable depth = args.length > 0 ? args[0].toValue!int : 1;
    void flattener(ScriptAny[] list, int dp)
    {
        foreach(item ; list)
        {
            if(item.type == ScriptAny.Type.ARRAY && dp > 0)
            {
                flattener(item.toValue!(ScriptAny[]), dp - 1);
            }
            else
            {
                flattened ~= item;
            }
        }
    }
    flattener(arr, depth);
    return ScriptAny(flattened);
}

private ScriptAny native_Array_flatMap(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray.array;
    ScriptAny[] flattened;
    if(args.length < 1)
        return *thisObj;
    if(args[0].type != ScriptAny.Type.FUNCTION)
        return *thisObj;
    ScriptAny thisToUse = args.length > 1 ? args[1] : getLocalThis(env, args[0]);
    for(size_t i = 0; i < arr.length; ++i)
    {
        auto temp = native_Function_call(env, &args[0], [thisToUse, arr[i], ScriptAny(i), *thisObj], nfe);
        if(nfe != NativeFunctionError.NO_ERROR)
            return temp;
        if(temp.type == ScriptAny.Type.ARRAY)
        {
            foreach(element ; temp.toValue!ScriptArray.array)
                flattened ~= element;
        }
    }
    return ScriptAny(flattened);
}

private ScriptAny native_Array_forEach(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray.array;
    if(args.length < 1)
        return ScriptAny.UNDEFINED;
    if(args[0].type != ScriptAny.Type.FUNCTION)
        return ScriptAny.UNDEFINED;
    auto thisToUse = args.length > 1 ? args[1] : getLocalThis(env, args[0]);
    for(size_t i = 0; i < arr.length; ++i)
    {
        auto temp = native_Function_call(env, &args[0],
            [thisToUse, arr[i], ScriptAny(i), *thisObj], nfe);
        if(nfe != NativeFunctionError.NO_ERROR)
            return temp;
    }
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_Array_s_from(Environment env, ScriptAny* thisObj,
                                      ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(cast(ScriptAny[])[]);
    ScriptAny func = args.length > 1 ? args[1] : ScriptAny.UNDEFINED;
    auto thisToUse = args.length > 2 ? args[2] : getLocalThis(env, func);
    
    ScriptAny[] result;
    if(args[0].type == ScriptAny.Type.ARRAY)
    {
        auto arr = args[0].toValue!ScriptArray.array;
        for(size_t i = 0; i < arr.length; ++i)
        {
            if(func.type == ScriptAny.Type.FUNCTION)
            {
                auto temp = native_Function_call(env, &func, [thisToUse, arr[i], ScriptAny(i), args[0]], nfe);
                if(nfe != NativeFunctionError.NO_ERROR)
                    return temp;
                result ~= temp;
            }
            else
            {
                result ~= arr[i];
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
                if(nfe != NativeFunctionError.NO_ERROR)
                    return temp;
                result ~= temp;
            }
            else
            {
                result ~= ScriptAny([ch]);
            }
            ++index;
        }       
    }

    return ScriptAny(result);
}

private ScriptAny native_Array_includes(Environment env, ScriptAny* thisObj,
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny(false);
    auto arr = thisObj.toValue!ScriptArray.array;
    if(args.length < 1)
        return ScriptAny(false);
    long indexToStart = args.length > 1 ? args[1].toValue!long : 0;
    if(indexToStart < 0)
        indexToStart = args.length + indexToStart;
    if(indexToStart < 0 || indexToStart >= arr.length)
        indexToStart = arr.length;
    for(size_t i = indexToStart; i < arr.length; ++i)
        if(args[0].strictEquals(arr[i]))
            return ScriptAny(true);
    return ScriptAny(false);
}


private ScriptAny native_Array_indexOf(Environment env, ScriptAny* thisObj,
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray.array;
    if(args.length < 1)
        return ScriptAny(-1);
    long indexToStart = args.length > 1 ? args[1].toValue!long : 0;
    if(indexToStart < 0)
        indexToStart = args.length + indexToStart;
    if(indexToStart < 0 || indexToStart >= arr.length)
        indexToStart = arr.length;
    for(size_t i = indexToStart; i < arr.length; ++i)
        if(args[0].strictEquals(arr[i]))
            return ScriptAny(i);
    return ScriptAny(-1);
}

private ScriptAny native_Array_s_isArray(Environment env, ScriptAny* thisObj,
                                         ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(false);
    return ScriptAny(args[0].type == ScriptAny.Type.ARRAY);
}

private ScriptAny native_Array_join(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
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

// TODO Array.prototype.keys once Generators are a thing

private ScriptAny native_Array_lastIndexOf(Environment env, ScriptAny* thisObj,
                                           ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray.array;
    if(args.length < 1)
        return ScriptAny(-1);
    long indexToStart = args.length > 1 ? args[1].toValue!long : arr.length - 1;
    if(indexToStart < 0)
        indexToStart = args.length + indexToStart;
    if(indexToStart < 0 || indexToStart >= arr.length)
        indexToStart = arr.length - 1;
    for(size_t i = indexToStart; i >= 0; --i)
    {
        if(i < arr.length && args[0].strictEquals(arr[i]))
            return ScriptAny(i);
    }
    return ScriptAny(-1);    
}

private ScriptAny native_Array_p_length(Environment env, ScriptAny* thisObj,
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    if(args.length >= 1)
    {
        auto actualArray = thisObj.toValue!ScriptArray;
        immutable length = args[0].toValue!long;
        actualArray.array.length = length;
        return ScriptAny(actualArray.array.length);
    }
    else
    {
        auto arr = thisObj.toValue!(ScriptAny[]);
        return ScriptAny(arr.length);
    }
}

private ScriptAny native_Array_map(Environment env, ScriptAny* thisObj,
                                   ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray.array;
    if(args.length < 1)
        return *thisObj;
    if(args[0].type != ScriptAny.Type.FUNCTION)
        return *thisObj;
    ScriptAny thisToUse = args.length > 1 ? args[1] : ScriptAny.UNDEFINED;
    ScriptAny[] result;
    for(size_t i = 0; i < arr.length; ++i)
    {
        auto temp = native_Function_call(env, &args[0], 
            [thisToUse, arr[i], ScriptAny(i), *thisObj], nfe);
        if(nfe != NativeFunctionError.NO_ERROR)
            return temp;
        result ~= temp;
    }
    return ScriptAny(result);
}

private ScriptAny native_Array_s_of(Environment env, ScriptAny* thisObj,
                                    ScriptAny[] args, ref NativeFunctionError nfe)
{
    ScriptAny[] results;
    foreach(arg ; args)
        results ~= arg;
    return ScriptAny(results);
}

private ScriptAny native_Array_push(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    if(args.length < 0)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray;
    arr.array ~= args[0];
    return ScriptAny(arr.array.length);
}

private ScriptAny native_Array_pop(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
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

private ScriptAny native_Array_reduce(Environment env, ScriptAny* thisObj,
                                      ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray.array;
    if(args.length < 0 || args[0].type != ScriptAny.Type.FUNCTION)
        return ScriptAny.UNDEFINED;
    ScriptAny accumulator = args.length > 1 ? args[1] : (arr.length > 0? arr[0] : ScriptAny.UNDEFINED);
    immutable start = accumulator == ScriptAny.UNDEFINED ? 0 : 1;
    for(size_t i = start; i < arr.length; ++i)
    {
        accumulator = native_Function_call(env, &args[0], 
            [getLocalThis(env, args[0]), accumulator, arr[i], ScriptAny(i), *thisObj], nfe);
        if(nfe != NativeFunctionError.NO_ERROR)
            return accumulator;
    }
    return accumulator;
}

private ScriptAny native_Array_reduceRight(Environment env, ScriptAny* thisObj,
                                      ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray.array;
    if(args.length < 0 || args[0].type != ScriptAny.Type.FUNCTION)
        return ScriptAny.UNDEFINED;
    ScriptAny accumulator = args.length > 1 ? args[1] : (arr.length > 0? arr[arr.length-1] : ScriptAny.UNDEFINED);
    immutable long start = accumulator == ScriptAny.UNDEFINED ? arr.length : cast(long)arr.length - 1;
    if(start < 0)
        return ScriptAny.UNDEFINED;
    for(size_t i = start; i > 0; --i)
    {
        accumulator = native_Function_call(env, &args[0], 
            [getLocalThis(env, args[0]), accumulator, arr[i-1], ScriptAny(i-1), *thisObj], nfe);
        if(nfe != NativeFunctionError.NO_ERROR)
            return accumulator;
    }
    return accumulator;
}

private ScriptAny native_Array_reverse(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.algorithm.mutation: reverse;
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray;
    reverse(arr.array);
    return *thisObj;
}

private ScriptAny native_Array_shift(Environment env, ScriptAny* thisObj,
                                     ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray;
    if(arr.array.length < 1)
        return ScriptAny.UNDEFINED;
    auto removed = arr.array[0];
    arr.array = arr.array[1..$];
    return removed;
}

private ScriptAny native_Array_slice(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto array = thisObj.toValue!(ScriptAny[]);
    long start = args.length > 0 ? args[0].toValue!long : 0;
    long end = args.length > 1 ? args[1].toValue!long : array.length;
    if(start < 0)
        start = array.length + start;
    if(end < 0)
        end = array.length + end;
    if(start < 0 || start >= array.length)
        start = 0;
    if(end < 0 || end > array.length)
        end = array.length;
    return ScriptAny(array[start .. end]);
}

private ScriptAny native_Array_some(Environment env, ScriptAny* thisObj, 
                                    ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    if(args.length < 1 || args[0].type != ScriptAny.Type.FUNCTION)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray.array;
    ScriptAny thisToUse = args.length > 1 ? args[1] : getLocalThis(env, args[0]);
    for(size_t i = 0; i < arr.length; ++i)
    {
        auto temp = native_Function_call(env, &args[0], 
            [thisToUse, arr[i], ScriptAny(i), *thisObj], nfe);
        if(nfe != NativeFunctionError.NO_ERROR || temp)
            return temp;
    }
    return ScriptAny(false);
}

private ScriptAny native_Array_sort(Environment env, ScriptAny* thisObj,
                                    ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.algorithm: sort;
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray;
    if(arr.array.length <= 1)
        return *thisObj;
    if(args.length < 1 || args[0].type != ScriptAny.Type.FUNCTION)
    {
        sort(arr.array);
    }
    else
    {
        // use bubble sort
        for(size_t i = 0; i < arr.length-1; ++i)
        {
            for(size_t j = 0; j < arr.length - i - 1; ++j)
            {
                auto temp = native_Function_call(env, &args[0], 
                    [getLocalThis(env, args[0]), arr.array[j], arr.array[j+1]], nfe);
                if(nfe != NativeFunctionError.NO_ERROR)
                    return temp;
                if(temp.toValue!int > 0)
                {
                    auto swap = arr.array[j+1]; // @suppress(dscanner.suspicious.unmodified)
                    arr.array[j+1] = arr.array[j];
                    arr.array[j] = swap;
                }
            }
        }
    }
    return *thisObj;
}

private ScriptAny native_Array_splice(Environment env, ScriptAny* thisObj, 
                                      ScriptAny[] args, ref NativeFunctionError nfe)
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

private ScriptAny native_Array_unshift(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.ARRAY)
        return ScriptAny.UNDEFINED;
    auto arr = thisObj.toValue!ScriptArray;
    arr.array = args ~ arr.array;
    return ScriptAny(arr.length);
}

//
// Function methods ///////////////////////////////////////////////////////////
//

private ScriptAny native_Function_apply(Environment env, ScriptAny* thisIsFn, ScriptAny[] args,
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
        if(fn.isGenerator)
        {
            auto obj = new ScriptObject("Generator", getGeneratorPrototype, new ScriptGenerator(
                env, fn, argList, thisToUse));
            return ScriptAny(obj);
        }
        else
        {
            auto interpreter = env.interpreter;
            if(interpreter is null)
            {
                nfe = NativeFunctionError.RETURN_VALUE_IS_EXCEPTION;
                return ScriptAny("Interpreter was improperly created without global environment");
            }
            if(interpreter.usingVM)
            {
                if(fn.type == ScriptFunction.Type.SCRIPT_FUNCTION)
                    return interpreter.vm.runFunction(fn, thisToUse, args);
                else if(fn.type == ScriptFunction.Type.NATIVE_FUNCTION)
                    return fn.nativeFunction()(env, &thisToUse, argList, nfe);
                else if(fn.type == ScriptFunction.Type.NATIVE_DELEGATE)
                    return fn.nativeDelegate()(env, &thisToUse, argList, nfe);
            }
            return interpreter.callFunction(fn, thisToUse, argList);
        }
    }
    catch(ScriptRuntimeException ex)
    {
        nfe = NativeFunctionError.RETURN_VALUE_IS_EXCEPTION;
        return ScriptAny(ex.msg);
    }
}

private ScriptAny native_Function_bind(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.FUNCTION)
        return ScriptAny.UNDEFINED;
    auto fn = thisObj.toValue!ScriptFunction;
    ScriptAny newBinding = args.length > 0 ? args[0] : ScriptAny.UNDEFINED;
    fn.bind(newBinding);
    return ScriptAny.UNDEFINED;
}

/**
 * This function provides a way for Mildew functions to be called with arbitrary "this"
 * objects. This function is public so that there is a common interface for calling ScriptFunctions
 * without worrying about the underlying details.
 *
 * Params:
 *  env = Since this function is to be called from other native functions, this should be the Environment object
 *        received. The underlying function handlers will handle the closure data of ScriptFunctions.
 *  thisIfFn = This should be a ScriptAny pointer of the ScriptFunction to be called.
 *  args = An array of arguments to call the function with, but the first element must be the "this" object to use.
 *  nfe = Since this function is to be called from native ScriptFunction implementations, this should be the same
 *        NativeFunctionError reference. This must always be checked after using native_Function_call directly.
 *
 * Returns:
 *  The return value of calling the ScriptFunction.
 */
ScriptAny native_Function_call(Environment env, ScriptAny* thisIsFn, ScriptAny[] args, 
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
        if(fn.isGenerator)
        {
            auto obj = new ScriptObject("Generator", getGeneratorPrototype, new ScriptGenerator(
                env, fn, args, thisToUse));
            return ScriptAny(obj);
        }
        else
        {
            auto interpreter = env.interpreter;
            if(interpreter is null)
            {
                nfe = NativeFunctionError.RETURN_VALUE_IS_EXCEPTION;
                return ScriptAny("Interpreter was improperly created without global environment");
            }
            if(interpreter.usingVM)
            {
                if(fn.type == ScriptFunction.Type.SCRIPT_FUNCTION)
                    return interpreter.vm.runFunction(fn, thisToUse, args);
                else if(fn.type == ScriptFunction.Type.NATIVE_FUNCTION)
                    return fn.nativeFunction()(env, &thisToUse, args, nfe);
                else if(fn.type == ScriptFunction.Type.NATIVE_DELEGATE)
                    return fn.nativeDelegate()(env, &thisToUse, args, nfe);
            }
            return interpreter.callFunction(fn, thisToUse, args);
        }
    }
    catch(ScriptRuntimeException ex)
    {
        nfe = NativeFunctionError.RETURN_VALUE_IS_EXCEPTION;
        return ScriptAny(ex.msg);
    }
}

private ScriptAny native_Function_p_isGenerator(Environment env, ScriptAny* thisObj,
                                                ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.FUNCTION)
        return ScriptAny(false);
    auto func = thisObj.toValue!ScriptFunction;
    return ScriptAny(func.isGenerator);
}

private ScriptAny native_Function_p_length(Environment env, ScriptAny* thisObj,
                                           ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.FUNCTION)
        return ScriptAny(0);
    auto func = thisObj.toValue!ScriptFunction;
    return ScriptAny(func.argNames.length);
}

private ScriptAny native_Function_p_name(Environment env, ScriptAny* thisObj,
                                         ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.FUNCTION)
        return ScriptAny("");
    auto func = thisObj.toValue!ScriptFunction;
    return ScriptAny(func.functionName);
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

private ScriptAny native_String_charAt(Environment env, ScriptAny* thisObj,
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

private ScriptAny native_String_p_length(Environment env, ScriptAny* thisObj,
                                         ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;
    auto str = thisObj.toString();
    return ScriptAny(str.length);
}

private ScriptAny native_String_match(Environment env, ScriptAny* thisObj,
                                      ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(thisObj.type != ScriptAny.Type.STRING || args.length < 1)
        return ScriptAny(null);
    ScriptRegExp regExp = args[0].toNativeObject!ScriptRegExp;
    if(regExp is null)
        return ScriptAny(null);
    return ScriptAny(regExp.match(thisObj.toString()));
}

// TODO matchAll once generators and RegExp.matchAll are.

private ScriptAny native_String_normalize(Environment env, ScriptAny* thisObj,
                                          ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.uni: normalize, NFC, NFD, NFKC, NFKD;
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;
    if(args.length < 1)
        return ScriptAny(normalize(thisObj.toString()));
    auto form = args[0].toString(); // @suppress(dscanner.suspicious.unmodified)
    if(form == "NFD")
        return ScriptAny(normalize!NFD(thisObj.toString()));
    else if(form == "NFKC")
        return ScriptAny(normalize!NFKC(thisObj.toString()));
    else if(form == "NFKD")
        return ScriptAny(normalize!NFKD(thisObj.toString()));
    else
        return ScriptAny(normalize!NFC(thisObj.toString())); 
}

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

// String.raw is a Lexer directive not a method

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

private ScriptAny native_String_replace(Environment env, ScriptAny* thisObj,
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    import std.array: replaceFirst;
    import std.string: indexOf;

    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;
    if(args.length < 2)
        return *thisObj;
    
    auto thisString = thisObj.toString();

    if(args[0].isNativeObjectType!ScriptRegExp)
    {
        auto regex = args[0].toNativeObject!ScriptRegExp;
        if(args[1].type == ScriptAny.Type.FUNCTION)
        {
            auto match = regex.match(thisString);
            foreach(mat ; match)
            {
                auto send = [getLocalThis(env, args[1]), ScriptAny(mat)];
                send ~= ScriptAny(thisString.indexOf(mat));
                send ~= ScriptAny(thisString);
                auto replacement = native_Function_call(env, &args[1], send, nfe);
                if(nfe != NativeFunctionError.NO_ERROR)
                    return replacement;
                thisString = replaceFirst(thisString, mat, replacement.toString());
            }
            return ScriptAny(thisString);
        }
        else
        {
            auto substr = args[1].toString();
            return ScriptAny(regex.replaceFirst(thisString, substr));
        }
    }
    else
    {
        auto substr = args[0].toString;
        if(args[1].type == ScriptAny.Type.FUNCTION)
        {
            immutable index = thisString.indexOf(substr);
            if(index == -1)
                return ScriptAny(thisString);
            auto replacement = native_Function_call(env, &args[1], [
                    getLocalThis(env, args[1]),
                    ScriptAny(substr),
                    ScriptAny(index),
                    ScriptAny(thisString)
            ], nfe);
            if(nfe != NativeFunctionError.NO_ERROR)
                return replacement;
            thisString = replaceFirst(thisString, substr, replacement.toString);
            return ScriptAny(thisString);
        }
        else
        {
            return ScriptAny(replaceFirst(thisObj.toString, substr, args[1].toString));
        }
    }
}

private ScriptAny native_String_replaceAll(Environment env, ScriptAny* thisObj,
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
import std.array: replace;
    import std.string: indexOf;

    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;
    if(args.length < 2)
        return *thisObj;
    
    auto thisString = thisObj.toString();

    if(args[0].isNativeObjectType!ScriptRegExp)
    {
        auto regex = args[0].toNativeObject!ScriptRegExp;
        if(args[1].type == ScriptAny.Type.FUNCTION)
        {
            auto matches = regex.matchAll(thisString);
            foreach(match ; matches)
            {
                auto send = [getLocalThis(env, args[1]), ScriptAny(match.hit)];
                foreach(group ; match)
                    send ~= ScriptAny(group);
                send ~= ScriptAny(match.pre.length);
                send ~= ScriptAny(thisString);
                auto replacement = native_Function_call(env, &args[1], send, nfe);
                if(nfe != NativeFunctionError.NO_ERROR)
                    return replacement;
                thisString = replace(thisString, match.hit, replacement.toString());
            }
            return ScriptAny(thisString);
        }
        else
        {
            auto substr = args[1].toString();
            return ScriptAny(regex.replace(thisString, substr));
        }
    }
    else
    {
        auto substr = args[0].toString;
        if(args[1].type == ScriptAny.Type.FUNCTION)
        {
            while(true)
            {
                immutable index = thisString.indexOf(substr);
                if(index == -1)
                    break;
                auto replacement = native_Function_call(env, &args[1], [
                        getLocalThis(env, args[1]),
                        ScriptAny(substr),
                        ScriptAny(index),
                        ScriptAny(thisString)
                ], nfe);
                if(nfe != NativeFunctionError.NO_ERROR)
                    return replacement;
                thisString = replace(thisString, substr, replacement.toString);
                if(replacement.toString() == substr)
                    break;
            }
            return ScriptAny(thisString);
        }
        else
        {
            return ScriptAny(replace(thisObj.toString, substr, args[1].toString));
        }
    }
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
    import std.conv: to;
    if(thisObj.type != ScriptAny.Type.STRING)
        return ScriptAny.UNDEFINED;
    auto splitter = ",";
    if(args.length > 0)
        splitter = args[0].toString();
    string[] splitResult;
    splitResult = thisObj.toString().split(splitter);
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