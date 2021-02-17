/*
This module implements the Mildew RegExp class.

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
module mildew.stdlib.regexp;

static import std.regex;

import mildew.environment;
import mildew.interpreter;
import mildew.types;

/**
 * Class that encapsulates regular expressions. The D struct Regex cannot be directly stored in a ScriptObject
 */
class ScriptRegExp
{
public:
    /// ctor
    this(in string pattern, in string flags="")
    {
        _regex = std.regex.regex(pattern, flags);

        _source = pattern;

        char[] unsortedFlags = flags.dup;
        if(flags.length > 0)
        {
            for(size_t i = 0; i < unsortedFlags.length - 1; ++i)
            {
                for(size_t j = 0; j < unsortedFlags.length - i - 1; ++j)
                {
                    if(unsortedFlags[j] > unsortedFlags[j+1])
                    {
                        immutable swap = unsortedFlags[j];
                        unsortedFlags[j] = unsortedFlags[j+1];
                        unsortedFlags[j+1] = swap;
                    }
                }
            }
        }
        _flags = cast(string)unsortedFlags;
    }

    /// flags property
    string flags() const { return _flags; }

    /// last index property
    size_t lastIndex() const { return _lastIndex; }
    /// last index property
    size_t lastIndex(size_t li)
    {
        return _lastIndex = li;
    }

    /// source property
    string source() const { return _source; }

    /// whether or not 's' flag was used
    bool dotAll() const 
    {
        foreach(ch ; _flags)
            if(ch == 's') return true;
        return false;
    }

    /// whether or not 'g' flag was used
    bool global() const 
    {
        foreach(ch ; _flags)
            if(ch == 'g') return true;
        return false;
    }

    /// whether or not 'i' flag was used
    bool ignoreCase() const
    {
        foreach(ch ; _flags)
            if(ch == 'i') return true;
        return false;
    }

    /// whether or not 'm' flag was used
    bool multiline() const 
    {
        foreach(ch ; _flags)
            if(ch == 'm') return true;
        return false;
    }

    /// returns match
    auto match(string str)
    {
        auto m = std.regex.match(str, _regex);
        string[] result;
        foreach(mat ; m)
            result ~= mat.hit;
        return result;
    }

    /// matchAll - The Script will implement this as an iterator once generators are a thing
    auto matchAll(string str)
    {
        auto m = std.regex.matchAll(str, _regex);
        return m;
    }

    /// replace
    auto replace(string str, string fmt)
    {
        if(global)
            return std.regex.replaceAll(str, _regex, fmt);
        else
            return std.regex.replaceFirst(str, _regex, fmt);
    }

    /// replace only the first occurrence.
    auto replaceFirst(string str, string fmt)
    {
        string r = std.regex.replaceFirst(str, _regex, fmt);
        return r;
    }

    /// search
    auto search(string str)
    {
        auto m = std.regex.match(str, _regex);
        return m.pre.length;
    }

    /// split
    auto split(string str)
    {
        auto result = std.regex.split(str, _regex);
        return result;
    }

    /// exec
    string[] exec(string str)
    {
        string[] result;
        std.regex.Captures!string mat;
        if(str == _currentExec)
        {
            if(_lastIndex >= _currentExec.length)
                return [];
            mat = std.regex.matchFirst(str[_lastIndex..$], _regex);
        }
        else
        {
            if(str.length < 1)
                return [];
            _currentExec = str;
            _lastIndex = 0;
            mat = std.regex.matchFirst(str, _regex);
        }
        if(!mat.empty)
            _lastIndex += mat.hit.length;
        else
            return [];
        // result ~= mat.hit;
        foreach(value ; mat)
        {
            result ~= value;
            _lastIndex += value.length;
        }
        return result;
    }

    /// test
    bool test(string str)
    {
        auto result = exec(str);
        return result != null;
    }

    /// get the string representation
    override string toString() const 
    {
        return "/" ~ _source ~ "/" ~ _flags;
    }

private:
    string _currentExec; // change _matches if this changes
    size_t _lastIndex;

    string _source; // keep track of source
    string _flags; // keep track of flags
    std.regex.Regex!char _regex;
}

void initializeRegExpLibrary(Interpreter interpreter)
{
    ScriptAny ctor = new ScriptFunction("RegExp", &native_RegExp_ctor, true);
    ctor["prototype"] = getRegExpProto();
    ctor["prototype"]["constructor"] = ctor;

    interpreter.forceSetGlobal("RegExp", ctor, false);
}

ScriptObject getRegExpProto()
{
    if(_regExpProto is null)
    {
        _regExpProto = new ScriptObject("RegExp", null);
        
        _regExpProto.addGetterProperty("flags", new ScriptFunction("RegExp.prototype.flags", &native_RegExp_p_flags));
        _regExpProto.addGetterProperty("lastIndex", new ScriptFunction("RegExp.prototype.lastIndex",
                &native_RegExp_p_lastIndex));
        _regExpProto.addSetterProperty("lastIndex", new ScriptFunction("RegExp.prototype.lastIndex",
                &native_RegExp_p_lastIndex));
        _regExpProto.addGetterProperty("source", new ScriptFunction("RegExp.prototype.source", 
                &native_RegExp_p_source));
        
        _regExpProto["dotAll"] = new ScriptFunction("RegExp.prototype.dotAll", &native_RegExp_dotAll);        
        _regExpProto["global"] = new ScriptFunction("RegExp.prototype.global", &native_RegExp_global);
        _regExpProto["ignoreCase"] = new ScriptFunction("RegExp.prototype.ignoreCase", &native_RegExp_ignoreCase);
        _regExpProto["multiline"] = new ScriptFunction("RegExp.prototype.multiline", &native_RegExp_multiline);

        _regExpProto["match"] = new ScriptFunction("RegExp.prototype.match", &native_RegExp_match);
        // TODO matchAll
        _regExpProto["replace"] = new ScriptFunction("RegExp.prototype.replace", &native_RegExp_replace);
        _regExpProto["search"] = new ScriptFunction("RegExp.prototype.search", &native_RegExp_search);
        _regExpProto["split"] = new ScriptFunction("RegExp.prototype.split", &native_RegExp_split);
        _regExpProto["exec"] = new ScriptFunction("RegExp.prototype.exec", &native_RegExp_exec);
        _regExpProto["test"] = new ScriptFunction("RegExp.prototype.test", &native_RegExp_test);
    }
    return _regExpProto;
}

private ScriptObject _regExpProto;

ScriptAny native_RegExp_ctor(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(!thisObj.isObject)
        return ScriptAny.UNDEFINED;
    auto obj = thisObj.toValue!ScriptObject;
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    auto pattern = args[0].toString();
    auto flags = args.length > 1 ? args[1].toString() : "";
    try 
    {
        obj.nativeObject = new ScriptRegExp(pattern, flags);
    }
    catch(std.regex.RegexException rex)
    {
        nfe = NativeFunctionError.RETURN_VALUE_IS_EXCEPTION;
        return ScriptAny(rex.msg);
    }
    return ScriptAny.UNDEFINED;
}

private ScriptAny native_RegExp_p_flags(Environment env, ScriptAny* thisObj,
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto regExp = thisObj.toNativeObject!ScriptRegExp;
    if(regExp is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    return ScriptAny(regExp.flags);
}

private ScriptAny native_RegExp_p_lastIndex(Environment env, ScriptAny* thisObj,
                                            ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto regExp = thisObj.toNativeObject!ScriptRegExp;
    if(regExp is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    if(args.length < 1)
        return ScriptAny(regExp.lastIndex);
    immutable index = args[0].toValue!size_t;
    return ScriptAny(regExp.lastIndex = index);
}

private ScriptAny native_RegExp_p_source(Environment env, ScriptAny* thisObj,
                                         ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto regExp = thisObj.toNativeObject!ScriptRegExp;
    if(regExp is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    return ScriptAny(regExp.source);
}

private ScriptAny native_RegExp_dotAll(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto regExp = thisObj.toNativeObject!ScriptRegExp;
    if(regExp is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    return ScriptAny(regExp.dotAll());
}

private ScriptAny native_RegExp_global(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto regExp = thisObj.toNativeObject!ScriptRegExp;
    if(regExp is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    return ScriptAny(regExp.global());
}

private ScriptAny native_RegExp_ignoreCase(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto regExp = thisObj.toNativeObject!ScriptRegExp;
    if(regExp is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    return ScriptAny(regExp.ignoreCase());
}

private ScriptAny native_RegExp_multiline(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto regExp = thisObj.toNativeObject!ScriptRegExp;
    if(regExp is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    return ScriptAny(regExp.multiline());
}

private ScriptAny native_RegExp_match(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto regExp = thisObj.toNativeObject!ScriptRegExp;
    if(regExp is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    auto str = args[0].toString();
    auto result = regExp.match(str); // @suppress(dscanner.suspicious.unmodified)
    return ScriptAny(result);
}

// TODO matchAll once iterators are implemented

private ScriptAny native_RegExp_replace(Environment env, ScriptAny* thisObj,
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto regExp = thisObj.toNativeObject!ScriptRegExp;
    if(regExp is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    if(args.length < 2)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    auto str = args[0].toString();
    auto fmt = args[1].toString();
    return ScriptAny(regExp.replace(str, fmt));
}

private ScriptAny native_RegExp_search(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto regExp = thisObj.toNativeObject!ScriptRegExp;
    if(regExp is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    auto str = args[0].toString();
    return ScriptAny(regExp.search(str));
}

private ScriptAny native_RegExp_split(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto regExp = thisObj.toNativeObject!ScriptRegExp;
    if(regExp is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    auto str = args[0].toString();
    return ScriptAny(regExp.split(str));
}

private ScriptAny native_RegExp_exec(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto regExp = thisObj.toNativeObject!ScriptRegExp;
    if(regExp is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    auto str = args[0].toString();
    auto result = regExp.exec(str); // @suppress(dscanner.suspicious.unmodified)
    return ScriptAny(regExp.exec(str));
}

private ScriptAny native_RegExp_test(Environment env, ScriptAny* thisObj,
                                       ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto regExp = thisObj.toNativeObject!ScriptRegExp;
    if(regExp is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    auto str = args[0].toString();
    return ScriptAny(regExp.test(str));
}

unittest
{
    import std.stdio: writeln, writefln;
    auto testString = "foo bar foo bar foo";
    auto testRegexp = new ScriptRegExp("foo", "g");
    auto rg2 = new ScriptRegExp("bar");
    auto result = testRegexp.exec(testString);
    assert(result != null);
    while(result)
    {
        writeln(result);
        result = testRegexp.exec(testString);
    }
    writeln(rg2.search(testString));
}