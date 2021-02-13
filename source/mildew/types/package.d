/**
This module is for convenient use by the scripting language internals. Host applications should
only import func.d, object.d, and any.d most of the time.
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
module mildew.types;

public import mildew.types.any;
public import mildew.types.array;
public import mildew.types.func;
public import mildew.types.object;
public import mildew.types.string;