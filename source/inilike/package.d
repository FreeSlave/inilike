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
 *  Roman Chistokhodov, 2015-2016
 * License: 
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also: 
 *  $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/index.html, Desktop Entry Specification)
 */

module inilike;

public import inilike.common;
public import inilike.range;
public import inilike.file;

unittest
{
    import std.exception;
    
    final class DesktopEntry : IniLikeGroup
    {
        this() {
            super("Desktop Entry");
        }
    protected:
        @trusted override void validateKeyValue(string key, string value) const {
            if (!isValidKey(key)) {
                throw new IniLikeEntryException("key is invalid", name(), key, value);
            }
        }
    }

    final class DesktopFile : IniLikeFile
    {
        //Flags to manage .ini like file reading
        enum ReadOptions
        {
            noOptions = 0,              // Read all groups, skip comments and empty lines, stop on any error.
            preserveComments = 2,       // Preserve comments and empty lines. Use this when you want to keep them across writing.
            ignoreGroupDuplicates = 4,  // Ignore group duplicates. The first found will be used.
            ignoreInvalidKeys = 8,      // Skip invalid keys during parsing.
            ignoreKeyDuplicates = 16,   // Ignore key duplicates. The first found will be used.
            ignoreUnknownGroups = 32,   // Don't throw on unknown groups. Still save them.
            skipUnknownGroups = 64,     // Don't save unknown groups.
            skipExtensionGroups = 128   // Skip groups started with X-
        }
        
        @trusted this(IniLikeReader)(IniLikeReader reader, ReadOptions options = ReadOptions.noOptions)
        {
            _options = options;
            super(reader);
            enforce(_desktopEntry !is null, new IniLikeReadException("No \"Desktop Entry\" group", 0));
            _options = ReadOptions.noOptions;
        }
        
        @safe override bool removeGroup(string groupName) nothrow {
            if (groupName == "Desktop Entry") {
                return false;
            }
            return super.removeGroup(groupName);
        }
        
        @trusted override void addLeadingComment(string line) nothrow {
            if (_options & ReadOptions.preserveComments) {
                super.addLeadingComment(line);
            }
        }
        
    protected:
        @trusted override void addCommentForGroup(string comment, IniLikeGroup currentGroup, string groupName)
        {
            if (currentGroup && (_options & ReadOptions.preserveComments)) {
                currentGroup.addComment(comment);
            }
        }
        
        @trusted override void addKeyValueForGroup(string key, string value, IniLikeGroup currentGroup, string groupName)
        {
            if (currentGroup) {
                if (!isValidKey(key) && (_options & ReadOptions.ignoreInvalidKeys)) {
                    return;
                }
                if (currentGroup.contains(key)) {
                    if (_options & ReadOptions.ignoreKeyDuplicates) {
                        return;
                    } else {
                        throw new Exception("key already exists");
                    }
                }
                currentGroup[key] = value;
            }
        }
        
        @trusted override IniLikeGroup createGroup(string groupName)
        {
            if (group(groupName) !is null) {
                if (_options & ReadOptions.ignoreGroupDuplicates) {
                    return null;
                } else {
                    throw new Exception("group already exists");
                }
            }
            
            if (groupName == "Desktop Entry") {
                _desktopEntry = new DesktopEntry();
                return _desktopEntry;
            } else if (groupName.startsWith("X-")) {
                if (_options & ReadOptions.skipExtensionGroups) {
                    return null;
                }
                return createEmptyGroup(groupName);
            } else {
                if (_options & ReadOptions.ignoreUnknownGroups) {
                    if (_options & ReadOptions.skipUnknownGroups) {
                        return null;
                    } else {
                        return createEmptyGroup(groupName);
                    }
                } else {
                    throw new Exception("Unknown group");
                }
            }
        }
        
        inout(DesktopEntry) desktopEntry() inout {
            return _desktopEntry;
        }
        
    private:
        DesktopEntry _desktopEntry;
        ReadOptions _options;
    }
    
    string contents = 
`# First comment
[Desktop Entry]
Key=Value
# Comment in group`;

    auto df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.noOptions);
    assert(!df.removeGroup("Desktop Entry"));
    assert(!df.removeGroup("NonExistent"));
    assert(df.group("Desktop Entry") !is null);
    assert(df.desktopEntry() !is null);
    assert(df.leadingComments().empty);
    assert(equal(df.desktopEntry().byIniLine(), [IniLikeLine.fromKeyValue("Key", "Value")]));
    
    df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.preserveComments);
    assert(equal(df.leadingComments(), ["# First comment"]));
    assert(equal(df.desktopEntry().byIniLine(), [IniLikeLine.fromKeyValue("Key", "Value"), IniLikeLine.fromComment("# Comment in group")]));
    
    contents = 
`[X-SomeGroup]
Key=Value`;

    auto thrown = collectException!IniLikeReadException(new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.noOptions));
    assert(thrown !is null);
    assert(thrown.lineNumber == 0);
    
    contents = 
`[Desktop Entry]
Valid=Key
$=Invalid`;

    thrown = collectException!IniLikeReadException(new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.noOptions));
    assert(thrown !is null);
    assert(thrown.entryException !is null);
    assert(thrown.entryException.key == "$");
    assert(thrown.entryException.value == "Invalid");
    
    assertNotThrown(new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.ignoreInvalidKeys));
    
    contents = 
`[Desktop Entry]
Key=Value1
Key=Value2`;

    assertThrown(new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.noOptions));
    assertNotThrown(df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.ignoreKeyDuplicates));
    assert(df.desktopEntry().value("Key") == "Value1");
    
    contents = 
`[Desktop Entry]
Name=Name
[Unknown]
Key=Value`;

    assertThrown(new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.noOptions));
    assertNotThrown(df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.ignoreUnknownGroups));
    assert(df.group("Unknown") !is null);
    
    df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.ignoreUnknownGroups|DesktopFile.ReadOptions.skipUnknownGroups);
    assert(df.group("Unknown") is null);
    
    contents = 
`[Desktop Entry]
Name=Name1
[Desktop Entry]
Name=Name2`;
    
    assertThrown(new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.noOptions));
    assertNotThrown(df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.ignoreGroupDuplicates));
    
    assert(df.desktopEntry().value("Name") == "Name1");
    
    contents = 
`[Desktop Entry]
Name=Name1
[X-Extension]
Name=Name2`;

    df = new DesktopFile(iniLikeStringReader(contents), DesktopFile.ReadOptions.skipExtensionGroups);
    assert(df.group("X-Extension") is null);
}
