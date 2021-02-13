import std.stdio;

import std.file: readText, FileException;
import std.getopt;
import mildew.compiler;
import mildew.exceptions;
import mildew.vm;

private void printUsage()
{
    stderr.writeln("Usage: <name of script file> [-o=<outputfile>]");
}

int main(string[] args)
{
    string outputFile = "out.mdc";
    try 
    {
        auto options = getopt(args, "out|o", &outputFile); // @suppress(dscanner.suspicious.unmodified)
        if(options.helpWanted)
        {
            printUsage();
            return 1;
        }
    }
    catch(Exception)
    {
        printUsage();
        return 64;
    }

    if(args.length < 2)
    {
        stderr.writeln("Input file not specified");
        return 64;
    }

    string inputFile = args[1];
    string sourceText = "";
    try 
    {
        sourceText = readText(inputFile);
    }
    catch(FileException fex)
    {
        stderr.writefln("Unable to read input file `%s`", inputFile);
        stderr.writeln(fex.msg);
        return 66;
    }

    auto compiler = new Compiler();

    try 
    {
        auto chunk = compiler.compile(sourceText); // @suppress(dscanner.suspicious.unmodified)
        File outFile = File(outputFile, "wb");
        auto raw = chunk.serialize();
        outFile.rawWrite(raw);
        outFile.close();
        auto testChunk = Chunk.deserialize(raw);
    }
    catch(ScriptCompileException ex)
    {
        stderr.writeln(ex.msg);
        return 1;
    }
    catch(FileException ex)
    {
        stderr.writefln("Unable to write to output file `%s`", outputFile);
        stderr.writeln(ex.msg);
        return 1;
    }

    return 0;
}
