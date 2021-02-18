/**
This module implements Generators for the Mildew scripting language.

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
module mildew.stdlib.generator;

import std.concurrency;

import mildew.environment;
import mildew.exceptions;
import mildew.interpreter;
import mildew.types;
import mildew.vm;

/// Generator class
class ScriptGenerator : Generator!ScriptAny
{
    /// ctor
    this(Environment env, ScriptFunction func, ScriptAny[] args, ScriptAny thisObj = ScriptAny.UNDEFINED)
    {
        // first get the thisObj
        bool _; // @suppress(dscanner.suspicious.unmodified)
        if(thisObj == ScriptAny.UNDEFINED)
        {
            if(func.boundThis)
            {
                thisObj = func.boundThis;
            }
            if(func.closure && func.closure.variableOrConstExists("this"))
            {
                thisObj = *func.closure.lookupVariableOrConst("this", _);
            }
            else if(env.variableOrConstExists("this"))
            {
                thisObj = *env.lookupVariableOrConst("this", _);
            }
            // else it's undefined and that's ok
        }

        // next get a VM copy that will live in the following closure
        if(env.getGlobalEnvironment.interpreter.vm is null)
            throw new Exception("Generators may only be used in VM mode");
        auto vm = env.getGlobalEnvironment.interpreter.vm.copy();

        _name = func.functionName;

        super({
            _returnValue = vm.runFunction(func, thisObj, args, ScriptAny(new ScriptFunction("yield",
                    &this.native_yield)));
        });
    }

    override string toString() const 
    {
        return "Generator " ~ _name;
    }
private:

    ScriptAny native_yield(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
    {
        if(args.length < 1)
            .yield!ScriptAny(ScriptAny());
        else
            .yield!ScriptAny(args[0]);
        auto result = this._yieldValue;
        this._yieldValue = ScriptAny.UNDEFINED;
        return result;
    }

    string _name;
    bool _markedAsFinished = false;
    ScriptAny _yieldValue;
    ScriptAny _returnValue;
}

/// initialize the Generator library
void initializeGeneratorLibrary(Interpreter interpreter)
{
    ScriptAny ctor = new ScriptFunction("Generator", &native_Generator_ctor, true);
    ctor["prototype"] = getGeneratorPrototype();
    ctor["prototype"]["constructor"] = ctor;
    interpreter.forceSetGlobal("Generator", ctor, false);
}

private ScriptObject _generatorPrototype;

/// Gets the Generator prototype. The VM will eventually need this.
ScriptObject getGeneratorPrototype()
{
    if(_generatorPrototype is null)
    {
        _generatorPrototype = new ScriptObject("Generator", null);
        _generatorPrototype.addGetterProperty("name", new ScriptFunction("Generator.prototype.name",
                &native_Generator_p_name));
        _generatorPrototype["next"] = new ScriptFunction("Generator.prototype.next",
                &native_Generator_next);
        _generatorPrototype["return"] = new ScriptFunction("Generator.prototype.return",
                &native_Generator_return);
        _generatorPrototype.addGetterProperty("returnValue", new ScriptFunction("Generator.prototype.returnValue",
                &native_Generator_p_returnValue));
    }
    return _generatorPrototype;
}

private ScriptAny native_Generator_ctor(Environment env, ScriptAny* thisObj,
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(args.length < 1 || args[0].type != ScriptAny.Type.FUNCTION)
    {
        nfe = NativeFunctionError.RETURN_VALUE_IS_EXCEPTION;
        return ScriptAny("First argument to new Generator() must exist and be a Function");
    }
    if(!thisObj.isObject)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    auto obj = thisObj.toValue!ScriptObject;
    obj.nativeObject = new ScriptGenerator(env, args[0].toValue!ScriptFunction, args[1..$]);
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_Generator_p_name(Environment env, ScriptAny* thisObj,
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto thisGen = thisObj.toNativeObject!ScriptGenerator;
    if(thisGen is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    return ScriptAny(thisGen._name);
}

/// This is public for opIter
ScriptAny native_Generator_next(Environment env, ScriptAny* thisObj,
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto thisGen = thisObj.toNativeObject!ScriptGenerator;
    if(thisGen is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    auto valueToYield = args.length > 0 ? args[0] : ScriptAny.UNDEFINED; // @suppress(dscanner.suspicious.unmodified)
    thisGen._yieldValue = valueToYield;

    if(thisGen._markedAsFinished)
    {
        nfe = NativeFunctionError.RETURN_VALUE_IS_EXCEPTION;
        return ScriptAny("Cannot call next on a finished Generator");
    }
    if(!thisGen.empty)
    {
        auto obj = new ScriptObject("iteration", null);
        obj["done"] = ScriptAny(false);
        obj["value"] = thisGen.front();
        try 
        {
            thisGen.popFront();
        }
        catch(ScriptRuntimeException ex)
        {
            thisGen._markedAsFinished = true;
            return ScriptAny.UNDEFINED;
        }
        return ScriptAny(obj);
    }
    else
    {
        thisGen._markedAsFinished = true;
        auto obj = new ScriptObject("iteration", null);
        obj["done"] = ScriptAny(true);
        return ScriptAny(obj);
    }
}

private ScriptAny native_Generator_return(Environment env, ScriptAny* thisObj,
                                          ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto thisGen = thisObj.toNativeObject!ScriptGenerator;
    if(thisGen is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    ScriptAny retVal = args.length > 0 ? args[0] : ScriptAny.UNDEFINED; // @suppress(dscanner.suspicious.unmodified)
    if(thisGen._markedAsFinished)
    {
        nfe = NativeFunctionError.RETURN_VALUE_IS_EXCEPTION;
        return ScriptAny("Cannot call return on a finished Generator");
    }
    while(!thisGen.empty)
    {
        try 
        {
            thisGen.popFront();
        }
        catch(ScriptRuntimeException ex)
        {
            thisGen._markedAsFinished = true;
            return ScriptAny.UNDEFINED;
        }
    }
    thisGen._markedAsFinished = true;
    auto obj = new ScriptObject("iteration", null);
    obj["value"] = retVal;
    obj["done"] = ScriptAny(true);
    return ScriptAny(obj);
}

// we are not adding throw I've ripped up the Lexer enough as it is

private ScriptAny native_Generator_p_returnValue(Environment env, ScriptAny* thisObj,
                                               ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto thisGen = thisObj.toNativeObject!ScriptGenerator;
    if(thisGen is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    return thisGen._returnValue;
}

