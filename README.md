# DMildew

A scripting language for the D programming language inspired by Lua and JavaScript. While there are other scripting languages for D such as Lua, one cannot use D delegates as C function pointers in those languages. Other languages require modification of the D class in order to bind. With Mildew, bindings for any public method or property can be written without touching the original D class module. The downside is that there are no ways to trivialize this binding process with metaprogramming yet. The prototype inheritance system of Mildew allows scripts to extend D classes in powerful ways.

This software is licensed under the GNU General Public License version 3.0 so that it may be used in free and open software. For a commercial software usage license, please contact the author.

Note: this is still very much a work in progress and the API is subject to change at any time.

## Usage

The `examples/` folder contains example scripts. It should look familiar to anyone who knows JavaScript. However, Mildew is not a full feature ES6 JavaScript implementation.

This project is in its early stages so one should probably use the ~main version to get the latest bug fixes. The release tags are only so that it is usable in dub.

## Building

Building the library is as simple as writing `dub build` in a terminal in the main project directory. To build the REPL and script runner one can write `dub build :run` in the same directory as the main project.

## Running the Examples

In a terminal in the main project directory run `dub run :run -- examples/nameofexample.mds`. To try out the interactive shell simply type `dub run :run`. In the interactive shell it is only possible to continue a command on a new line by writing a single backslash at the end of a line. Note that functions and classes declared in one REPL command will not be accessible in the next unless stored in a var. To store a class such as `class Foo {}` one must write `var Foo = Foo;` immediately after. One can also store anonymous class expressions in a global variable such as `var Foo = class {};`.

## Binding

See mildew/stdlib files for how to bind functions. Classes can be bound by wrapping the object inside a ScriptObject's nativeObject field. Methods can be written as free functions or delegates stored inside the bound constructor's "prototype" dictionary entry. (This is not to be confused with the prototype property on each ScriptObject.)

Binding structs can only be done by wrapping the struct inside a class and storing the class object in a ScriptObject.

The function or delegate signature that can be wrapped inside a ScriptAny (and thus ScriptFunction) is `ScriptAny function(Context, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError);` And such a function is wrapped by `ScriptAny(new ScriptFunction("name of function", &nativeFunction))`. This is analogous to how Lua bindings work.

`bindingexample2.zip` in the examples folder contains a simple program that binds a class and its public methods and properties. D classes that are bound can be extended by the script as long as the native function constructor checks that the `thisObj` parameter is an object and assigns the native object to its `nativeObject` field.

## Caveats

This language is stricter than JavaScript. Global variables cannot be redeclared unless they are undefined by setting them to `undefined`. Local variables cannot be redeclared in the same scope likewise. Semicolons are required in a manner similar to C# or Java.

Since all programs are run in a scope, the `var` keyword declares variables that are stored in the global scope, while `let` and `const` work the same as in ES6. This is more similar to Lua.

For-of loops cannot iterate over chars in a string so one has to write a regular for-loop that checks the length. For-of and for-in loops are the same.

To declare a function to be stored in an object, one must write `objectName.fieldName = function(...)...` as `function objectName.fieldName(...)...` declarations do not work.

Binding classes by extending ScriptObject will not work and is not supported. Script classes that extend native D classes must call `super` in a constructor for it to work even if there are no parameters.

## Help

There is now a ##dmildew channel on the Freenode IRC network. If no one is there, leave a question or comment on the github project page.

## Current Goals

* Refactor code to easily implement all math assignment operators (such as `*=`).
* Possibly support importing other scripts from a script. However, most host applications would probably prefer to do this with XML and their own solution.
* Implement ES6 destructuring declaration and assignments of arrays and objects into variables.
* Implement lambda functions.
* Implement a regular expression library. Regex literals will probably never be supported.
* Bind native classes and functions with one line of code with mixins and template metaprogramming.
* Write a more complete and robust standard library for the scripting language.
* Allow super keyword to be used to call base class methods and properties other than the constructor.
* Allow unicode support for source code text.
* Reduce parse tree to low level bytecode.
* Implement yield keyword.
