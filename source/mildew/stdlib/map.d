/**
This module implements the Mildew Map class, which allows all Mildew types to serve as a key in a hash map.
See https://pillager86.github.io/dmildew/Map.html for usage.

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
module mildew.stdlib.map;

import mildew.environment;
import mildew.interpreter;
import mildew.types;

/// D class wrapper around a hash map that can be stored in ScriptObject's nativeObject field
class ScriptMap
{
    /// the entries
    ScriptAny[ScriptAny] entries;

    override string toString() const 
    {
        import std.conv: to;
        return "Map (" ~ entries.length.to!string ~ ")";
    }
}

/** 
 * Initializes the Map class in the scripts. Documentation for usage can be found at
 * https://pillager86.github.io/dmildew/Map.html
 * Params:
 *  interpreter = The Interpreter instance to load the Map constructor as a global into.
 */
void initializeMapLibrary(Interpreter interpreter)
{
    ScriptAny ctor = new ScriptFunction("Map", &native_Map_ctor, true);
    ctor["prototype"] = getMapPrototype();
    ctor["prototype"]["constructor"] = ctor;
    interpreter.forceSetGlobal("Map", ctor);
}

private ScriptObject _mapPrototype;

private ScriptObject getMapPrototype()
{
    if(_mapPrototype is null)
    {
        _mapPrototype = new ScriptObject("Map", null);
        _mapPrototype["clear"] = new ScriptFunction("Map.prototype.clear", &native_Map_clear);
        _mapPrototype["delete"] = new ScriptFunction("Map.prototype.delete", &native_Map_delete);
        _mapPrototype["entries"] = new ScriptFunction("Map.prototype.entries", &native_Map_entries);
        _mapPrototype["forEach"] = new ScriptFunction("Map.prototype.forEach", &native_Map_forEach);
        _mapPrototype["get"] = new ScriptFunction("Map.prototype.get", &native_Map_get);
        _mapPrototype["has"] = new ScriptFunction("Map.prototype.has", &native_Map_has);
        _mapPrototype["keys"] = new ScriptFunction("Map.prototype.keys", &native_Map_keys);
        _mapPrototype.addGetterProperty("length", new ScriptFunction("Map.prototype.length", &native_Map_p_length));
        _mapPrototype["set"] = new ScriptFunction("Map.prototype.set", &native_Map_set);
        _mapPrototype["values"] = new ScriptFunction("Map.prototype.values", &native_Map_values);

    }
    return _mapPrototype;
}

private ScriptAny native_Map_ctor(Environment env, ScriptAny* thisObj,
                                  ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(!thisObj.isObject)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    thisObj.toValue!ScriptObject().nativeObject = new ScriptMap();
    return ScriptAny.UNDEFINED; // could return this for Map() usage.
}

private ScriptAny native_Map_clear(Environment env, ScriptAny* thisObj,
                                   ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto map = thisObj.toNativeObject!ScriptMap;
    if(map is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    map.entries.clear();
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_Map_delete(Environment env, ScriptAny* thisObj,
                                    ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto map = thisObj.toNativeObject!ScriptMap;
    if(map is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    immutable bool removed = (args[0] in map.entries) != null;
    map.entries.remove(args[0]);
    return ScriptAny(removed);
}

private ScriptAny native_Map_entries(Environment env, ScriptAny* thisObj,
                                     ScriptAny[] args, ref NativeFunctionError nfe)
{
    import mildew.stdlib.generator: ScriptGenerator, getGeneratorPrototype;

    auto map = thisObj.toNativeObject!ScriptMap; // @suppress(dscanner.suspicious.unmodified)
    if(map is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    auto func = new ScriptFunction("Iterator", 
        cast(NativeFunction)(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe){
            import std.concurrency: yield;
            auto map = args[0].toNativeObject!ScriptMap;
                foreach(key, value ; map.entries)
                {
                    ScriptAny[] entry = [key, value];
                    yield!ScriptAny(ScriptAny(entry));
                }
                return ScriptAny.UNDEFINED;
        });
    auto generator = new ScriptGenerator(env, func, [ *thisObj ] );
    auto obj = new ScriptObject("Iterator", getGeneratorPrototype, generator);
    return ScriptAny(obj);
}

private ScriptAny native_Map_forEach(Environment env, ScriptAny* thisObj,
                                     ScriptAny[] args, ref NativeFunctionError nfe)
{
    import mildew.types.bindings: native_Function_call, getLocalThis;

    auto map = thisObj.toNativeObject!ScriptMap;
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    if(map is null || args[0].type != ScriptAny.Type.FUNCTION)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    ScriptAny thisToUse;
    if(args.length > 1)
        thisToUse = args[1];
    else
        thisToUse = getLocalThis(env, args[0]);
    foreach(key, value ; map.entries)
    {
        auto temp = native_Function_call(env, &args[0], [thisToUse, value, key, *thisObj], nfe);
        if(env.g.interpreter.vm.hasException)
            return temp;
        if(nfe != NativeFunctionError.NO_ERROR)
            return temp;
    }
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_Map_get(Environment env, ScriptAny* thisObj,
                                 ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto map = thisObj.toNativeObject!ScriptMap; // @suppress(dscanner.suspicious.unmodified)
    if(map is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    auto resultPtr = args[0] in map.entries;
    if(resultPtr == null)
        return ScriptAny.UNDEFINED;
    return *resultPtr;
}

private ScriptAny native_Map_has(Environment env, ScriptAny* thisObj,
                                 ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto map = thisObj.toNativeObject!ScriptMap; // @suppress(dscanner.suspicious.unmodified)
    if(map is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    auto resultPtr = args[0] in map.entries; // @suppress(dscanner.suspicious.unmodified)
    if(resultPtr == null)
        return ScriptAny(false);
    return ScriptAny(true);
}

private ScriptAny native_Map_keys(Environment env, ScriptAny* thisObj,
                                     ScriptAny[] args, ref NativeFunctionError nfe)
{
    import mildew.stdlib.generator: ScriptGenerator, getGeneratorPrototype;

    auto map = thisObj.toNativeObject!ScriptMap; // @suppress(dscanner.suspicious.unmodified)
    if(map is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    auto func = new ScriptFunction("Iterator", 
        cast(NativeFunction)(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe){
            import std.concurrency: yield;
            auto map = args[0].toNativeObject!ScriptMap;
                foreach(key ; map.entries.keys)
                {
                    yield!ScriptAny(key);
                }
                return ScriptAny.UNDEFINED;
        });
    auto generator = new ScriptGenerator(env, func, [ *thisObj ] );
    auto obj = new ScriptObject("Iterator", getGeneratorPrototype, generator);
    return ScriptAny(obj);
}

private ScriptAny native_Map_p_length(Environment env, ScriptAny* thisObj,
                                      ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto map = thisObj.toNativeObject!ScriptMap;
    if(map is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    return ScriptAny(map.entries.length);
}

private ScriptAny native_Map_set(Environment env, ScriptAny* thisObj,
                                 ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto map = thisObj.toNativeObject!ScriptMap; // @suppress(dscanner.suspicious.unmodified)
    if(map is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    if(args.length < 2)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    map.entries[args[0]] = args[1];
    return *thisObj;
}

private ScriptAny native_Map_values(Environment env, ScriptAny* thisObj,
                                     ScriptAny[] args, ref NativeFunctionError nfe)
{
    import mildew.stdlib.generator: ScriptGenerator, getGeneratorPrototype;

    auto map = thisObj.toNativeObject!ScriptMap; // @suppress(dscanner.suspicious.unmodified)
    if(map is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    auto func = new ScriptFunction("Iterator", 
        cast(NativeFunction)(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe){
            import std.concurrency: yield;
            auto map = args[0].toNativeObject!ScriptMap;
                foreach(value ; map.entries.values)
                {
                    yield!ScriptAny(value);
                }
                return ScriptAny.UNDEFINED;
        });
    auto generator = new ScriptGenerator(env, func, [ *thisObj ] );
    auto obj = new ScriptObject("Iterator", getGeneratorPrototype, generator);
    return ScriptAny(obj);
}