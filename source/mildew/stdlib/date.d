/**
 * Bindings for the script Date class
 */
module mildew.stdlib.date;

import std.datetime.systime;
import std.datetime.date;
import std.datetime.timezone;

import mildew.context;
import mildew.interpreter;
import mildew.types;

/// Initializes the Date library
void initializeDateLibrary(Interpreter interpreter)
{
    auto Date_ctor = new ScriptFunction("Date", &native_Date_ctor, true);
    Date_ctor["prototype"] = getDatePrototype();
    interpreter.forceSetGlobal("Date", Date_ctor, false);
}

package:

/**
 * The Date class
 */
class ScriptDate : ScriptObject
{
public:
    /**
     * Creates a Date representing the time and date of object creation
     */ 
    this()
    {
        super("Date", getDatePrototype());
        _sysTime = Clock.currTime();
    }

    this(in long num)
    {
        super("Date", getDatePrototype());
        _sysTime = SysTime.fromUnixTime(num);
    }

    this(in int year, in int monthIndex, in int day=1, in int hours=0, in int minutes=0, 
         in int seconds=0, in int milliseconds=0)
    {
        import core.time: msecs;
        super("Date", getDatePrototype());
        auto dt = DateTime(year, monthIndex+1, day, hours, minutes, seconds);
        _sysTime = SysTime(dt, msecs(milliseconds), UTC());
    }

    this(in string str)
    {
        super("Date", getDatePrototype());
        auto dt = DateTime.fromSimpleString(str);
        _sysTime = SysTime(dt, UTC());
    }

    override string toString() const
    {
        auto tz = _sysTime.timezone.dstName;
        return (cast(DateTime)_sysTime).toString() ~ " " ~ tz;
    }

private:
    SysTime _sysTime;
}

private:

ScriptObject _datePrototype;

ScriptObject getDatePrototype()
{
    if(_datePrototype is null)
    {
        _datePrototype = new ScriptObject("Date", null);
        // nothing to put here yet
    }
    return _datePrototype;
}

ScriptAny native_Date_ctor(Context c, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    import core.time: TimeException;
    try 
    {
        if(args.length == 0)
            *thisObj = new ScriptDate();
        else if(args.length == 1)
        {
            if(args[0].isNumber)
                *thisObj = new ScriptDate(args[0].toValue!long);
            else
                *thisObj = new ScriptDate(args[0].toString());
        }
        else if(args.length >= 2)
        {
            immutable year = args[0].toValue!int;
            immutable month = args[1].toValue!int;
            immutable day = args.length > 2? args[2].toValue!int : 1;
            immutable hours = args.length > 3 ? args[3].toValue!int : 0;
            immutable minutes = args.length > 4 ? args[4].toValue!int : 0; 
            immutable seconds = args.length > 5 ? args[5].toValue!int : 0;
            immutable mseconds = args.length > 6 ? args[6].toValue!int : 0;
            *thisObj = new ScriptDate(year, month, day, hours, minutes, seconds, mseconds);
        }
        else
            nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
    }
    catch(TimeException tex)
    {
        nfe = NativeFunctionError.RETURN_VALUE_IS_EXCEPTION;
        return ScriptAny(tex.msg);
    }
    return ScriptAny.UNDEFINED;
}
