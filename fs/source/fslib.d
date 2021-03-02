module fslib;

import mildew.environment;
import mildew.exceptions;
import mildew.interpreter;
import mildew.types;

version(Windows)
{
    import core.runtime;
    import core.sys.windows.windows;

    private HINSTANCE g_hInst;

    /// required for Windows
    extern (Windows) BOOL DllMain(HINSTANCE hInstance, ULONG ulReason, LPVOID pvReserved) // @suppress(dscanner.style.phobos_naming_convention)
    {
        switch (ulReason)
        {
            case DLL_PROCESS_ATTACH:
                Runtime.initialize();
                break;

            case DLL_PROCESS_DETACH:
                Runtime.terminate();
                break;

            case DLL_THREAD_ATTACH:
                return false;

            case DLL_THREAD_DETACH:
                return false;

            default:
        }
        g_hInst = hInstance;
        return true;
    }
}

/// Initializes the fs library
export extern(C) void initializeModule(Interpreter interpreter)
{
    auto fs = new ScriptObject("fs", null);
    fs["test"] = new ScriptFunction("fs.test", &native_fs_test);
    interpreter.forceSetGlobal("fs", ScriptAny(fs), false);
}

private ScriptAny native_fs_test(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(args.length < 1)
        throw new ScriptRuntimeException("Test exception: pass at least one argument");
    auto num = args[0].toValue!double;
    return ScriptAny(num * 2.0);
}
