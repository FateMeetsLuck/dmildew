module mildew.stdlib.math;

import math=std.math;

import mildew.context;
import mildew.interpreter;
import mildew.types;

/**
 * Initializes the math library. This is called by Interpreter.initializeStdlib. Functions
 * are stored in the global Math object and are accessed such as "Math.acos"
 */
public void initializeMathLibrary(Interpreter interpreter)
{
    // TODO rewrite this mess with mixins
    ScriptObject mathNamespace = new ScriptObject("Math", null, null);
    // static members
    mathNamespace["E"] = ScriptValue(cast(double)math.E);
    mathNamespace["LN10"] = ScriptValue(cast(double)math.LN10);
    mathNamespace["LN2"] = ScriptValue(cast(double)math.LN2);
    mathNamespace["LOG10E"] = ScriptValue(cast(double)math.LOG10E);
    mathNamespace["LOG2E"] = ScriptValue(cast(double)math.LOG2E);
    mathNamespace["PI"] = ScriptValue(cast(double)math.PI);
    mathNamespace["SQRT1_2"] = ScriptValue(cast(double)math.SQRT1_2);
    mathNamespace["SQRT2"] = ScriptValue(cast(double)math.SQRT2);
    // functions
    mathNamespace["abs"] = ScriptValue(new ScriptFunction("Math.abs", &native_Math_abs));
    mathNamespace["acos"] = ScriptValue(new ScriptFunction("Math.acos", &native_Math_acos));
    mathNamespace["acosh"] = ScriptValue(new ScriptFunction("Math.acosh", &native_Math_acosh));
    mathNamespace["asin"] = ScriptValue(new ScriptFunction("Math.asin", &native_Math_asin));
    mathNamespace["asinh"] = ScriptValue(new ScriptFunction("Math.asinh", &native_Math_asinh));
    mathNamespace["atan"] = ScriptValue(new ScriptFunction("Math.atan", &native_Math_atan));
    mathNamespace["atan2"] = ScriptValue(new ScriptFunction("Math.atan2", &native_Math_atan2));
    mathNamespace["cbrt"] = ScriptValue(new ScriptFunction("Math.cbrt", &native_Math_cbrt));
    mathNamespace["ceil"] = ScriptValue(new ScriptFunction("Math.ceil", &native_Math_ceil));
    mathNamespace["clz32"] = ScriptValue(new ScriptFunction("Math.clz32", &native_Math_clz32));
    mathNamespace["cos"] = ScriptValue(new ScriptFunction("Math.cos", &native_Math_cos));
    mathNamespace["cosh"] = ScriptValue(new ScriptFunction("Math.cosh", &native_Math_cosh));
    mathNamespace["exp"] = ScriptValue(new ScriptFunction("Math.exp", &native_Math_exp));
    mathNamespace["expm1"] = ScriptValue(new ScriptFunction("Math.expm1", &native_Math_expm1));
    mathNamespace["floor"] = ScriptValue(new ScriptFunction("Math.floor", &native_Math_floor));
    mathNamespace["fround"] = ScriptValue(new ScriptFunction("Math.fround", &native_Math_fround));
    mathNamespace["hypot"] = ScriptValue(new ScriptFunction("Math.hypot", &native_Math_hypot));
    mathNamespace["imul"] = ScriptValue(new ScriptFunction("Math.imul", &native_Math_imul));
    mathNamespace["log"] = ScriptValue(new ScriptFunction("Math.log", &native_Math_log));
    mathNamespace["log10"] = ScriptValue(new ScriptFunction("Math.log10", &native_Math_log10));
    mathNamespace["log1p"] = ScriptValue(new ScriptFunction("Math.log1p", &native_Math_log1p));
    mathNamespace["log2"] = ScriptValue(new ScriptFunction("Math.log2", &native_Math_log2));
    mathNamespace["max"] = ScriptValue(new ScriptFunction("Math.max", &native_Math_max));
    mathNamespace["min"] = ScriptValue(new ScriptFunction("Math.min", &native_Math_min));
    mathNamespace["pow"] = ScriptValue(new ScriptFunction("Math.pow", &native_Math_pow));
    mathNamespace["random"] = ScriptValue(new ScriptFunction("Math.random", &native_Math_random));
    mathNamespace["round"] = ScriptValue(new ScriptFunction("Math.round", &native_Math_round));
    mathNamespace["sign"] = ScriptValue(new ScriptFunction("Math.sign", &native_Math_sign));
    mathNamespace["sin"] = ScriptValue(new ScriptFunction("Math.sin", &native_Math_sin));
    mathNamespace["sinh"] = ScriptValue(new ScriptFunction("Math.sinh", &native_Math_sinh));
    mathNamespace["sqrt"] = ScriptValue(new ScriptFunction("Math.sqrt", &native_Math_sqrt));
    mathNamespace["tan"] = ScriptValue(new ScriptFunction("Math.tan", &native_Math_tan));
    mathNamespace["tanh"] = ScriptValue(new ScriptFunction("Math.tanh", &native_Math_tanh));
    mathNamespace["trunc"] = ScriptValue(new ScriptFunction("Math.trunc", &native_Math_trunc));
    interpreter.forceSetGlobal("Math", mathNamespace, true);
}

// TODO rewrite half of this mess with mixins

private ScriptValue native_Math_abs(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    if(args[0].type == ScriptValue.Type.INTEGER)
        return ScriptValue(math.abs(args[0].toValue!long));
    return ScriptValue(math.abs(args[0].toValue!double));            
}

private ScriptValue native_Math_acos(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.acos(args[0].toValue!double));
}

private ScriptValue native_Math_acosh(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.acosh(args[0].toValue!double));
}

private ScriptValue native_Math_asin(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.asin(args[0].toValue!double));
}

private ScriptValue native_Math_asinh(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.asinh(args[0].toValue!double));
}

private ScriptValue native_Math_atan(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.atan(args[0].toValue!double));
}

private ScriptValue native_Math_atan2(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 2)
        return ScriptValue(double.nan);
    if(!args[0].isNumber || !args[1].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.atan2(args[0].toValue!double, args[1].toValue!double));
}

private ScriptValue native_Math_cbrt(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.cbrt(args[0].toValue!double));
}

private ScriptValue native_Math_ceil(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.ceil(args[0].toValue!double));
}

private ScriptValue native_Math_clz32(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(0);
    if(!args[0].isNumber)
        return ScriptValue(0);
    immutable uint num = args[0].toValue!uint;
    return ScriptValue(CLZ1(num));
}

private ScriptValue native_Math_cos(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.cos(args[0].toValue!double));
}

private ScriptValue native_Math_cosh(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.cosh(args[0].toValue!double));
}

private ScriptValue native_Math_exp(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.exp(args[0].toValue!double));
}

private ScriptValue native_Math_expm1(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.expm1(args[0].toValue!double));
}

private ScriptValue native_Math_floor(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.floor(args[0].toValue!double));
}

private ScriptValue native_Math_fround(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    immutable float f = args[0].toValue!float;
    return ScriptValue(f);
}

private ScriptValue native_Math_hypot(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    double sum = 0;
    foreach(arg ; args)
    {
        if(!arg.isNumber)
            return ScriptValue(double.nan);
        sum += arg.toValue!double;
    }
    return ScriptValue(math.sqrt(sum));
}

private ScriptValue native_Math_imul(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 2)
        return ScriptValue(double.nan);
    if(!args[0].isNumber || !args[1].isNumber)
        return ScriptValue(double.nan);
    immutable a = args[0].toValue!int;
    immutable b = args[1].toValue!int;
    return ScriptValue(a * b);
}

private ScriptValue native_Math_log(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.log(args[0].toValue!double));
}

private ScriptValue native_Math_log10(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.log10(args[0].toValue!double));
}

private ScriptValue native_Math_log1p(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.log1p(args[0].toValue!double));
}

private ScriptValue native_Math_log2(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.log2(args[0].toValue!double));
}

private ScriptValue native_Math_max(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    import std.algorithm: max;
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    double maxNumber = args[0].toValue!double;
    for(size_t i = 1; i < args.length; ++i)
    {
        if(!args[i].isNumber)
            return ScriptValue.UNDEFINED;
        immutable temp = args[i].toValue!double;
        if(temp > maxNumber)
            maxNumber = temp;
    }
    return ScriptValue(maxNumber);
}

private ScriptValue native_Math_min(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    import std.algorithm: max;
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    double minNumber = args[0].toValue!double;
    for(size_t i = 1; i < args.length; ++i)
    {
        if(!args[i].isNumber)
            return ScriptValue.UNDEFINED;
        immutable temp = args[i].toValue!double;
        if(temp < minNumber)
            minNumber = temp;
    }
    return ScriptValue(minNumber);
}

private ScriptValue native_Math_pow(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 2)
        return ScriptValue(double.nan);
    if(!args[0].isNumber || !args[1].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.pow(args[0].toValue!double, args[1].toValue!double));
}

private ScriptValue native_Math_random(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    import std.random : uniform;
    return ScriptValue(uniform(0.0, 1.0));
}

private ScriptValue native_Math_round(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.round(args[0].toValue!double));
}

private ScriptValue native_Math_sign(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    immutable num = args[0].toValue!double;
    if(num < 0)
        return ScriptValue(-1);
    else if(num > 0)
        return ScriptValue(1);
    else
        return ScriptValue(0);
}

private ScriptValue native_Math_sin(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.sin(args[0].toValue!double));
}

private ScriptValue native_Math_sinh(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.sinh(args[0].toValue!double));
}

private ScriptValue native_Math_sqrt(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue.UNDEFINED;
    if(!args[0].isNumber)
        return ScriptValue.UNDEFINED;
    return ScriptValue(math.sqrt(args[0].toValue!double));
}

private ScriptValue native_Math_tan(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.tan(args[0].toValue!double));
}

private ScriptValue native_Math_tanh(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.tanh(args[0].toValue!double));
}

private ScriptValue native_Math_trunc(Context context,
        ScriptValue* thisObj,
        ScriptValue[] args,
        ref NativeFunctionError nfe)
{
    if(args.length < 1)
        return ScriptValue(double.nan);
    if(!args[0].isNumber)
        return ScriptValue(double.nan);
    return ScriptValue(math.trunc(args[0].toValue!double));
}


/// software implementation of CLZ32 because I don't know assembly
/// courtesy of https://embeddedgurus.com/state-space/2014/09/fast-deterministic-and-portable-counting-leading-zeros/
pragma(inline) 
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
