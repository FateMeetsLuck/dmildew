/**
This module implements functions for validating and extracting the parts of regular expressions
between '/'s.

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
module mildew.util.regex;

import std.regex: regex, RegexException;

/// Extract both parts from a regular expression described by e.g. /foo/g
string[] extract(string slashRegex)
{
    if(slashRegex.length < 0 || slashRegex[0] != '/')
        throw new Exception("Not a regular expression");
    immutable size_t patternStart = 1;
    size_t patternEnd;
    for(auto i = slashRegex.length; i > 0; --i)
    {
        if(slashRegex[i-1] == '/')
        {
            patternEnd = i - 1;
            break;
        }
    }
    if(patternEnd == 0)
        throw new Exception("Not a valid regular expression string");
    string pattern = slashRegex[patternStart..patternEnd];
    string flags = slashRegex[patternEnd+1..$];
    return [pattern, flags];
}

/// Returns true if a Regex is valid and compiles
bool isValid(string pattern, string flags)
{
    try 
    {
        auto reg = regex(pattern, flags); // @suppress(dscanner.suspicious.unmodified)
        return true;
    }
    catch(RegexException rex)
    {
        return false;
    }
}
