/**
 * Reading and writing ini-like files used in some Unix systems and Freedesktop specifications.
 * ini-like is informal name for the file format that look like this:
 * ---
# Comment
[Group name]
Key=Value
# Comment inside group
AnotherKey=Value

[Another group]
Key2=Value

 * ---
 * Authors: 
 *  $(LINK2 https://github.com/MyLittleRobo, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2015
 * License: 
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also: 
 *  $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/index.html, Desktop Entry Specification)
 */

module inilike;

public import inilike.common;
public import inilike.range;

