# Inilike

Inilike is D library for parsing **.ini-like** files used in Freedesktop systems in various places (.desktop files, icon themes, mimeapps.list, mimeinfo.cache, trashcan files on freedesktop, etc.)

[![Build Status](https://travis-ci.org/MyLittleRobo/inilike.svg?branch=master)](https://travis-ci.org/MyLittleRobo/inilike?branch=master) [![Coverage Status](https://coveralls.io/repos/MyLittleRobo/inilike/badge.svg?branch=master&service=github)](https://coveralls.io/github/MyLittleRobo/inilike?branch=master)

[Online documentation](https://mylittlerobo.github.io/d-freedesktop/docs/inilike.html)

Note: the original purpose of this library is to serve as dependency for my other projects, e.g. [desktopfile](https://github.com/MyLittleRobo/desktopfile) and [icontheme](https://github.com/MyLittleRobo/icontheme). It may be not suitable to save configuration files using this library. You have been warned.

## Generating documentation

Ddoc:

    dub build --build=docs

Ddox:

    dub build --build=ddox

## Running tests

    dub test

## Format

Freedesktop specifications use the format which is sometimes referred to as **.ini-like** because it's very similiar to **INI** used in MS Windows with small differences:

1. Comments start with '#', not ';'.
2. Each comment is always placed on its own line. Key-value can't be mixed with a comment on the same line.

Example:

    # Comment
    [Group name]
    Key=Value
    # Comment inside group
    AnotherKey=Value

    [Another group]
    Key=English value
    Key[fr_FR]=Francais value

## Localized values lookup

The localized value is the value associated with the localized key. Localized keys look like this:

    keyname[locale]

where **locale** is the [POSIX locale](http://en.wikipedia.org/wiki/Locale) with the charset part dropped.

Inilike library has support for lookup of localized values, using the algorithm described in [Desktop Entry Specification](http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s04.html).

## Subclassing IniLikeFile

IniLikeFile is the base class for file of ini-like format. To change its functionality (validation and other behavior) it needs to be subclassed. 
See [example](source/inilike/package.d) in unittests that shows which functions can be overridden.

