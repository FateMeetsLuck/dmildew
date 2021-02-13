/**
 * This module contains the main function for the REPL. It also runs script files.
 */
module app;

import std.file: readText, FileException;
import std.getopt;
import std.stdio;
import std.string: strip;

import arsd.terminal;

import mildew.compiler : Compiler;
import mildew.exceptions;
import mildew.interpreter;
import mildew.lexer;
import mildew.parser;
import mildew.types;

/**
 * This runs a script program and prints the appropriate error message when a script exception is caught.
 */
void evaluateWithErrorChecking(Interpreter interpreter, in string source, in string fileName, bool printDisasm)
{
    try 
    {
        ScriptAny result;
        if(source == "" && fileName != "<stdin>")
            result = interpreter.evaluateFile(fileName, printDisasm);
        else
            result = interpreter.evaluate(source, printDisasm);
        writeln("The program successfully returned " ~ result.toString);
    }
    catch(ScriptCompileException ex)
    {
        stderr.writeln("In file " ~ fileName);
        stderr.writefln("%s", ex);
    }
    catch(ScriptRuntimeException ex)
    {
        stderr.writeln("In file " ~ fileName);
        stderr.writefln("%s", ex);
        if(ex.thrownValue.type != ScriptAny.Type.UNDEFINED)
            stderr.writefln("Value thrown: %s", ex.thrownValue);
    }
    catch(Compiler.UnimplementedException ex)
    {
        stderr.writeln(ex.msg);
    }
}

private void printUsage()
{
    stderr.writeln("Usage: dmildew_run <scriptfile> [options]");
    stderr.writeln("       dmildew_run [options]");
    stderr.writeln("Options: -usevm : Use bytecode generation instead of tree walker (experimental)");
    stderr.writeln("         -h     : Print this usage message");
}

/**
 * Main function for the REPL or interpreter. If no command line arguments are specified, it enters
 * interactive REPL mode, otherwise it attempts to execute the first argument as a script file.
 */
int main(string[] args)
{
    auto terminal = Terminal(ConsoleOutputType.linear);
    bool useVM = false;
    bool printVMDebugInfo = false;
    bool printDisasm = false;

    try 
    {
        auto options = cast(immutable)getopt(args, 
                "usevm|u", &useVM,
                "verbose|v", &printVMDebugInfo,
                "disasm|d", &printDisasm);
        if(options.helpWanted) 
        {
            printUsage();
            return 1;
        }
    }
    catch(Exception ex)
    {
        printUsage();
        return 64;
    }

    auto interpreter = new Interpreter(useVM, printVMDebugInfo);
    interpreter.initializeStdlib();

    if(args.length > 1)
    {
        string[] fileNames = args[1..$];
        foreach(fileName ; fileNames)
            evaluateWithErrorChecking(interpreter, "", fileName, printDisasm);
    }    
    else
    {
        while(true)
        {
            try 
            {
                string input = strip(terminal.getline("mildew> "));
                if(input == "#exit" || input == "")
                    break;
                while(input.length > 0 && input[$-1]=='\\')
                {
                    input = input[0..$-1];
                    input ~= "\n" ~ strip(terminal.getline(">>> "));
                }
                writeln();
                evaluateWithErrorChecking(interpreter, input, "<stdin>", printDisasm);
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
