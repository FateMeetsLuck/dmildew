/**
This module implements the JSON namespace.

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
module mildew.stdlib.json;

import std.conv: to, ConvException;
debug import std.stdio;
import std.uni: isNumber;
import std.utf: encode;

import mildew.environment;
import mildew.exceptions;
import mildew.interpreter;
import mildew.types;

/**
 * Initializes the JSON namespace
 * Params:
 *  interpreter = The Interpreter instance to load the namespace into
 */
void initializeJSONLibrary(Interpreter interpreter)
{
    auto JSONnamespace = new ScriptObject("namespace", null);
    JSONnamespace["parse"] = new ScriptFunction("JSON.parse", &native_JSON_parse);
    JSONnamespace["stringify"] = new ScriptFunction("JSON.stringify", &native_JSON_stringify);
    interpreter.forceSetGlobal("JSON", JSONnamespace, false);
}

/**
 * Parses text and returns a ScriptObject. Throws ScriptRuntimeException if invalid.
 */
ScriptAny native_JSON_parse(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    auto str = args[0].toString();
    try 
    {
        JSONReader.ignoreWhitespace(str);
        if(str.length == 0)
            return ScriptAny.UNDEFINED;
        else if(str[0] == '{')
            return ScriptAny(JSONReader.consumeObject(str));
        else if(str[0] == '[')
            return ScriptAny(JSONReader.consumeArray(str));
        else
            throw new ScriptRuntimeException("Unknown JSON value at top level");
    }
    catch(Exception ex)
    {
        throw new ScriptRuntimeException("JSON.parse: " ~ ex.msg);
    }
}

/**
 * Reads JSON strings as Mildew objects.
 */
class JSONReader 
{

    private static void consume(ref string str, char c)
    {
        if(str.length < 1)
            throw new ScriptRuntimeException("Expected " ~ c ~ " in non-empty string");
        if(str[0] != c)
            throw new ScriptRuntimeException("Expected '" ~ c ~ "' not '" ~ str[0] ~ "'");
        str = str[1..$];
    }

    /**
     * Reads an array from a string
     */
    static ScriptAny[] consumeArray(ref string str)
    {
        ScriptAny[] result;
        consume(str, '[');
        while(peek(str) != ']')
        {
            ignoreWhitespace(str);
            if(isStringDelimiter(peek(str)))
                result ~= ScriptAny(consumeString(str));
            else if(isNumber(peek(str)) || peek(str) == '-')
                result ~= consumeNumber(str);
            else if(peek(str) == '{')
                result ~= ScriptAny(consumeObject(str));
            else if(peek(str) == '[')
                result ~= ScriptAny(consumeArray(str));
            else if(peek(str) == 't' || peek(str) == 'f')
                result ~= ScriptAny(consumeBoolean(str));
            else if(peek(str) == 'n')
                result ~= consumeNull(str);
            else
                throw new ScriptRuntimeException("Not a valid JSON value in array");
            ignoreWhitespace(str);
            if(peek(str) == ',')
                next(str);
            else if(peek(str) != ']')
                throw new ScriptRuntimeException("Arrays must end with ']'");
        }
        consume(str, ']');
        return result;
    }

    private static bool consumeBoolean(ref string str)
    {
        if(str[0] == 't' && str.length >= 4 && str[0..4] == "true")
        {
            str = str[4..$];
            return true;
        }
        else if(str[0] == 'f' && str.length >= 5 && str[0..5] == "false")
        {
            str = str[5..$];
            return false;
        }
        else
        {
            throw new ScriptRuntimeException("Expected boolean");
        }
    }

    private static ScriptAny consumeNull(ref string str)
    {
        if(str[0] == 'n' && str.length >= 4 && str[0..4] == "null")
        {
            str = str[4..$];
            return ScriptAny(null);
        }
        throw new ScriptRuntimeException("Expected null");
    }

    private static ScriptAny consumeNumber(ref string str)
    {
        auto numberString = "";
        auto eCounter = 0;
        auto dotCounter = 0;
        auto dashCounter = 0;
        while(isNumber(peek(str)) || peek(str) == '.' || peek(str) == 'e' || peek(str) == '-')
        {
            immutable ch = next(str);
            if(ch == 'e')
                ++eCounter;
            else if(ch == '.')
                ++dotCounter;
            else if(ch == '-')
                ++dashCounter;
            if(eCounter > 1 || dotCounter > 1 || dashCounter > 2)
                throw new ScriptRuntimeException("Too many 'e' or '.' or '-' in number literal");
            numberString ~= ch;
        }
        if(dotCounter == 0 && eCounter == 0)
            return ScriptAny(to!long(numberString));
        
        return ScriptAny(to!double(numberString));
    }

    /**
     * Reads a Mildew object from a JSON string
     */
    static ScriptObject consumeObject(ref string str)
    {
        auto object = new ScriptObject("Object", null);

        consume(str, '{');
        ignoreWhitespace(str);
        while(peek(str) != '}' && str.length > 0)
        {
            ignoreWhitespace(str);
            // then key value pairs
            auto key = JSONReader.consumeString(str);
            ignoreWhitespace(str);
            consume(str, ':');
            ignoreWhitespace(str);
            ScriptAny value;
            if(isStringDelimiter(peek(str)))
                value = consumeString(str);
            else if(isNumber(peek(str)) || peek(str) == '-')
                value = consumeNumber(str);
            else if(peek(str) == '{')
                value = ScriptAny(consumeObject(str));
            else if(peek(str) == '[')
                value = ScriptAny(consumeArray(str));
            else if(peek(str) == 't' || peek(str) == 'f')
                value = ScriptAny(consumeBoolean(str));
            else if(peek(str) == 'n')
                value = consumeNull(str);
            else
                throw new ScriptRuntimeException("Not a valid JSON value in object");
            ignoreWhitespace(str);
            if(peek(str) == ',')
                next(str);
            else if(peek(str) != '}')
                throw new ScriptRuntimeException("Expected comma between key-value pairs");
            object[key] = value;
        }
        consume(str, '}');

        return object;
    }

    private static string consumeString(ref string str)
    {
        if(str.length == 0)
            throw new ScriptRuntimeException("Expected string value in non-empty string");
        if(!isStringDelimiter(str[0]))
            throw new ScriptRuntimeException("Expected string delimiter not " ~ str[0]);
        immutable delim = next(str);
        auto value = "";
        auto ch = next(str);
        while(ch != delim)
        {
            if(ch == '\\')
            {
                ch = next(str);
                switch(ch)
                {
                case 'b':
                    value ~= '\b';
                    break;
                case 'f':
                    value ~= '\f';
                    break;
                case 'n':
                    value ~= '\n';
                    break;
                case 'r':
                    value ~= '\r';
                    break;
                case 't':
                    value ~= '\t';
                    break;
                case 'u': {
                    ch = next(str);
                    auto hexNumber = "";
                    for(auto counter = 0; counter < 4; ++counter)
                    {
                        if(!isHexDigit(peek(str)))
                            break;
                        hexNumber ~= ch;
                        ch = next(str);
                    }
                    immutable hexValue = to!ushort(hexNumber);
                    char[] buf;
                    encode(buf, cast(dchar)hexValue);
                    value ~= buf;
                    
                    break;
                }
                default:
                    value ~= ch;
                }
            }
            else
            {
                value ~= ch;
            }
            ch = next(str);
        }
        // consume(str, delim);

        return value;
    }

    private static void ignoreWhitespace(ref string str)
    {
        while ( 
            str.length > 0 
            && ( str[0] == ' ' 
                || str[0] == '\t' 
                || str[0] == '\n'
                || str[0] == '\r'
            )
            ) 
        {
            str = str[1..$];
        }
    }

    private static bool isHexDigit(in char c)
    {
        import std.ascii: toLower;
        return (c >= '0' && c <= '9') || (c.toLower >= 'a' || c.toLower <= 'f');
    }

    private static bool isStringDelimiter(in char c)
    {
        return (c == '"' || c == '\'' || c == '`');
    }

    private static char next(ref string str)
    {
        if(str.length == 0)
            return '\0';
        immutable c = str[0];
        str = str[1..$];
        return c;
    }

    private static char peek(in string str)
    {
        if(str.length == 0)
            return '\0';
        return str[0];
    }
}

/**
 * Converts a Mildew Object into a JSON string.
 */
ScriptAny native_JSON_stringify(Environment env, ScriptAny* thisObj, 
                                        ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(args.length < 1)
    {
        nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
        return ScriptAny.UNDEFINED;
    }
    ScriptAny replacer = args.length > 1 ? args[1] : ScriptAny.UNDEFINED;
    auto writer = new JSONWriter(env, ScriptAny.UNDEFINED, replacer);
    return ScriptAny(writer.produceValue(args[0]));
}

private class JSONWriter
{
    import mildew.types.bindings: native_Function_call;

    this(Environment e, ScriptAny t, ScriptAny r)
    {
        environment = e;
        thisToUse = t;
        replacer = r;
    }

    string produceArray(ScriptAny[] array)
    {
        string result = "[";
        if(array in arrayLimiter)
            ++arrayLimiter[cast(immutable)array];
        else
            arrayLimiter[cast(immutable)array] = 1;
        
        if(arrayLimiter[cast(immutable)array] > 256)
            throw new Exception("Array recursion error");

        for(size_t i = 0; i < array.length; ++i)
        {
            auto strValue = produceValue(array[i]);
            if(strValue != "")
                result ~= strValue;
            else
                result ~= produceNull();
            if(i < array.length - 1)
                result ~= ",";
        }
        result ~= "]";

        --arrayLimiter[cast(immutable)array];

        return result;
    }

    string produceBoolean(bool b)
    {
        return b ? "true" : "false";
    }

    string produceNull()
    {
        return "null";
    }

    string produceNumber(ScriptAny number)
    {
        return number.toString();
    }

    string produceObject(ScriptObject object)
    {
        if(object in recursion)
            ++recursion[object];
        else
            recursion[object] = 1;
        
        if(recursion[object] > 256)
            throw new Exception("Object recursion error");
        
        string result = "{";
        size_t counter = 0;
        foreach(key, value ; object.dictionary)
        {
            auto strKey = produceString(key);
            auto strValue = "";
            if(replacer.type == ScriptAny.Type.FUNCTION)
            {
                NativeFunctionError nfe;
                strValue = native_Function_call(environment, &replacer, 
                        [thisToUse, ScriptAny(key), value], nfe).toString();
            }
            else 
            {
                strValue = produceValue(value);
            }
            if(strValue != "")
            {
                result ~= strKey ~ ":" ~ strValue;
            }
            if(counter < object.dictionary.keys.length - 1)
                result ~= ",";
            ++counter;
        }
        result ~= "}";
        --recursion[object];
        return result;
    }

    string produceString(in string key)
    {
        string result = "\"";
        foreach(ch ; key)
        {
            switch(ch)
            {
            case '"':
                result ~= "\\\"";
                break;
            case '\\':
                result ~= "\\\\";
                break;
            case '\b':
                result ~= "\\b";
                break;
            case '\f':
                result ~= "\\f";
                break;
            case '\n':
                result ~= "\\n";
                break;
            case '\r':
                result ~= "\\r";
                break;
            case '\t':
                result ~= "\\t";
                break;
            default:
                result ~= ch;
            }
        }
        result ~= "\"";
        return result;
    }


    string produceValue(ScriptAny value)
    {
        switch(value.type)
        {
        case ScriptAny.Type.NULL:
            return produceNull();
        case ScriptAny.Type.BOOLEAN:
            return produceBoolean(cast(bool)value);
        case ScriptAny.Type.INTEGER:
        case ScriptAny.Type.DOUBLE:
            return produceNumber(value);
        case ScriptAny.Type.ARRAY:
            return produceArray(value.toValue!(ScriptAny[]));
        case ScriptAny.Type.STRING:
            return produceString(value.toString());
        case ScriptAny.Type.OBJECT:
            return produceObject(value.toValue!ScriptObject);
        default:
            return "";
        }
    }

    Environment environment;
    ScriptAny thisToUse;
    ScriptAny replacer;

    int[ScriptAny[]] arrayLimiter;
    int[ScriptObject] recursion;
}

unittest 
{
    string str1 = ""; // @suppress(dscanner.suspicious.unmodified)
    string str2 = null; // @suppress(dscanner.suspicious.unmodified)
    assert(str1 == str2); // weird that is passes when the produceObject didn't work the same
}