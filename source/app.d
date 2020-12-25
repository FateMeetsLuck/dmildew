import std.stdio;
import std.string: strip;

import mildew.context;
import mildew.exceptions;
import mildew.interpreter;
import mildew.lexer;
import mildew.parser;
import mildew.types;

/// testing a native function
ScriptValue native_testPrint(Context c, ScriptValue[] args, ref NativeFunctionError nfe)
{
    foreach(arg; args)
    {
        write(arg.toString ~ " ");
    }
    writeln("");
    return ScriptValue.UNDEFINED;
}

/// testing errors
ScriptValue native_testSum(Context c, ScriptValue[] args, ref NativeFunctionError nfe)
{
    double sum = 0.0;
    foreach(arg ; args)
    {
        if(!arg.isNumber)
        {
            nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
            return ScriptValue.UNDEFINED;
        }
        sum += arg.toValue!double;
    }
    return ScriptValue(sum);
}

/// for now just parses an expression
void evaluateWithErrorChecking(Interpreter interpreter, in string code)
{
    try 
    {
        auto result = interpreter.evaluateStatements(code);
        writefln("The program successfully returned " ~ result.toString);
    }
    catch(ScriptCompileException ex)
    {
        writefln("%s", ex);
    }
    catch(ScriptRuntimeException ex)
    {
        writefln("%s", ex);
    }
}

int main(string[] args)
{
    auto interpreter = new Interpreter();
    interpreter.forceSetGlobal("testPrint", &native_testPrint, true);
    interpreter.forceSetGlobal("testSum", &native_testSum, true);
    while(true)
    {
        write("mildew> ");
        string input = strip(readln());
        if(input == "#exit" || input == "")
            break;
        while(input.length > 0 && input[$-1]=='\\')
        {
            write(">>> ");
            input = input[0..$-1];
            input ~= "\n" ~ strip(readln());
        }
        evaluateWithErrorChecking(interpreter, input);
    }
    writeln("");
    return 0;
}
