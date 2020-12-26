import std.file: readText;
import std.stdio;
import std.string: strip;

import arsd.terminal;

import mildew.context;
import mildew.exceptions;
import mildew.interpreter;
import mildew.lexer;
import mildew.parser;
import mildew.types;

/// testing a native function
ScriptValue native_testPrint(Context c, ScriptValue* thisObj, ScriptValue[] args, ref NativeFunctionError nfe)
{
    foreach(arg; args)
    {
        write(arg.toString ~ " ");
    }
    writeln("");
    return ScriptValue.UNDEFINED;
}

/// testing errors
ScriptValue native_testSum(Context c, ScriptValue* thisObj, ScriptValue[] args, ref NativeFunctionError nfe)
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
void evaluateWithErrorChecking(Interpreter interpreter, in string code, in string fileName = "<stdin>")
{
    try 
    {
        auto result = interpreter.evaluateStatements(code);
        writefln("The program successfully returned " ~ result.toString);
    }
    catch(ScriptCompileException ex)
    {
        writeln("In file " ~ fileName);
        writefln("%s", ex);
    }
    catch(ScriptRuntimeException ex)
    {
        writeln("In file " ~ fileName);
        writefln("%s", ex);
    }
}

int main(string[] args)
{
    auto terminal = Terminal(ConsoleOutputType.linear);
    auto interpreter = new Interpreter();
    interpreter.initializeStdlib();
    interpreter.forceSetGlobal("testPrint", new ScriptFunction("testPrint", &native_testPrint), true);
    interpreter.forceSetGlobal("testSum", new ScriptFunction("testSum", &native_testSum), true);

    if(args.length > 1)
    {
        immutable fileName = args[1];
        auto code = readText(fileName);
        evaluateWithErrorChecking(interpreter, code, fileName);
    }    
    else
    {
        while(true)
        {
            try 
            {
                write("mildew> ");
                string input = strip(terminal.getline("mildew> "));
                if(input == "#exit" || input == "")
                    break;
                while(input.length > 0 && input[$-1]=='\\')
                {
                    write(">>> ");
                    input = input[0..$-1];
                    input ~= "\n" ~ strip(terminal.getline(">>> "));
                }
                evaluateWithErrorChecking(interpreter, input);
            }
            catch(UserInterruptionException ex)
            {
                break;
            }
        }
        writeln("");
    }
    return 0;
}
