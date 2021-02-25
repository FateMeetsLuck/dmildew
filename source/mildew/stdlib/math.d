/**
This module implements functions for the "Math" namespace in the scripting language.
See https://pillager86.github.io/dmildew/Math.html

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
module mildew.stdlib.math;

import math=std.math;

import mildew.environment;
import mildew.interpreter;
import mildew.types;

/**
 * Initializes the math library. This is called by Interpreter.initializeStdlib. Functions
 * are stored in the global Math object and are accessed such as "Math.acos". Documentation
 * for this library can be found at https://pillager86.github.io/dmildew/Math.html
 * Params:
 *  interpreter = The Interpreter object to load the namespace into.
 */
public void initializeMathLibrary(Interpreter interpreter)
{
    // TODO rewrite this mess with mixins
    ScriptObject mathNamespace = new ScriptObject("Math", null, null);
    // static members
    mathNamespace["E"] = ScriptAny(cast(double)math.E);
    mathNamespace["LN10"] = ScriptAny(cast(double)math.LN10);
    mathNamespace["LN2"] = ScriptAny(cast(double)math.LN2);
    mathNamespace["LOG10E"] = ScriptAny(cast(double)math.LOG10E);
    mathNamespace["LOG2E"] = ScriptAny(cast(double)math.LOG2E);
    mathNamespace["PI"] = ScriptAny(cast(double)math.PI);
    mathNamespace["SQRT1_2"] = ScriptAny(cast(double)math.SQRT1_2);
    mathNamespace["SQRT2"] = ScriptAny(cast(double)math.SQRT2);
    // functions
    mathNamespace["abs"] = ScriptAny(new ScriptFunction("Math.abs", &native_Math_abs));
    mathNamespace["acos"] = ScriptAny(new ScriptFunction("Math.acos", &native_Math_acos));
    mathNamespace["acosh"] = ScriptAny(new ScriptFunction("Math.acosh", &native_Math_acosh));
    mathNamespace["asin"] = ScriptAny(new ScriptFunction("Math.asin", &native_Math_asin));
    mathNamespace["asinh"] = ScriptAny(new ScriptFunction("Math.asinh", &native_Math_asinh));
    mathNamespace["atan"] = ScriptAny(new ScriptFunction("Math.atan", &native_Math_atan));
    mathNamespace["atan2"] = ScriptAny(new ScriptFunction("Math.atan2", &native_Math_atan2));
    mathNamespace["cbrt"] = ScriptAny(new ScriptFunction("Math.cbrt", &native_Math_cbrt));
    mathNamespace["ceil"] = ScriptAny(new ScriptFunction("Math.ceil", &native_Math_ceil));
    mathNamespace["clz32"] = ScriptAny(new ScriptFunction("Math.clz32", &native_Math_clz32));
    mathNamespace["cos"] = ScriptAny(new ScriptFunction("Math.cos", &native_Math_cos));
    mathNamespace["cosh"] = ScriptAny(new ScriptFunction("Math.cosh", &native_Math_cosh));
    mathNamespace["exp"] = ScriptAny(new ScriptFunction("Math.exp", &native_Math_exp));
    mathNamespace["expm1"] = ScriptAny(new ScriptFunction("Math.expm1", &native_Math_expm1));
    mathNamespace["floor"] = ScriptAny(new ScriptFunction("Math.floor", &native_Math_floor));
    mathNamespace["fround"] = ScriptAny(new ScriptFunction("Math.fround", &native_Math_fround));
    mathNamespace["hypot"] = ScriptAny(new ScriptFunction("Math.hypot", &native_Math_hypot));
    mathNamespace["imul"] = ScriptAny(new ScriptFunction("Math.imul", &native_Math_imul));
    mathNamespace["log"] = ScriptAny(new ScriptFunction("Math.log", &native_Math_log));
    mathNamespace["log10"] = ScriptAny(new ScriptFunction("Math.log10", &native_Math_log10));
    mathNamespace["log1p"] = ScriptAny(new ScriptFunction("Math.log1p", &native_Math_log1p));
    mathNamespace["log2"] = ScriptAny(new ScriptFunction("Math.log2", &native_Math_log2));
    mathNamespace["max"] = ScriptAny(new ScriptFunction("Math.max", &native_Math_max));
    mathNamespace["min"] = ScriptAny(new ScriptFunction("Math.min", &native_Math_min));
    mathNamespace["pow"] = ScriptAny(new ScriptFunction("Math.pow", &native_Math_pow));
    mathNamespace["random"] = ScriptAny(new ScriptFunction("Math.random", &native_Math_random));
    mathNamespace["round"] = ScriptAny(new ScriptFunction("Math.round", &native_Math_round));
    mathNamespace["sign"] = ScriptAny(new ScriptFunction("Math.sign", &native_Math_sign));
    mathNamespace["sin"] = ScriptAny(new ScriptFunction("Math.sin", &native_Math_sin));
    mathNamespace["sinh"] = ScriptAny(new ScriptFunction("Math.sinh", &native_Math_sinh));
    mathNamespace["sqrt"] = ScriptAny(new ScriptFunction("Math.sqrt", &native_Math_sqrt));
    mathNamespace["tan"] = ScriptAny(new ScriptFunction("Math.tan", &native_Math_tan));
    mathNamespace["tanh"] = ScriptAny(new ScriptFunction("Math.tanh", &native_Math_tanh));
    mathNamespace["trunc"] = ScriptAny(new ScriptFunction("Math.trunc", &native_Math_trunc));
    interpreter.forceSetGlobal("Math", mathNamespace, true);
}

// TODO rewrite half of this mess with mixins

private ScriptAny native_Math_abs(Environment env,
                                  ScriptAny* thisObj,
                                  ScriptAny[] args,
                                  ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    if(args[0].type == ScriptAny.Type.INTEGER)
        return ScriptAny(math.abs(args[0].toValue!long));
    return ScriptAny(math.abs(args[0].toValue!double));            
}

private ScriptAny native_Math_acos(Environment env,
                                   ScriptAny* thisObj,
                                   ScriptAny[] args,
                                   ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.acos(args[0].toValue!double));
}

private ScriptAny native_Math_acosh(Environment env,
                                    ScriptAny* thisObj,
                                    ScriptAny[] args,
                                    ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.acosh(args[0].toValue!double));
}

private ScriptAny native_Math_asin(Environment env,
                                   ScriptAny* thisObj,
                                   ScriptAny[] args,
                                   ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.asin(args[0].toValue!double));
}

private ScriptAny native_Math_asinh(Environment env,
                                    ScriptAny* thisObj,
                                    ScriptAny[] args,
                                    ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.asinh(args[0].toValue!double));
}

private ScriptAny native_Math_atan(Environment env,
                                   ScriptAny* thisObj,
                                   ScriptAny[] args,
                                   ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.atan(args[0].toValue!double));
}

private ScriptAny native_Math_atan2(Environment env,
                                    ScriptAny* thisObj,
                                    ScriptAny[] args,
                                    ref NativeFunctionError nfe)
{
    if(args.length < 2)
        return ScriptAny(double.nan);
    if(!args[0].isNumber || !args[1].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.atan2(args[0].toValue!double, args[1].toValue!double));
}

private ScriptAny native_Math_cbrt(Environment env,
                                   ScriptAny* thisObj,
                                   ScriptAny[] args,
                                   ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.cbrt(args[0].toValue!double));
}

private ScriptAny native_Math_ceil(Environment env,
                                   ScriptAny* thisObj,
                                   ScriptAny[] args,
                                   ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    if(args[0].isInteger)
        return ScriptAny(args[0].toValue!long);
    return ScriptAny(cast(long)math.ceil(args[0].toValue!double));
}

private ScriptAny native_Math_clz32(Environment env,
                                    ScriptAny* thisObj,
                                    ScriptAny[] args,
                                    ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(0);
    if(!args[0].isNumber)
        return ScriptAny(0);
    immutable uint num = args[0].toValue!uint;
    return ScriptAny(CLZ1(num));
}

private ScriptAny native_Math_cos(Environment env,
                                  ScriptAny* thisObj,
                                  ScriptAny[] args,
                                  ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.cos(args[0].toValue!double));
}

private ScriptAny native_Math_cosh(Environment env,
                                   ScriptAny* thisObj,
                                   ScriptAny[] args,
                                   ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.cosh(args[0].toValue!double));
}

private ScriptAny native_Math_exp(Environment env,
                                  ScriptAny* thisObj,
                                  ScriptAny[] args,
                                  ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.exp(args[0].toValue!double));
}

private ScriptAny native_Math_expm1(Environment env,
                                    ScriptAny* thisObj,
                                    ScriptAny[] args,
                                    ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.expm1(args[0].toValue!double));
}

private ScriptAny native_Math_floor(Environment env,
                                    ScriptAny* thisObj,
                                    ScriptAny[] args,
                                    ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    if(args[0].isInteger)
        return ScriptAny(args[0].toValue!long);
    return ScriptAny(cast(long)math.floor(args[0].toValue!double));
}

private ScriptAny native_Math_fround(Environment env,
                                     ScriptAny* thisObj,
                                     ScriptAny[] args,
                                     ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    immutable float f = args[0].toValue!float;
    return ScriptAny(f);
}

private ScriptAny native_Math_hypot(Environment env,
                                    ScriptAny* thisObj,
                                    ScriptAny[] args,
                                    ref NativeFunctionError nfe)
{
    double sum = 0;
    foreach(arg ; args)
    {
        if(!arg.isNumber)
            return ScriptAny(double.nan);
        sum += arg.toValue!double * arg.toValue!double;
    }
    return ScriptAny(math.sqrt(sum));
}

private ScriptAny native_Math_imul(Environment env,
                                   ScriptAny* thisObj,
                                   ScriptAny[] args,
                                   ref NativeFunctionError nfe)
{
    if(args.length < 2)
        return ScriptAny(double.nan);
    if(!args[0].isNumber || !args[1].isNumber)
        return ScriptAny(double.nan);
    immutable a = args[0].toValue!int;
    immutable b = args[1].toValue!int;
    return ScriptAny(a * b);
}

private ScriptAny native_Math_log(Environment env,
                                  ScriptAny* thisObj,
                                  ScriptAny[] args,
                                  ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.log(args[0].toValue!double));
}

private ScriptAny native_Math_log10(Environment env,
                                    ScriptAny* thisObj,
                                    ScriptAny[] args,
                                    ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.log10(args[0].toValue!double));
}

private ScriptAny native_Math_log1p(Environment env,
                                    ScriptAny* thisObj,
                                    ScriptAny[] args,
                                    ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.log1p(args[0].toValue!double));
}

private ScriptAny native_Math_log2(Environment env,
                                   ScriptAny* thisObj,
                                   ScriptAny[] args,
                                   ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.log2(args[0].toValue!double));
}

private ScriptAny native_Math_max(Environment env,
                                  ScriptAny* thisObj,
                                  ScriptAny[] args,
                                  ref NativeFunctionError nfe)
{
    import std.algorithm: max;
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    double maxNumber = args[0].toValue!double;
    for(size_t i = 1; i < args.length; ++i)
    {
        if(!args[i].isNumber)
            return ScriptAny.UNDEFINED;
        immutable temp = args[i].toValue!double;
        if(temp > maxNumber)
            maxNumber = temp;
    }
    return ScriptAny(maxNumber);
}

private ScriptAny native_Math_min(Environment env,
                                  ScriptAny* thisObj,
                                  ScriptAny[] args,
                                  ref NativeFunctionError nfe)
{
    import std.algorithm: max;
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    double minNumber = args[0].toValue!double;
    for(size_t i = 1; i < args.length; ++i)
    {
        if(!args[i].isNumber)
            return ScriptAny.UNDEFINED;
        immutable temp = args[i].toValue!double;
        if(temp < minNumber)
            minNumber = temp;
    }
    return ScriptAny(minNumber);
}

private ScriptAny native_Math_pow(Environment env,
                                  ScriptAny* thisObj,
                                  ScriptAny[] args,
                                  ref NativeFunctionError nfe)
{
    if(args.length < 2)
        return ScriptAny(double.nan);
    if(!args[0].isNumber || !args[1].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.pow(args[0].toValue!double, args[1].toValue!double));
}

private ScriptAny native_Math_random(Environment env,
                                     ScriptAny* thisObj,
                                     ScriptAny[] args,
                                     ref NativeFunctionError nfe)
{
    import std.random : uniform;
    return ScriptAny(uniform(0.0, 1.0));
}

private ScriptAny native_Math_round(Environment env,
                                    ScriptAny* thisObj,
                                    ScriptAny[] args,
                                    ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    if(args[0].isInteger)
        return ScriptAny(args[0].toValue!long);
    return ScriptAny(cast(long)math.round(args[0].toValue!double));
}

private ScriptAny native_Math_sign(Environment env,
                                   ScriptAny* thisObj,
                                   ScriptAny[] args,
                                   ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    immutable num = args[0].toValue!double;
    if(num < 0)
        return ScriptAny(-1);
    else if(num > 0)
        return ScriptAny(1);
    else
        return ScriptAny(0);
}

private ScriptAny native_Math_sin(Environment env,
                                  ScriptAny* thisObj,
                                  ScriptAny[] args,
                                  ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.sin(args[0].toValue!double));
}

private ScriptAny native_Math_sinh(Environment env,
        ScriptAny* thisObj,
        ScriptAny[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.sinh(args[0].toValue!double));
}

private ScriptAny native_Math_sqrt(Environment env,
                                   ScriptAny* thisObj,
                                   ScriptAny[] args,
                                   ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny.UNDEFINED;
    if(!args[0].isNumber)
        return ScriptAny.UNDEFINED;
    return ScriptAny(math.sqrt(args[0].toValue!double));
}

private ScriptAny native_Math_tan(Environment env,
                                  ScriptAny* thisObj,
                                  ScriptAny[] args,
                                  ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.tan(args[0].toValue!double));
}

private ScriptAny native_Math_tanh(Environment env,
                                   ScriptAny* thisObj,
                                   ScriptAny[] args,
                                   ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.tanh(args[0].toValue!double));
}

private ScriptAny native_Math_trunc(Environment env,
                                    ScriptAny* thisObj,
                                    ScriptAny[] args,
                                    ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptAny(double.nan);
    if(!args[0].isNumber)
        return ScriptAny(double.nan);
    return ScriptAny(math.trunc(args[0].toValue!double));
}


/// software implementation of CLZ32 because I don't know assembly nor care to lock DMildew to a specific CPU
/// courtesy of https://embeddedgurus.com/state-space/2014/09/fast-deterministic-and-portable-counting-leading-zeros/
pragma(inline, true) 
uint CLZ1(uint x) 
{
    static immutable ubyte[] clz_lkup = [
        32U, 31U, 30U, 30U, 29U, 29U, 29U, 29U,
        28U, 28U, 28U, 28U, 28U, 28U, 28U, 28U,
        27U, 27U, 27U, 27U, 27U, 27U, 27U, 27U,
        27U, 27U, 27U, 27U, 27U, 27U, 27U, 27U,
        26U, 26U, 26U, 26U, 26U, 26U, 26U, 26U,
        26U, 26U, 26U, 26U, 26U, 26U, 26U, 26U,
        26U, 26U, 26U, 26U, 26U, 26U, 26U, 26U,
        26U, 26U, 26U, 26U, 26U, 26U, 26U, 26U,
        25U, 25U, 25U, 25U, 25U, 25U, 25U, 25U,
        25U, 25U, 25U, 25U, 25U, 25U, 25U, 25U,
        25U, 25U, 25U, 25U, 25U, 25U, 25U, 25U,
        25U, 25U, 25U, 25U, 25U, 25U, 25U, 25U,
        25U, 25U, 25U, 25U, 25U, 25U, 25U, 25U,
        25U, 25U, 25U, 25U, 25U, 25U, 25U, 25U,
        25U, 25U, 25U, 25U, 25U, 25U, 25U, 25U,
        25U, 25U, 25U, 25U, 25U, 25U, 25U, 25U,
        24U, 24U, 24U, 24U, 24U, 24U, 24U, 24U,
        24U, 24U, 24U, 24U, 24U, 24U, 24U, 24U,
        24U, 24U, 24U, 24U, 24U, 24U, 24U, 24U,
        24U, 24U, 24U, 24U, 24U, 24U, 24U, 24U,
        24U, 24U, 24U, 24U, 24U, 24U, 24U, 24U,
        24U, 24U, 24U, 24U, 24U, 24U, 24U, 24U,
        24U, 24U, 24U, 24U, 24U, 24U, 24U, 24U,
        24U, 24U, 24U, 24U, 24U, 24U, 24U, 24U,
        24U, 24U, 24U, 24U, 24U, 24U, 24U, 24U,
        24U, 24U, 24U, 24U, 24U, 24U, 24U, 24U,
        24U, 24U, 24U, 24U, 24U, 24U, 24U, 24U,
        24U, 24U, 24U, 24U, 24U, 24U, 24U, 24U,
        24U, 24U, 24U, 24U, 24U, 24U, 24U, 24U,
        24U, 24U, 24U, 24U, 24U, 24U, 24U, 24U,
        24U, 24U, 24U, 24U, 24U, 24U, 24U, 24U,
        24U, 24U, 24U, 24U, 24U, 24U, 24U, 24U
    ];
    uint n;
    if (x >= (1U << 16)) 
    {
        if (x >= (1U << 24)) 
        {
            n = 24U;
        }
        else 
        {
            n = 16U;
        }
    }
    else 
    {
        if (x >= (1U << 8)) 
        {
            n = 8U;
        }
        else 
        {
            n = 0U;
        }
    }
    return cast(uint)clz_lkup[x >> n] - n;
}
