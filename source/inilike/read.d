/**
 * Reading ini-like files without usage of $(D inilike.file.IniLikeFile) class.
 * Authors:
 *  $(LINK2 https://github.com/FreeSlave, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2017
 * License:
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also:
 *  $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/index.html, Desktop Entry Specification)
 */

module inilike.read;
public import inilike.range;
public import inilike.exception;
import inilike.common;

/// What to do when encounter some group name in onGroup callback of $(D readIniLike).
enum ActionOnGroup {
    skip, /// Skip this group entries, don't do any processing.
    proceed, /// Process the grouo entries as usual.
    stopAfter, /// Stop after processing this group (don't parse next groups)
}

/**
 * Read ini-like file entries via the set of callbacks. Callbacks can be null, but basic format validation is still run in this case.
 * Params:
 *  reader = $(D inilike.range.IniLikeReader) object as returned by $(D inilike.range.iniLikeRangeReader) or similar function.
 *  onLeadingComment = Delegate to call after leading comment (i.e. the one before any group) is read. The parameter is either comment of empty line.
 *  onGroup = Delegate to call after group header is read. The parameter is group name (without brackets). Must return $(D ActionOnGroup). Providing the null callback is equal to providing the callback that always returns $(D ActionOnGroup.skip).
 *  onKeyValue = Delegate to call after key-value entry is read and parsed. Parameters are key, value and the current group name. It's recommended to throw $(D inilike.exceptions.IniLikeEntryException) from this function in case if the key-value pair is invalid.
 *  onCommentInGroup = Delegate to call after comment or empty line is read inside group section. The first parameter is either comment or empty line. The second parameter is the current group name.
 *  fileName = Optional file name parameter to use in thrown exceptions.
 * Throws:
 *  $(D inilike.exception.IniLikeReadException) if error occured while parsing. Any exception thrown by callbacks will be transformed to $(D inilike.exception.IniLikeReadException).
 */
void readIniLike(IniLikeReader)(IniLikeReader reader, scope void delegate(string) onLeadingComment = null, scope ActionOnGroup delegate(string) onGroup = null,
        scope void delegate(string, string, string) onKeyValue = null, scope void delegate(string, string) onCommentInGroup = null, string fileName = null
) {
    size_t lineNumber = 0;

    version(DigitalMars) {
        static void foo(size_t ) {}
    }

    try {
        foreach(line; reader.byLeadingLines)
        {
            lineNumber++;
            if (line.isComment || line.strip.empty) {
                if (onLeadingComment !is null)
                    onLeadingComment(line);
            } else {
                throw new IniLikeException("Expected comment or empty line before any group");
            }
        }

        foreach(g; reader.byGroup)
        {
            lineNumber++;
            string groupName = g.groupName;

            version(DigitalMars) {
                foo(lineNumber); //fix dmd codgen bug with -O
            }

            auto actionOnGroup = onGroup is null ? ActionOnGroup.skip : onGroup(groupName);
            final switch(actionOnGroup)
            {
                case ActionOnGroup.stopAfter:
                case ActionOnGroup.proceed:
                {
                    foreach(line; g.byEntry)
                    {
                        lineNumber++;

                        if (line.isComment || line.strip.empty) {
                            if (onCommentInGroup !is null)
                                onCommentInGroup(line, groupName);
                        } else {
                            const t = parseKeyValue(line);

                            string key = t.key.stripRight;
                            string value = t.value.stripLeft;

                            if (key.length == 0 && value.length == 0) {
                                throw new IniLikeException("Expected comment, empty line or key value inside group");
                            } else {
                                if (onKeyValue !is null)
                                    onKeyValue(key, value, groupName);
                            }
                        }
                    }
                    if (actionOnGroup == ActionOnGroup.stopAfter) {
                        return;
                    }
                }
                break;
                case ActionOnGroup.skip:
                {
                    foreach(line; g.byEntry) {}
                }
                break;
            }
        }
    }
    catch(IniLikeEntryException e) {
        throw new IniLikeReadException(e.msg, lineNumber, fileName, e, e.file, e.line, e.next);
    }
    catch (Exception e) {
        throw new IniLikeReadException(e.msg, lineNumber, fileName, null, e.file, e.line, e.next);
    }
}

///
unittest
{
    string contents =
`# Comment
[ToSkip]
KeyInSkippedGroup=Value
[ToProceed]
KeyInNormalGroup=Value2
# Comment2
[ToStopAfter]
KeyInStopAfterGroup=Value3
# Comment3
[NeverGetThere]
KeyNeverGetThere=Value4
# Comment4`;
    auto onLeadingComment = delegate void(string line) {
        assert(line == "# Comment");
    };
    auto onGroup = delegate ActionOnGroup(string groupName) {
        if (groupName == "ToSkip") {
            return ActionOnGroup.skip;
        } else if (groupName == "ToProceed") {
            return ActionOnGroup.proceed;
        } else if (groupName == "ToStopAfter") {
            return ActionOnGroup.stopAfter;
        } else assert(false);
    };
    auto onKeyValue = delegate void(string key, string value, string groupName) {
        assert((groupName == "ToProceed" && key == "KeyInNormalGroup" && value == "Value2") ||
            (groupName == "ToStopAfter" && key == "KeyInStopAfterGroup" && value == "Value3"));
    };
    auto onCommentInGroup = delegate void(string line, string groupName) {
        assert((groupName == "ToProceed" && line == "# Comment2") || (groupName == "ToStopAfter" && line == "# Comment3"));
    };
    readIniLike(iniLikeStringReader(contents), onLeadingComment, onGroup, onKeyValue, onCommentInGroup);
    readIniLike(iniLikeStringReader(contents));

    import std.exception : assertThrown;
    contents =
`Not a comment
[Group name]
Key=Value`;
    assertThrown!IniLikeReadException(readIniLike(iniLikeStringReader(contents)));
}
