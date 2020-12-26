module mildew.stdlib.math;

import math=std.math;

import mildew.context;
import mildew.interpreter;
import mildew.types;

/// initializes the Math object
public void initializeMathLibrary(Interpreter interpreter)
{
    ScriptObject mathNamespace = new ScriptObject("Math", null, null);
    mathNamespace["abs"] = ScriptValue(new ScriptFunction("Math.abs", &native_Math_abs));
    mathNamespace["acos"] = ScriptValue(new ScriptFunction("Math.acos", &native_Math_acos));
    interpreter.forceSetGlobal("Math", mathNamespace, true);
}

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