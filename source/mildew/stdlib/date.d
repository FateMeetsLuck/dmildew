/**
Bindings for the script Date class. This module contains both the D class definition and the script bindings.

────────────────────────────────────────────────────────────────────────────────

Copyright (C) 2021 pillager86.rf.gd

This program is free software: you can redistribute it and/or modify it under 
the terms of the GNU General Public License as published by the Free Software 
Foundation, either version 3 of the License, or (at your option) any later 
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with 
this program.  If not, see <https://www.gnu.org/licenses/>.
*/
module mildew.stdlib.date;

import core.time: TimeException;
import std.datetime.systime;
import std.datetime.date;
import std.datetime.timezone;

import mildew.binder;
import mildew.environment;
import mildew.interpreter;
import mildew.types;

/** 
 * Initializes the Date library, which includes the Date() constructor. Documentation for the
 * library can be found at https://pillager86.github.io/dmildew/
 * Params:
 *  interpreter = The Interpreter object for which to load the library.
 */
void initializeDateLibrary(Interpreter interpreter)
{
    auto Date_ctor = new ScriptFunction("Date", &native_Date_ctor, true);
    Date_ctor["prototype"]["getDate"] = new ScriptFunction("Date.prototype.getDate", &native_Date_getDate);
    Date_ctor["prototype"]["getDay"] = new ScriptFunction("Date.prototype.getDay", &native_Date_getDay);
    Date_ctor["prototype"]["getFullYear"] = new ScriptFunction("Date.prototype.getFullYear", 
            &native_Date_getFullYear);
    Date_ctor["prototype"]["getHours"] = new ScriptFunction("Date.prototype.getHours", 
            &native_Date_getHours);
    Date_ctor["prototype"]["getMilliseconds"] = new ScriptFunction("Date.prototype.getMilliseconds", 
            &native_Date_getMilliseconds);
    Date_ctor["prototype"]["getMinutes"] = new ScriptFunction("Date.prototype.getMinutes", 
            &native_Date_getMinutes);
    Date_ctor["prototype"]["getMonth"] = new ScriptFunction("Date.prototype.getMonth", 
            &native_Date_getMonth);
    Date_ctor["prototype"]["getSeconds"] = new ScriptFunction("Date.prototype.getSeconds", 
            &native_Date_getSeconds);
    Date_ctor["prototype"]["getTime"] = new ScriptFunction("Date.prototype.getTime", 
            &native_Date_getTime);
    Date_ctor["prototype"]["getTimezone"] = new ScriptFunction("Date.prototype.getTimezone", 
            &native_Date_getTimezone);
    Date_ctor["prototype"]["setDate"] = new ScriptFunction("Date.prototype.setDate", 
            &native_Date_setDate);
    Date_ctor["prototype"]["setFullYear"] = new ScriptFunction("Date.prototype.setFullYear", 
            &native_Date_setFullYear);
    Date_ctor["prototype"]["setHours"] = new ScriptFunction("Date.prototype.setHours", 
            &native_Date_setHours);
    Date_ctor["prototype"]["setMilliseconds"] = new ScriptFunction("Date.prototype.setMillseconds", 
            &native_Date_setMilliseconds);
    Date_ctor["prototype"]["setMinutes"] = new ScriptFunction("Date.prototype.setMinutes", 
            &native_Date_setMinutes);
    Date_ctor["prototype"]["setMonth"] = new ScriptFunction("Date.prototype.setMonth", 
            &native_Date_setMonth);
    Date_ctor["prototype"]["setSeconds"] = new ScriptFunction("Date.prototype.setSeconds", 
            &native_Date_setSeconds);
    Date_ctor["prototype"]["setTime"] = new ScriptFunction("Date.prototype.setTime", 
            &native_Date_setTime);
    Date_ctor["prototype"]["toDateString"] = new ScriptFunction("Date.prototype.toDateString", 
            &native_Date_toDateString);
    Date_ctor["prototype"]["toISOString"] = new ScriptFunction("Date.prototype.toISOString", 
            &native_Date_toISOString);
    Date_ctor["prototype"]["toUTC"] = new ScriptFunction("Date.prototype.toUTC", 
            &native_Date_toUTC);
    interpreter.forceSetGlobal("Date", Date_ctor, false);
}

package:

/**
 * The Date class
 */
class ScriptDate
{
public:
    /**
     * Creates a Date representing the time and date of object creation
     */ 
    this()
    {
        _sysTime = Clock.currTime();
    }

    this(in long num)
    {
        _sysTime = SysTime.fromUnixTime(num);
    }

    /// takes month 0-11 like JavaScript
    this(in int year, in int monthIndex, in int day=1, in int hours=0, in int minutes=0, 
         in int seconds=0, in int milliseconds=0)
    {
        import core.time: msecs;
        auto dt = DateTime(year, monthIndex+1, day, hours, minutes, seconds);
        _sysTime = SysTime(dt, msecs(milliseconds), UTC());
    }

    /// This string has to be formatted as "2020-Jan-01 00:00:00" for example. Anything different throws an exception
    this(in string str)
    {
        auto dt = DateTime.fromSimpleString(str);
        _sysTime = SysTime(dt, UTC());
    }

    /// returns day of month
    int getDate() const
    {
        auto dt = cast(DateTime)_sysTime;
        return dt.day;
    }

    /// returns day of week
    int getDay() const
    {
        auto dt = cast(DateTime)_sysTime;
        return dt.dayOfWeek;
    }

    int getFullYear() const
    {
        auto dt = cast(DateTime)_sysTime;
        return dt.year;
    }

    /// get the hour of the date
    int getHours() const
    {
        return _sysTime.hour;
    }

    long getMilliseconds() const
    {
        return _sysTime.fracSecs.total!"msecs";
    }

    int getMinutes() const
    {
        return _sysTime.minute;
    }

    /// returns month from 0-11
    int getMonth() const
    {
        return cast(int)(_sysTime.month) - 1;
    }

    int getSeconds() const
    {
        return _sysTime.second;
    }

    long getTime() const
    {
        return _sysTime.toUnixTime * 1000; // TODO fix
    }

    long getTimezone() const
    {
        return _sysTime.timezone.utcOffsetAt(_sysTime.stdTime).total!"minutes";
    }

    // TODO UTC stuff

    void setDate(in int d)
    {
        _sysTime.day = d;
    }

    void setFullYear(in int year)
    {
        _sysTime.year = year;
    }

    void setHours(in int hours, in int minutes=0, in int seconds=0)
    {
        _sysTime.hour = hours;
        _sysTime.minute = minutes;
        _sysTime.second = seconds;
    }

    void setMilliseconds(in uint ms)
    {
        import core.time: msecs, Duration;
        _sysTime.fracSecs = msecs(ms);
    }

    void setMinutes(in uint minutes)
    {
        _sysTime.minute = minutes;
    }

    void setMonth(in uint month)
    {
        _sysTime.month = cast(Month)(month % 12 + 1);
    }

    void setSeconds(in uint s)
    {
        _sysTime.second = cast(ubyte)(s%60);
    }

    void setTime(in long unixTimeMs)
    {
        _sysTime = _sysTime.fromUnixTime(unixTimeMs / 1000); // TODO fix
    }

    string toISOString() const
    {
        auto dt = cast(DateTime)_sysTime;
        return dt.toISOString();
    }

    ScriptDate toUTC() const
    {
        auto newSD = new ScriptDate(0);
        newSD._sysTime = _sysTime.toUTC();
        return newSD;
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

ScriptAny native_Date_ctor(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(!thisObj.isObject)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    auto obj = thisObj.toValue!ScriptObject;
    try 
    {
        if(args.length == 0)
            obj.nativeObject = new ScriptDate();
        else if(args.length == 1)
        {
            if(args[0].isNumber)
                obj.nativeObject = new ScriptDate(args[0].toValue!long);
            else
                obj.nativeObject = new ScriptDate(args[0].toString());
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
            obj.nativeObject = new ScriptDate(year, month, day, hours, minutes, seconds, mseconds);
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

ScriptAny native_Date_getDate(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto date = thisObj.toNativeObject!ScriptDate;
    if(date is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    return ScriptAny(date.getDate());
}

ScriptAny native_Date_getDay(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto date = thisObj.toNativeObject!ScriptDate;
    if(date is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    return ScriptAny(date.getDay());
}

ScriptAny native_Date_getFullYear(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto date = thisObj.toNativeObject!ScriptDate;
    if(date is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    return ScriptAny(date.getFullYear());
}

ScriptAny native_Date_getHours(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto date = thisObj.toNativeObject!ScriptDate;
    if(date is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    return ScriptAny(date.getHours());
}

ScriptAny native_Date_getMilliseconds(Environment env, ScriptAny* thisObj, 
                                      ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto date = thisObj.toNativeObject!ScriptDate;
    if(date is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    return ScriptAny(date.getMilliseconds());
}

ScriptAny native_Date_getMinutes(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto date = thisObj.toNativeObject!ScriptDate;
    if(date is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    return ScriptAny(date.getMinutes());
}

ScriptAny native_Date_getMonth(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    if(!thisObj.isObject)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    auto dateObj = (*thisObj).toValue!ScriptDate;
    if(dateObj is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    return ScriptAny(dateObj.getMonth);
}

ScriptAny native_Date_getSeconds(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto date = thisObj.toNativeObject!ScriptDate;
    if(date is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    return ScriptAny(date.getSeconds());
}

ScriptAny native_Date_getTime(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto date = thisObj.toNativeObject!ScriptDate;
    if(date is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    return ScriptAny(date.getTime());
}

ScriptAny native_Date_getTimezone(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    auto date = thisObj.toNativeObject!ScriptDate;
    if(date is null)
    {
        nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
        return ScriptAny.UNDEFINED;
    }
    return ScriptAny(date.getTimezone());
}

ScriptAny native_Date_setDate(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    mixin(CHECK_THIS_NATIVE_OBJECT!("date", ScriptDate));
    mixin(TO_ARG_CHECK_INDEX!("d", 0, int));
    try 
    {
        date.setDate(d);
    }
    catch(TimeException ex)
    {
        nfe = NativeFunctionError.RETURN_VALUE_IS_EXCEPTION;
        return ScriptAny(ex.msg);
    }
    return ScriptAny.UNDEFINED;
}

ScriptAny native_Date_setFullYear(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    mixin(CHECK_THIS_NATIVE_OBJECT!("date", ScriptDate));
    mixin(TO_ARG_CHECK_INDEX!("year", 0, int));
    try // this might not be needed here
    {
        date.setFullYear(year);
    }
    catch(TimeException ex)
    {
        nfe = NativeFunctionError.RETURN_VALUE_IS_EXCEPTION;
        return ScriptAny(ex.msg);
    }
    return ScriptAny.UNDEFINED;
}

ScriptAny native_Date_setHours(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    mixin(CHECK_THIS_NATIVE_OBJECT!("date", ScriptDate));
    mixin(TO_ARG_CHECK_INDEX!("hour", 0, int));
    mixin(TO_ARG_OPT!("minute", 1, 0, int));
    mixin(TO_ARG_OPT!("second", 2, 0, int));
    date.setHours(hour%24, minute%60, second%60);
    return ScriptAny.UNDEFINED;
}

ScriptAny native_Date_setMilliseconds(Environment env, ScriptAny* thisObj, 
                                      ScriptAny[] args, ref NativeFunctionError nfe)
{
    mixin(CHECK_THIS_NATIVE_OBJECT!("date", ScriptDate));
    mixin(TO_ARG_CHECK_INDEX!("ms", 0, uint));
    date.setMilliseconds(ms % 1000);
    return ScriptAny.UNDEFINED;
}

ScriptAny native_Date_setMinutes(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    mixin(CHECK_THIS_NATIVE_OBJECT!("date", ScriptDate));
    mixin(TO_ARG_CHECK_INDEX!("minutes", 0, uint));
    date.setMinutes(minutes % 60);
    return ScriptAny.UNDEFINED;
}

ScriptAny native_Date_setMonth(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    mixin(CHECK_THIS_NATIVE_OBJECT!("date", ScriptDate));
    mixin(TO_ARG_CHECK_INDEX!("m", 0, uint));
    try 
    {
        date.setMonth(m);
    }
    catch(TimeException ex)
    {
        nfe = NativeFunctionError.RETURN_VALUE_IS_EXCEPTION;
        return ScriptAny(ex.msg);
    }
    return ScriptAny.UNDEFINED;
}

ScriptAny native_Date_setSeconds(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    mixin(CHECK_THIS_NATIVE_OBJECT!("date", ScriptDate));
    mixin(TO_ARG_CHECK_INDEX!("s", 0, uint));
    date.setSeconds(s);
    return ScriptAny.UNDEFINED;
}

ScriptAny native_Date_setTime(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    mixin(CHECK_THIS_NATIVE_OBJECT!("date", ScriptDate));
    mixin(TO_ARG_CHECK_INDEX!("t", 0, long));
    date.setTime(t);
    return ScriptAny.UNDEFINED;
}

ScriptAny native_Date_toDateString(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    mixin(CHECK_THIS_NATIVE_OBJECT!("date", ScriptDate));
    return ScriptAny(date.toString());
}

ScriptAny native_Date_toISOString(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    mixin(CHECK_THIS_NATIVE_OBJECT!("date", ScriptDate));
    return ScriptAny(date.toISOString());
}

ScriptAny native_Date_toUTC(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
{
    mixin(CHECK_THIS_NATIVE_OBJECT!("date", ScriptDate));
    auto newDate = date.toUTC();
    auto newSD = new ScriptObject("Date", thisObj.toValue!ScriptObject.prototype, newDate);
    return ScriptAny(newSD);
}
