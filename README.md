# DMildew

Mildew is a scripting language for the D programming language inspired by Lua and JavaScript. While there are other scripting languages for D such as Lua, one cannot easily use D delegates as C function pointers in those languages. Other languages require modification of the D class in order to bind. With Mildew, bindings for any public method or property can be written without touching the original D class module. The downside is that there are no ways to trivialize this binding process with metaprogramming yet. The prototype inheritance system of Mildew allows scripts to extend D classes in powerful ways.

The ideal use case for this software is for embedding in D games needing a dynamic scriptable GUI. It is not intended to replace Node.js.

This software is licensed under the GNU General Public License version 3.0 so that it may be used in free and open software. For a commercial software usage license, please contact the author. In the future, the license will be changed to LGPL3 when the software is more stable and ready for production use.

## Table of Contents
1. [Usage](#usage)
2. [Mildew Standard Library Documentation](#mildew-standard-library-documentation)
3. [Building](#building)
4. [Compiling and Running Bytecode Files](#compiling-and-running-bytecode-files)
5. [Running the Examples](#running-the-examples)
6. [Binding](#binding)
7. [Caveats](#caveats)
8. [Help](#help)
9. [Current Goals](#current-goals)

<div id="usage"></div>

## Usage 

The `examples/` folder contains example scripts. It should look familiar to anyone who knows JavaScript. However, Mildew is not a full feature ES6 JavaScript implementation.

This project is in its early stages so one should probably use the ~main version to get the latest bug fixes. The release tags are only so that it is usable in dub.

<div id="mildew-standard-library-documentation"></div>

## Mildew Standard Library Documentation 

The documentation for the standard library, which is only loaded if the host application chooses to do so, can be found [here](https://pillager86.github.io/dmildew/).

<div id="building"></div>

## Building 

Building the library is as simple as writing `dub build` in a terminal in the main project directory. To build the REPL and script runner one can write `dub build Mildew:run` in the same directory as the main project. Add `-b release` to the build commands to generate an optimized binary that performs slightly better than the default debugging build.

<div id="compiling-and-running-bytecode-files"></div>

## Compiling and Running Bytecode Files

A script can be compiled with `dub run Mildew:bccompiler -- <name of script file.mds> -o <name of binary.mdc>` and the resulting binary bytecode file can be run directly with the REPL as if it were a normal text file of source code.

<div id="running-the-examples"></div>

## Running the Examples

In a terminal in the main project directory run `dub run Mildew:run -- examples/<nameofexample>.mds`. To try out the interactive shell simply type `dub run dmilew:run`. In the interactive shell it is only possible to continue a command on a new line by writing a single backslash at the end of a line. Note that functions and classes declared in one REPL command will not be accessible in the next unless stored in a var. To store a class such as `class Foo {}` one must write `var Foo = Foo;` immediately after. One can also store anonymous class expressions in a global variable such as `var Foo = class {};`.

The option `-d` prints bytecode disassembly before running each chunk of code. The `-v` option prints highly verbose step by step execution of bytecode in the virtual machine.

<div id="binding"></div>

## Binding

See mildew/stdlib files for how to bind free functions. Classes are bound by assigning the native D object to the thisObj's nativeObject field after casting the thisObj to ScriptObject. The constructor function or delegate should have a "prototype" field containing functions to serve as the bound D class methods. The "prototype" field itself should have a field called "constructor" set to the constructor so that the `instanceof` operator will work. The Date and RegExp libraries are a good example of how class binding works.

Binding structs can only be done by wrapping the struct inside a class and storing the class object in a ScriptObject.

The function or delegate signature that can be wrapped inside a ScriptAny (and thus ScriptFunction) is `ScriptAny function(Context, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError);` And such a function is wrapped by `ScriptAny(new ScriptFunction("name of function", &nativeFunction))`. This is analogous to how Lua bindings work.

`bindingexample2.zip` in the examples folder contains a simple program that binds a class and its public methods and properties. D classes that are bound can be extended by the script as long as the native function constructor checks that the `thisObj` parameter is an object and assigns the native object to its `nativeObject` field. `bindingexample3.zip` shows a more advanced example of binding D classes that have an inheritance hierarchy. The power of Mildew is that methods written for the base class will automatically work on the bound subclasses.

<div id="caveats"></div>

## Caveats

This language is stricter than JavaScript. Global variables cannot be redeclared unless they are undefined by setting them to `undefined`. Local variables cannot be redeclared in the same scope likewise. However, it is possible to check if a variable is defined using the `isdefined` function of the standard library, which takes a string value equal to the variable name. Semicolons are required in a manner similar to C# or Java.

Since all programs are run in a new scope, the `var` keyword declares variables that are stored in the global scope, while `let` and `const` work the same as in ES6. This is more similar to Lua.

For-in loops over Strings iterate for each unicode code point, rather than each 8-bit character, although Strings are internally stored as UTF-8. Array indexing of Strings can access individual 8-bit characters as long as they form a complete code point.

To declare a function to be stored in an object, one must write `objectName.fieldName = function(...)...` because `function objectName.fieldName(...)...` declarations do not work.

Binding classes by extending ScriptObject will not work and is not supported. Script classes that extend native D classes must call `super` in a constructor for it to work even if there are no parameters.

Closure functions that refer to variables in an outer scope beyond the immediate function declaration scope can have variables shadowed by declaring them in the same scope. See examples/thistest.mds for the issue.

The "super" keyword cannot be used to access static base class methods.

Mildew is not optimized for computationally heavy tasks. The design of the language focuses on interoperability with D native functions and CPU intensive operations should be moved to native implementations and called from the scripting language.

Mildew has only been tested on Windows and Linux x86_64 operating systems. Please test on other operating systems to report problems. Note that compiled bytecode is platform dependent (endianness matters) and bytecode scripts must be compiled for each type of CPU, similar to Lua.

<div id="help"></div>

## Help

There is now a ##dmildew channel on the Freenode IRC network. If no one is there, leave a question or comment on the github project page.

<div id="current-goals"></div>

## Current Goals

* Implement all math assignment operators (such as `*=`).
* Possibly support importing other scripts from a script. However, most host applications would probably prefer to do this with XML and their own solution.
* Implement ES6 destructuring declaration and assignments of arrays and objects into variables.
* Bind native classes and functions with one line of code with mixins and template metaprogramming. Or write software that will analyze D source files and generate bindings.
* Write a more complete and robust standard library for the scripting language. (In progress.)
* Allow certain unicode characters as components of variable names.
