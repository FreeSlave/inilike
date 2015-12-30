/**
 * Parsing contents of ini-like files via range-based interface.
 * Authors: 
 *  $(LINK2 https://github.com/MyLittleRobo, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2015
 * License: 
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also: 
 *  $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/index.html, Desktop Entry Specification)
 */

module inilike.range;

import inilike.common;


/**
 * Object for iterating through ini-like file entries.
 */
struct IniLikeReader(Range) if (isInputRange!Range && isSomeString!(ElementType!Range))
{
    this(Range range)
    {
        _range = range;
    }
    
    /**
     * Iterate through lines before any group header. It does not check if all lines are comments or empty lines.
     */
    auto byFirstLines()
    {
        return _range.until!(isGroupHeader);
    }
    
    /**
     * Iterate thorugh groups of ini-like file.
     */
    auto byGroup()
    {   
        static struct ByGroup
        {
            static struct Group
            {
                this(Range range, string originalLine)
                {
                    _range = range;
                    _originalLine = originalLine;
                }
                
                string name() {
                    return parseGroupHeader(_originalLine);
                }
                
                string originalLine() {
                    return _originalLine;
                }
                
                auto byEntry()
                {
                    return _range.until!(isGroupHeader);
                }
                
            private:
                string _originalLine;
                Range _range;
            }
            
            this(Range range)
            {
                _range = range.find!(isGroupHeader);
                string line;
                if (!_range.empty) {
                    line = _range.front;
                    _range.popFront();
                }
                _currentGroup = Group(_range, line);
            }
            
            auto front()
            {
                return _currentGroup;
            }
            
            bool empty()
            {
                return _currentGroup.name.empty;
            }
            
            void popFront()
            {
                _range = _range.find!(isGroupHeader);
                string line;
                if (!_range.empty) {
                    line = _range.front;
                    _range.popFront();
                }
                _currentGroup = Group(_range, line);
            }
        private:
            Group _currentGroup;
            Range _range;
        }
        
        return ByGroup(_range.find!(isGroupHeader));
    }
    
private:
    Range _range;
}

/**
 * Convenient function for creation of IniLikeReader instance.
 * Params:
 *  range = input range of strings (strings must be without trailing new line characters)
 * Returns: IniLikeReader for given range.
 * See_Also: iniLikeFileReader, iniLikeStringReader
 */
auto iniLikeRangeReader(Range)(Range range)
{
    return IniLikeReader!Range(range);
}

/**
 * Convenient function for reading ini-like contents from the file.
 * Throws: $(B ErrnoException) if file could not be opened.
 * Note: This function uses byLineCopy internally. Fallbacks to byLine on older compilers.
 * See_Also: iniLikeRangeReader, iniLikeStringReader
 */
@trusted auto iniLikeFileReader(string fileName)
{
    import std.stdio;
    static if( __VERSION__ < 2067 ) {
        return iniLikeRangeReader(File(fileName, "r").byLine().map!(s => s.idup));
    } else {
        return iniLikeRangeReader(File(fileName, "r").byLineCopy());
    }
}

/**
 * Convenient function for reading ini-like contents from string.
 * Note: on frontends < 2.067 it uses splitLines thereby allocates strings.
 * See_Also: iniLikeRangeReader, iniLikeFileReader
 */
@trusted auto iniLikeStringReader(string contents)
{
    static if( __VERSION__ < 2067 ) {
        return iniLikeRangeReader(contents.splitLines());
    } else {
        return iniLikeRangeReader(contents.lineSplitter());
    }
}

///
unittest
{
    string contents = 
`First comment
Second comment
[First group]
KeyValue1
KeyValue2
[Second group]
KeyValue3
KeyValue4
[Empty group]
[Third group]
KeyValue5
KeyValue6`;
    auto r = iniLikeStringReader(contents);
    
    auto byFirstLines = r.byFirstLines;
    
    assert(byFirstLines.front == "First comment");
    assert(byFirstLines.equal(["First comment", "Second comment"]));
    
    auto byGroup = r.byGroup;
    
    assert(byGroup.front.name == "First group");
    assert(byGroup.front.originalLine == "[First group]");
    //assert(byGroup.map!(g => g.name).equal(["First group", "Second group", "Empty group", "Third group"]));
    
    
    assert(byGroup.front.byEntry.front == "KeyValue1");
    assert(byGroup.front.byEntry.equal(["KeyValue1", "KeyValue2"]));
    byGroup.popFront();
    assert(byGroup.front.name == "Second group");
    byGroup.popFront();
    assert(byGroup.front.name == "Empty group");
    assert(byGroup.front.byEntry.empty);
    byGroup.popFront();
    assert(byGroup.front.name == "Third group");
    byGroup.popFront();
    assert(byGroup.empty);
}

