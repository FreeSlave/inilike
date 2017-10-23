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
 * Read ini-like file entries via the set of callbacks.
 * Params:
 *  reader = $(D IniLikeReader) object as returned by $(D inilike.range.iniLikeReader) or similar function.
 *  onLeadingComment = Delegate to call after leading comment (i.e. the one before any group) is read. The parameter is either comment of empty line.
 *  onGroup = Delegate to call after group header is read. The parameter is group name (without brackets). Must return $(D ActionOnGroup).
 *  onKeyValue = Delegate to call after key-value entry is read and parsed. Parameters are key, value and group name.
 *  onCommentInGroup = Delegate to call after comment or empty line is read inside group section. The parameter is either comment of empty line.
 *  fileName = Optional file name parameter to use in thrown exceptions.
 * Throws:
 *  $(D inilike.exception.IniLikeReadException) if error occured while parsing. Any exception thrown by callbacks will be transformed to $(D inilike.exception.IniLikeReadException).
 */
void readIniLike(IniLikeReader)(IniLikeReader reader, scope void delegate(string) onLeadingComment, scope ActionOnGroup delegate(string) onGroup,
        scope void delegate(string, string, string) onKeyValue, scope void delegate(string, string) onCommentInGroup, string fileName = null
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

            auto actionOnGroup = onGroup(groupName);
            final switch(actionOnGroup)
            {
                case ActionOnGroup.stopAfter:
                case ActionOnGroup.proceed:
                {
                    foreach(line; g.byEntry)
                    {
                        lineNumber++;

                        if (line.isComment || line.strip.empty) {
                            onCommentInGroup(line, groupName);
                        } else {
                            const t = parseKeyValue(line);

                            string key = t.key.stripRight;
                            string value = t.value.stripLeft;

                            if (key.length == 0 && value.length == 0) {
                                throw new IniLikeException("Expected comment, empty line or key value inside group");
                            } else {
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
