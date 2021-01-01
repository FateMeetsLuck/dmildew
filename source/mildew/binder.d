/**
 * Contains functions to mixin to simplify code reuse. For these to work, the parameters of a native function
 * must be called context, thisObj, args, and nfe.
 */
module mildew.binder;

import std.format: format;
import std.conv: to;

/**
 * Uses .init value of a variable if argument doesn't exist.
 */
string TO_ARG(string varName, int index, alias type)()
{
    return format(q{
        %3$s %1$s;
        if(args.length >= %2$s + 1)
        {
            %1$s = args[%2$s].toValue!%3$s;
        }
    }, varName, index.to!string, type.stringof);
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
 * Check for a minimum number of arguments
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