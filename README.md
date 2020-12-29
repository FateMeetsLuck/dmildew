# DMildew

A scripting language for the D programming language inspired by Lua and JavaScript.

This is still very much a work in progress.

## Usage

The `examples/` folder contains example scripts. It should look familiar to anyone who knows JavaScript. However, Mildew is not a full feature JavaScript implementation.

This project is in its early stages so you should probably use the ~main version to get the latest bug fixes. The release tags are only so that it is usable in dub.

## Running the Examples

In a terminal in the main project directory run `dub run :repl -- examples/nameOfExample.mds`. If you want to try out the interactive shell simply type `dub run :repl`. In the interactive shell it is only possible to enter multiple lines by writing '\' at the end of a line you want to continue. Note that functions and classes declared in one REPL command will not be accessible in the next unless stored in a var. To store a class such as `class Foo {}` one must write `var Foo = Foo;` immediately after.

## Binding

See mildew/stdlib files for how to bind functions. Classes can be bound by wrapping the object inside a ScriptObject. Methods can be written as free functions or delegates stored inside the bound constructor's prototype object. In the future, there might be a more trivial way to bind using D metaprogramming.

Binding structs can only be done by wrapping the struct inside a class and storing the class object in a ScriptObject.

The function or delegate signature that can be wrapped inside a ScriptAny (and thus ScriptFunction) is `ScriptAny function(Context, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError);` And such a function is wrapped by `ScriptAny(new ScriptFunction("name of function", &nativeFunction))`. This is analogous to how Lua bindings work.

`bindingexample.zip` in the examples folder contains a simple program that binds a class and its public methods and properties. D classes that are bound can be extended by the script as long as the native function constructor checks that the `thisObj` parameter is an object and assigns the native object to it.

## Caveats

This language is stricter than JavaScript. Global variables cannot be redeclared unless they are undefined by setting them to `undefined`. Local variables cannot be redeclared in the same scope likewise. Semicolons are always required.

## Current Goals

* Implement postfix and prefix increment and decrement operators.
* Refactor code to easily implement all math assignment operators (such as `*=`).
* Allow selected bound functions to be used as properties similar to D's UFCS.
* Possibly support importing other scripts from a script. However, most host applications would probably prefer to do this with XML and their own solution.
* Bind classes with one line of code with mixins and template metaprogramming.
* Write a more complete and robust standard library for the scripting language.

