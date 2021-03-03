/// Inspired by bindbc-loader. Implements shared library module loading.
module loader;

import core.runtime: Runtime;
import std.string: toStringz;

import mildew.interpreter;

package:

static if((void*).sizeof == 8)
{
    enum BIND64 = true;
    enum BIND32 = false;
}
else
{
    enum BIND64 = false;
    enum BIND32 = true;
}

version(Windows) enum BIND_WINDOWS = true;
else enum BIND_WINDOWS = false;

version(OSX) enum BIND_MAC = true;
else enum BIND_MAC = false;

version(linux) enum BIND_LINUX = true;
else enum BIND_LINUX = false;

version(Posix) enum BIND_POSIX = true;
else enum BIND_POSIX = false;

version(Android) enum BIND_ANDROID = true;
else enum BIND_ANDROID = false;

enum BIND_IOS = false;
enum BIND_WINRT = false;

version(FreeBSD) 
{
    enum BIND_BSD = true;
    enum BIND_FREEBSD = true;
    enum BIND_OPENBSD = false;
}
else version(OpenBSD)
{
    enum BIND_BSD = true;
    enum BIND_FREEBSD = false;
    enum BIND_OPENBSD = true;
}
else
{
    enum BIND_BSD = false;
    enum BIND_FREEBSD = false;
    enum BIND_OPENBSD = false;
}

/// Shared library
public struct SharedLib
{
    private void* _handle;
}

enum INVALID_HANDLE = SharedLib.init;

/// Load a symbol from the library
public void bindSymbol(SharedLib lib, void** ptr, in string symbolName)
{
    pragma(inline, false);

    if(lib._handle == null)
        throw new LoaderException("Library handle is null");
    auto sym = loadSymbol(lib._handle, symbolName); // @suppress(dscanner.suspicious.unmodified)
    if(sym)
        *ptr = sym;
    else
        throw new LoaderException("Failed to load symbol " ~ symbolName ~ ":" ~ sysError());
}

void bindSymbolStdCall(T)(SharedLib lib, ref T ptr, string symbolName)
{
    static if(BIND_WINDOWS && BIND32) 
    {
        import std.format: format;
        import std.traits: ParameterTypeTuple;
        uint paramSize(A...)(A args)
        {
            size_t sum = 0;
            foreach(arg; args) 
            {
                sum += arg.sizeof;
                if((sum & 3) != 0)
                    sum += 4 - (sum & 3);
            }
            return sum;
        }
        ParameterTypeTuple!f params;
        immutable mangled = format("_%s@%d", symbolName, paramSize(params));
        symbolName = mangled;
    }
    bindSymbol(lib, cast(void**)&ptr, symbolName);
}

/// load the library without running the init function
public SharedLib load(in string libName)
{
    auto handle = loadLib(libName);
    if(handle)
        return SharedLib(handle);
    else
        throw new LoaderException("Failed to load library " ~ libName ~ ":" ~ sysError());
}

/// Unload library
public void unload(ref SharedLib lib)
{
    if(lib._handle)
    {
        unloadLib(lib._handle);
        lib = INVALID_HANDLE;
    }
}

version(Windows)
{
    import core.sys.windows.windows;
    extern(Windows) @nogc nothrow alias pSetDLLDirectory = BOOL function(const(char)*);
    pSetDLLDirectory setDLLDirectory;

    void* loadLib(string name)
    {
        // return LoadLibraryA(name.toStringz);
        return Runtime.loadLibrary(name);
    }

    void unloadLib(void* lib)
    {
        FreeLibrary(lib);
    }

    void* loadSymbol(void* lib, string symbolName)
    {
        return GetProcAddress(lib, symbolName.toStringz);
    }

    string sysError()
    {
        import std.conv: to;
        import core.stdc.string: strlen;
        char* msgBuf;
        enum uint LANG_ID = MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT);

        FormatMessageA(FORMAT_MESSAGE_ALLOCATE_BUFFER| FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
            null, GetLastError(), LANG_ID, cast(char*)msgBuf, 0, null);
        
        if(msgBuf) 
        {
            string message = msgBuf[0..strlen(msgBuf)].idup ~ '\0';
            LocalFree(msgBuf);
            return message;
        }
        else 
        {
            return "Unknown Error";
        }
    }

    public bool setCustomLoaderSearchPath(string path)
    {
        if(!setDLLDirectory)
        {
            auto lib = load("Kernel32.dll");
            if(lib == INVALID_HANDLE)
                return false;
            lib.bindSymbol(cast(void**)setDLLDirectory, "SetDllDirectoryA");
            if(!setDLLDirectory)
                return false;
        }
        return setDLLDirectory(path.toStringz) != 0;
    }
}
else version(Posix)
{
    import core.sys.posix.dlfcn;

    void* loadLib(string name)
    {
        // return dlopen(name.toStringz, RTLD_NOW);
        return Runtime.loadLibrary(name);
    }

    void unloadLib(void* lib)
    {
        dlclose(lib);
    }

    void* loadSymbol(void* lib, string symbolName)
    {
        return dlsym(lib, symbolName.toStringz);
    }

    string sysError()
    {
        import std.conv: to;
        auto msg = dlerror();
        if(msg == null)
            return "Unknown Error";
        return to!string(msg);
    }
}
else static assert(false, "Loader is not implemented on this platform.");

alias p_initializeModule = void function(Interpreter interpreter);

public:

/// loads and runs the initializer
SharedLib loadAndInitModule(string directory, string libname, Interpreter interpreter)
{
    import std.stdio: writefln;

    version(Windows)
    {
        libname = libname ~ ".dll";
    }
    else version(OSX)
    {
        libname = "lib" ~ libname ~ ".dylib";
    }
    else version(Posix)
    {
        libname = "lib" ~ libname ~ ".so";
    }
    else static assert(false, "Library cannot be loaded on this platform");

    if(directory.length > 0 && directory[$-1] != '/')
        directory ~= "/";
    libname = directory ~ libname;

    auto lib = load(libname);
    if(lib == INVALID_HANDLE)
        throw new LoaderException("Unable to load library " ~ libname);
    p_initializeModule initializeModule;
    lib.bindSymbol(cast(void**)&initializeModule, "initializeModule");

    initializeModule(interpreter);
    return lib;
}

/// Library load exception
class LoaderException : Exception
{
    /// constructor
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}
