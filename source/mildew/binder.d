/**
Contains functions to mixin to simplify code reuse. For these to work, the parameters of a native function
must be called context, thisObj, args, and nfe. They should not be placed in inner scopes or under if statements.

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
module mildew.binder;

import std.format: format;
import std.conv: to;

/**
 * Check for a minimum number of arguments. This must be used if using TO_ARG
 */
string CHECK_MINIMUM_ARGS(int num)()
{
    return format(q{
        if(args.length < %1$s)
        {
            nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
            return ScriptAny.UNDEFINED;
        }
    }, num.to!string);
}

/**
 * Shorthand for validating a this object as a native type
 */
string CHECK_THIS_NATIVE_OBJECT(string varName, alias dclass)()
{
    return format(q{
        auto %1$s = thisObj.toNativeObject!%2$s;
        if(%1$s is null)
        {
            nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
            return ScriptAny.UNDEFINED;
        }
    }, varName, dclass.stringof);
}

/**
 * Uses .init value of a variable if argument doesn't exist. Arguments length MUST be checked first
 */
string TO_ARG(string varName, int index, alias type)()
{
    return format(q{
        auto %1$s = args[%2$s].toValue!%3$s;
    }, varName, index.to!string, type.stringof);
}

/**
 * Get an optional argument and default value
 */
string TO_ARG_OPT(string varName, int index, alias defaultValue, alias type)()
{
    return format(q{
        auto %1$s = %3$s;
        if(%2$s < args.length)
        {
            %1$s = args[%2$s].toValue!%4$s;
        }
    }, varName, index.to!string, defaultValue.stringof, type.stringof);
}

/**
 * Shorthand for extracting an argument without validating its type
 */
string TO_ARG_CHECK_INDEX(string varName, int index, alias type)()
{   
    return format(q{
        if(args.length < %2$s + 1)
        {
            nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
            return ScriptAny.UNDEFINED;
        }
        auto %1$s = args[%2$s].toValue!%3$s;
    }, varName, index.to!string, type.stringof);
}

