/**
 * Class representation of ini-like file.
 * Authors: 
 *  $(LINK2 https://github.com/MyLittleRobo, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2015-2016
 * License: 
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also: 
 *  $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/index.html, Desktop Entry Specification)
 */

module inilike.file;

private import std.exception;

import inilike.common;
public import inilike.range;

private import std.typecons : Rebindable, rebindable;

private @trusted string makeComment(string line) pure nothrow
{
    if (line.length && line[$-1] == '\n') {
        line = line[0..$-1];
    }
    if (!line.isComment && line.length) {
        line = '#' ~ line;
    }
    line = line.replace("\n", " ");
    return line;
}

/**
 * Container used internally by $(D IniLikeFile) and $(D IniLikeGroup).
 * Technically this is list with optional value access by key.
 */
struct ListMap(K,V, size_t chunkSize = 32)
{       
    ///
    @disable this(this);
    
    /**
     * Insert key-value pair to the front of list.
     * Returns: Inserted node.
     */
    Node* insertFront(K key, V value) {
        Node* newNode = givePlace(key, value);
        putToFront(newNode);
        return newNode;
    }
    
    /**
     * Insert key-value pair to the back of list.
     * Returns: Inserted node.
     */
    Node* insertBack(K key, V value) {
        Node* newNode = givePlace(key, value);
        putToBack(newNode);
        return newNode;
    }
    
    /**
     * Insert key-value pair before some node in the list.
     * Returns: Inserted node.
     */
    Node* insertBefore(Node* node, K key, V value) {
        Node* newNode = givePlace(key, value);
        putBefore(node, newNode);
        return newNode;
    }
    
    /**
     * Insert key-value pair after some node in the list.
     * Returns: Inserted node.
     */
    Node* insertAfter(Node* node, K key, V value) {
        Node* newNode = givePlace(key, value);
        putAfter(node, newNode);
        return newNode;
    }
    
    /**
     * Add value at the start of list.
     * Returns: Inserted node.
     */
    Node* prepend(V value) {
        Node* newNode = givePlace(value);
        putToFront(newNode);
        return newNode;
    }
    
    /**
     * Add value at the end of list.
     * Returns: Inserted node.
     */
    Node* append(V value) {
        Node* newNode = givePlace(value);
        putToBack(newNode);
        return newNode;
    }
    
    /**
     * Add value before some node in the list.
     * Returns: Inserted node.
     */
    Node* addBefore(Node* node, V value) {
        Node* newNode = givePlace(value);
        putBefore(node, newNode);
        return newNode;
    }
    
    /**
     * Add value after some node in the list.
     * Returns: Inserted node.
     */
    Node* addAfter(Node* node, V value) {
        Node* newNode = givePlace(value);
        putAfter(node, newNode);
        return newNode;
    }
    
    /**
     * Move node to the front of list.
     */
    void moveToFront(Node* toMove)
    {
        pullOut(toMove);
        putToFront(toMove);
    }
    
    /**
     * Move node to the back of list.
     */
    void moveToBack(Node* toMove)
    {
        pullOut(toMove);
        putToBack(toMove);
    }
    
    /**
     * Move node to the location before other node.
     */
    void moveBefore(Node* node, Node* toMove) {
        pullOut(toMove);
        putBefore(node, toMove);
    }
    
    /**
     * Move node to the location after other node.
     */
    void moveAfter(Node* node, Node* toMove) {
        pullOut(toMove);
        putAfter(node, toMove);
    }
    
    /**
     * Remove node from list. It also becomes unaccessible via key lookup.
     */
    void remove(Node* toRemove)
    {
        pullOut(toRemove);
        
        if (toRemove.hasKey()) {
            _dict.remove(toRemove.key);
        }
        
        if (_lastEmpty) {
            _lastEmpty.next = toRemove;
        }
        toRemove.prev = _lastEmpty;
        _lastEmpty = toRemove;
    }
    
    /**
     * Remove value by key.
     * Returns: true if node with such key was found and removed. False otherwise.
     */
    bool remove(K key) {
        Node** toRemove = key in _dict;
        if (toRemove) {
            remove(*toRemove);
            return true;
        }
        return false;
    }
    
    /**
     * Remove the first node.
     */
    void removeFront() {
        remove(_head);
    }
    
    /**
     * Remove the last node.
     */
    void removeBack() {
        remove(_tail);
    }
    
    /**
     * Get list node by key.
     * Returns: Found Node or null if container does not have node associated with key.
     */
    inout(Node)* getNode(K key) inout {
        auto toReturn = key in _dict;
        if (toReturn) {
            return *toReturn;
        }
        return null;
    }
    
    private static struct ByNode(NodeType)
    {
    private:
        NodeType* _begin;
        NodeType* _end;
        
    public:
        bool empty() const {
            return _begin is null || _end is null || _begin.prev is _end || _end.next is _begin;
        }
        
        auto front() {
            return _begin;
        }
        
        auto back() {
            return _end;
        }
        
        void popFront() {
            _begin = _begin.next;
        }
        
        void popBack() {
            _end = _end.prev;
        }
        
        @property auto save() {
            return this;
        }
    }
    
    /**
     * Iterate over list nodes.
     * See_Also: byEntry
     */
    auto byNode() 
    {
        return ByNode!Node(_head, _tail);
    }
    
    ///ditto
    auto byNode() const
    {
        return ByNode!(const(Node))(_head, _tail);
    }
    
    /**
     * Iterate over nodes mapped to Entry elements (useful for testing).
     */
    auto byEntry() const {
        import std.algorithm : map;
        return byNode().map!(node => node.toEntry());
    }
    
    /**
     * Represenation of list node.
     */
    static struct Node {
    private:
        K _key;
        V _value;
        bool _hasKey;
        Node* _prev;
        Node* _next;
        
        this(K key, V value) {
            _key = key;
            _value = value;
            _hasKey = true;
        }
        
        this(V value) {
            _value = value;
            _hasKey = false;
        }
        
        void prev(Node* newPrev) {
            _prev = newPrev;
        }
        
        void next(Node* newNext) {
            _next = newNext;
        }
        
    public:
        /**
         * Get stored value.
         */
        inout(V) value() inout {
            return _value;
        }
        
        /**
         * Set stored value.
         */
        void value(V newValue) {
            _value = newValue;
        }
        
        /**
         * Tell whether this node is a key-value node.
         */
        bool hasKey() const {
            return _hasKey;
        }
        
        /**
         * Key in key-value node.
         */
        auto key() const {
            return _key;
        }
        
        /**
         * Access previous node in the list.
         */
        inout(Node)* prev() inout {
            return _prev;
        }
        
        /**
         * Access next node in the list.
         */
        inout(Node)* next() inout {
            return _next;
        }
        
        ///
        auto toEntry() const {
            static if (is(V == class)) {
                alias Rebindable!(const(V)) T;
                if (hasKey()) {
                    return Entry!T(_key, rebindable(_value));
                } else {
                    return Entry!T(rebindable(_value));
                }
                
            } else {
                alias V T;
                
                if (hasKey()) {
                    return Entry!T(_key, _value);
                } else {
                    return Entry!T(_value);
                }
            }
            
            
        }
    }
    
    /// Mapping of Node to structure.
    static struct Entry(T = V)
    {
    private:
        K _key;
        T _value;
        bool _hasKey;
        
    public:
        ///
        this(T value) {
            _value = value;
            _hasKey = false;
        }
        
        ///
        this(K key, T value) {
            _key = key;
            _value = value;
            _hasKey = true;
        }
        
        ///
        auto value() inout {
            return _value;
        }
        
        ///
        auto key() const {
            return _key;
        }
        
        ///
        bool hasKey() const {
            return _hasKey;
        }
    }
    
private:
    void putToFront(Node* toPut) 
    in {
        assert(toPut !is null);
    } 
    body {
        if (_head) {
            _head.prev = toPut;
            toPut.next = _head;
            _head = toPut;
        } else {
            _head = toPut;
            _tail = toPut;
        }
    }
    
    void putToBack(Node* toPut)
    in {
        assert(toPut !is null);
    }
    body {
        if (_tail) {
            _tail.next = toPut;
            toPut.prev = _tail;
            _tail = toPut;
        } else {
            _tail = toPut;
            _head = toPut;
        }
    }
    
    void putBefore(Node* node, Node* toPut)
    in {
        assert(toPut !is null);
        assert(node !is null);
    } 
    body {
        toPut.prev = node.prev;
        if (toPut.prev) {
            toPut.prev.next = toPut;
        }
        toPut.next = node;
        node.prev = toPut;
        
        if (node is _head) {
            _head = toPut;
        }
    }
    
    void putAfter(Node* node, Node* toPut) 
    in {
        assert(toPut !is null);
        assert(node !is null);
    }
    body {
        toPut.next = node.next;
        if (toPut.next) {
            toPut.next.prev = toPut;
        }
        toPut.prev = node;
        node.next = toPut;
        
        if (node is _tail) {
            _tail = toPut;
        }
    }
    
    void pullOut(Node* node) 
    in {
        assert(node !is null);
    }
    body {
        if (node.next) {
            node.next.prev = node.prev;
        }
        if (node.prev) {
            node.prev.next = node.next;
        }
        
        if (node is _head) {
            _head = node.next;
        }
        if (node is _tail) {
            _tail = node.prev;
        }
        
        node.next = null;
        node.prev = null;
    }
    
    Node* givePlace(K key, V value) {
        auto newNode = Node(key, value);
        return givePlace(newNode);
    }
    
    Node* givePlace(V value) {
        auto newNode = Node(value);
        return givePlace(newNode);
    }
    
    Node* givePlace(ref Node node) {
        Node* toReturn;
        if (_lastEmpty is null) {
            if (_storageSize < _storage.length) {
                toReturn = &_storage[_storageSize];
            } else {
                size_t storageIndex = (_storageSize - chunkSize) / chunkSize;
                if (storageIndex >= _additonalStorages.length) {
                    _additonalStorages ~= (Node[chunkSize]).init;
                }
                
                size_t index = (_storageSize - chunkSize) % chunkSize;
                toReturn = &_additonalStorages[storageIndex][index];
            }
            
            _storageSize++;
        } else {
            toReturn = _lastEmpty;
            _lastEmpty = _lastEmpty.prev;
            if (_lastEmpty) {
                _lastEmpty.next = null;
            }
            toReturn.next = null;
            toReturn.prev = null;
        }
        
        toReturn._hasKey = node._hasKey;
        toReturn._key = node._key;
        toReturn._value = node._value;
        
        if (toReturn.hasKey()) {
            _dict[toReturn.key] = toReturn;
        }
        return toReturn;
    }
    
    Node[chunkSize] _storage;
    Node[chunkSize][] _additonalStorages;
    size_t _storageSize;
    
    Node* _tail;
    Node* _head;
    Node* _lastEmpty;
    Node*[K] _dict;
}

unittest
{
    import std.range : isBidirectionalRange;
    ListMap!(string, string) listMap;
    static assert(isBidirectionalRange!(typeof(listMap.byNode())));
}

unittest
{
    import std.algorithm : equal;
    import std.range : ElementType;
    
    alias ListMap!(string, string, 2) TestListMap;
    
    TestListMap listMap;
    alias typeof(listMap).Node Node;
    alias ElementType!(typeof(listMap.byEntry())) Entry;
    
    assert(listMap.byEntry().empty);
    assert(listMap.getNode("Nonexistent") is null);
    
    listMap.insertFront("Start", "Fast");
    assert(listMap.getNode("Start") !is null);
    assert(listMap.getNode("Start").key() == "Start");
    assert(listMap.getNode("Start").value() == "Fast");
    assert(listMap.getNode("Start").hasKey());
    assert(listMap.byEntry().equal([Entry("Start", "Fast")]));
    assert(listMap.remove("Start"));
    assert(listMap.byEntry().empty);
    assert(listMap.getNode("Start") is null);
    
    listMap.insertBack("Finish", "Bad");
    assert(listMap.byEntry().equal([Entry("Finish", "Bad")]));
    assert(listMap.getNode("Finish").value() == "Bad");
    
    listMap.insertFront("Begin", "Good");
    assert(listMap.byEntry().equal([Entry("Begin", "Good"), Entry("Finish", "Bad")]));
    assert(listMap.getNode("Begin").value() == "Good");
    
    listMap.insertFront("Start", "Slow");
    assert(listMap.byEntry().equal([Entry("Start", "Slow"), Entry("Begin", "Good"), Entry("Finish", "Bad")]));
    
    listMap.insertAfter(listMap.getNode("Begin"), "Middle", "Person");
    assert(listMap.getNode("Middle").value() == "Person");
    assert(listMap.byEntry().equal([Entry("Start", "Slow"), Entry("Begin", "Good"), Entry("Middle", "Person"), Entry("Finish", "Bad")]));
    
    listMap.insertBefore(listMap.getNode("Middle"), "Mean", "Man");
    assert(listMap.getNode("Mean").value() == "Man");
    assert(listMap.byEntry().equal([Entry("Start", "Slow"), Entry("Begin", "Good"), Entry("Mean", "Man"), Entry("Middle", "Person"), Entry("Finish", "Bad")]));
    
    assert(listMap.remove("Mean"));
    assert(listMap.remove("Middle"));
    
    assert(listMap.byEntry().equal([Entry("Start", "Slow"), Entry("Begin", "Good"), Entry("Finish", "Bad")]));
    
    listMap.insertFront("New", "Era");
    assert(listMap.byEntry().equal([Entry("New", "Era"), Entry("Start", "Slow"), Entry("Begin", "Good"), Entry("Finish", "Bad")]));
    
    listMap.insertBack("Old", "Epoch");
    assert(listMap.byEntry().equal([Entry("New", "Era"), Entry("Start", "Slow"), Entry("Begin", "Good"), Entry("Finish", "Bad"), Entry("Old", "Epoch")]));
    
    listMap.moveToBack(listMap.getNode("New"));
    assert(listMap.byEntry().equal([Entry("Start", "Slow"), Entry("Begin", "Good"), Entry("Finish", "Bad"), Entry("Old", "Epoch"), Entry("New", "Era")]));
    
    listMap.moveToFront(listMap.getNode("Begin"));
    assert(listMap.byEntry().equal([Entry("Begin", "Good"), Entry("Start", "Slow"), Entry("Finish", "Bad"), Entry("Old", "Epoch"), Entry("New", "Era")]));
    
    listMap.moveAfter(listMap.getNode("Finish"), listMap.getNode("Start"));
    assert(listMap.byEntry().equal([Entry("Begin", "Good"), Entry("Finish", "Bad"), Entry("Start", "Slow"), Entry("Old", "Epoch"), Entry("New", "Era")]));
    
    listMap.moveBefore(listMap.getNode("Finish"), listMap.getNode("Old"));
    assert(listMap.byEntry().equal([Entry("Begin", "Good"), Entry("Old", "Epoch"), Entry("Finish", "Bad"), Entry("Start", "Slow"), Entry("New", "Era")]));
    
    listMap.moveBefore(listMap.getNode("Begin"), listMap.getNode("Start"));
    assert(listMap.byEntry().equal([Entry("Start", "Slow"), Entry("Begin", "Good"), Entry("Old", "Epoch"), Entry("Finish", "Bad"), Entry("New", "Era")]));
    
    listMap.moveAfter(listMap.getNode("New"), listMap.getNode("Finish"));
    assert(listMap.byEntry().equal([Entry("Start", "Slow"), Entry("Begin", "Good"), Entry("Old", "Epoch"), Entry("New", "Era"), Entry("Finish", "Bad")]));
    
    listMap.getNode("Begin").value = "Evil";
    assert(listMap.getNode("Begin").value() == "Evil");
    
    listMap.remove("Begin");
    assert(listMap.byEntry().equal([Entry("Start", "Slow"), Entry("Old", "Epoch"), Entry("New", "Era"), Entry("Finish", "Bad")]));
    listMap.remove("Old");
    listMap.remove("New");
    assert(!listMap.remove("Begin"));
    
    Node* shebang = listMap.prepend("Shebang");
    Node* endOfStory = listMap.append("End of story");
    
    assert(listMap.byEntry().equal([Entry("Shebang"), Entry("Start", "Slow"), Entry("Finish", "Bad"), Entry("End of story")]));
    
    Node* mid = listMap.addAfter(listMap.getNode("Start"), "Mid");
    Node* average = listMap.addBefore(listMap.getNode("Finish"), "Average");
    assert(listMap.byEntry().equal([Entry("Shebang"), Entry("Start", "Slow"), Entry("Mid"), Entry("Average"), Entry("Finish", "Bad"), Entry("End of story")]));
    
    listMap.remove(shebang);
    assert(listMap.byEntry().equal([Entry("Start", "Slow"), Entry("Mid"), Entry("Average"), Entry("Finish", "Bad"), Entry("End of story")]));
    
    listMap.remove(endOfStory);
    assert(listMap.byEntry().equal([Entry("Start", "Slow"), Entry("Mid"), Entry("Average"), Entry("Finish", "Bad")]));
    
    listMap.insertAfter(mid, "Center", "Universe");
    listMap.insertBefore(average, "Focus", "Cosmos");
    assert(listMap.byEntry().equal([Entry("Start", "Slow"), Entry("Mid"), Entry("Center", "Universe"), Entry("Focus", "Cosmos"), Entry("Average"), Entry("Finish", "Bad")]));
    
    listMap.removeFront();
    assert(listMap.byEntry().equal([Entry("Mid"), Entry("Center", "Universe"), Entry("Focus", "Cosmos"), Entry("Average"), Entry("Finish", "Bad")]));
    listMap.removeBack();
    
    assert(listMap.byEntry().equal([Entry("Mid"), Entry("Center", "Universe"), Entry("Focus", "Cosmos"), Entry("Average")]));
    
    assert(listMap.byEntry().retro.equal([Entry("Average"), Entry("Focus", "Cosmos"), Entry("Center", "Universe"), Entry("Mid")]));
    
    auto byEntry = listMap.byEntry();
    Entry entry = byEntry.front;
    assert(entry.value == "Mid");
    assert(!entry.hasKey());
    
    byEntry.popFront();
    assert(byEntry.equal([Entry("Center", "Universe"), Entry("Focus", "Cosmos"), Entry("Average")]));
    byEntry.popBack();
    assert(byEntry.equal([Entry("Center", "Universe"), Entry("Focus", "Cosmos")]));
    
    entry = byEntry.back;
    assert(entry.key == "Focus");
    assert(entry.value == "Cosmos");
    assert(entry.hasKey());
    
    auto saved = byEntry.save;
    
    byEntry.popFront();
    assert(byEntry.equal([Entry("Focus", "Cosmos")]));
    byEntry.popBack();
    assert(byEntry.empty);
    
    assert(saved.equal([Entry("Center", "Universe"), Entry("Focus", "Cosmos")]));
    saved.popBack();
    assert(saved.equal([Entry("Center", "Universe")]));
    saved.popFront();
    assert(saved.empty);
    
    static void checkConst(ref const TestListMap listMap)
    {
        assert(listMap.byEntry().equal([Entry("Mid"), Entry("Center", "Universe"), Entry("Focus", "Cosmos"), Entry("Average")]));
    }
    checkConst(listMap);
}

/**
 * Line in group.
 */
struct IniLikeLine
{
    /**
     * Type of line.
     */
    enum Type
    {
        None = 0,   /// deleted or invalid line
        Comment = 1, /// a comment or empty line
        KeyValue = 2 /// key-value pair
    }
    
    /**
     * Contruct from comment.
     */
    @nogc @safe static IniLikeLine fromComment(string comment) nothrow pure {
        return IniLikeLine(comment, null, Type.Comment);
    }
    
    /**
     * Construct from key and value.
     */
    @nogc @safe static IniLikeLine fromKeyValue(string key, string value) nothrow pure {
        return IniLikeLine(key, value, Type.KeyValue);
    }
    
    /**
     * Get comment.
     * Returns: Comment or empty string if type is not Type.Comment.
     */
    @nogc @safe string comment() const nothrow pure {
        return _type == Type.Comment ? _first : null;
    }
    
    /**
     * Get key.
     * Returns: Key or empty string if type is not Type.KeyValue
     */
    @nogc @safe string key() const nothrow pure {
        return _type == Type.KeyValue ? _first : null;
    }
    
    /**
     * Get value.
     * Returns: Value or empty string if type is not Type.KeyValue
     */
    @nogc @safe string value() const nothrow pure {
        return _type == Type.KeyValue ? _second : null;
    }
    
    @nogc @safe string value(string newValue) nothrow pure {
        return _second = newValue;
    }
    
    /**
     * Get type of line.
     */
    @nogc @safe Type type() const nothrow pure {
        return _type;
    }
private:
    string _first;
    string _second;
    Type _type = Type.None;
}


/**
 * This class represents the group (section) in the ini-like file. 
 * You can create and use instances of this class only in the context of $(D IniLikeFile) or its derivatives.
 * Note: Keys are case-sensitive.
 */
class IniLikeGroup
{
public:
    /**
     * Create instance on IniLikeGroup and set its name to groupName.
     */
    protected @nogc @safe this(string groupName) nothrow {
        _name = groupName;
    }
    
    /**
     * Returns: The value associated with the key.
     * Note: The value is not unescaped automatically.
     * Prerequisites: Accessed key must exist.
     * See_Also: $(D value), $(D readEntry)
     */
    @nogc @safe final string opIndex(string key) const nothrow pure {
        return _listMap.getNode(key).value.value;
    }
    
    private @safe final string setKeyValueImpl(string key, string value) 
    in {
        assert(!value.needEscaping);
    }
    body {
        import std.stdio;
        auto node = _listMap.getNode(key);
        if (node) {
            node.value = IniLikeLine.fromKeyValue(key, value);
        } else {
            _listMap.insertBack(key, IniLikeLine.fromKeyValue(key, value));
        }
        return value;
    }
    
    /**
     * Insert new value or replaces the old one if value associated with key already exists.
     * Note: The value is not escaped automatically upon writing. It's your responsibility to escape it.
     * Returns: Inserted/updated value or null string if key was not added.
     * Throws: IniLikeEntryException if key or value is not valid or value needs to be escaped.
     * See_Also: $(D writeEntry)
     */
    @safe final string opIndexAssign(string value, string key) {
        validateKeyAndValue(key, value);
        return setKeyValueImpl(key, value);
    }
    
    /**
     * Assign localized value.
     * Note: The value is not escaped automatically upon writing. It's your responsibility to escape it.
     * See_Also: $(D setLocalizedValue), $(D localizedValue), $(D writeEntry)
     */
    @safe final string opIndexAssign(string value, string key, string locale) {
        string keyName = localizedKey(key, locale);
        return this[keyName] = value;
    }
    
    /**
     * Tell if group contains value associated with the key.
     */
    @nogc @safe final bool contains(string key) const nothrow pure {
        return _listMap.getNode(key) !is null;
    }
    
    /**
     * Get value by key.
     * Returns: The value associated with the key, or defaultValue if group does not contain such item.
     * Note: The value is not unescaped automatically.
     * See_Also: $(D readEntry), $(D localizedValue)
     */
    @nogc @safe final string value(string key) const nothrow pure {
        auto node = _listMap.getNode(key);
        if (node) {
            return node.value.value;
        } else {
            return null;
        }
    }
    
    /**
     * Get value by key. This function automatically unescape the found value before returning.
     * Returns: The unescaped value associated with key or null if not found.
     * See_Also: $(D value), $(D writeEntry)
     */
    @safe final string readEntry(string key, string locale = null) const nothrow pure {
        if (locale.length) {
            return localizedValue(key, locale).unescapeValue();
        } else {
            return value(key).unescapeValue();
        }
    }
    
    /**
     * Set value by key. This function automatically escape the value (you should not escape value yourself) when writing it.
     * Throws: $(D IniLikeEntryException) if key or value is not valid.
     * See_Also: $(D readEntry)
     */
    @safe final string writeEntry(string key, string value, string locale = null) {
        value = value.escapeValue();
        validateKeyAndValue(key, value);
        string keyName = localizedKey(key, locale);
        return setKeyValueImpl(keyName, value);
    }
    
    /**
     * Perform locale matching lookup as described in $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s04.html, Localized values for keys).
     * Params:
     *  key = Non-localized key.
     *  locale = Locale in intereset.
     *  nonLocaleFallback = Allow fallback to non-localized version.
     * Returns: The localized value associated with key and locale, 
     * or the value associated with non-localized key if group does not contain localized value and nonLocaleFallback is true.
     * Note: The value is not unescaped automatically.
     * See_Also: $(D value), $(D readEntry)
     */
    @safe final string localizedValue(string key, string locale, bool nonLocaleFallback = true) const nothrow pure {
        //Any ideas how to get rid of this boilerplate and make less allocations?
        const t = parseLocaleName(locale);
        auto lang = t.lang;
        auto country = t.country;
        auto modifier = t.modifier;
        
        if (lang.length) {
            string pick;
            if (country.length && modifier.length) {
                pick = value(localizedKey(key, locale));
                if (pick !is null) {
                    return pick;
                }
            }
            if (country.length) {
                pick = value(localizedKey(key, lang, country));
                if (pick !is null) {
                    return pick;
                }
            }
            if (modifier.length) {
                pick = value(localizedKey(key, lang, string.init, modifier));
                if (pick !is null) {
                    return pick;
                }
            }
            pick = value(localizedKey(key, lang, string.init));
            if (pick !is null) {
                return pick;
            }
        }
        
        if (nonLocaleFallback) {
            return value(key);
        } else {
            return null;
        }
    }
    
    ///
    unittest 
    {
        auto lilf = new IniLikeFile;
        lilf.addGroup("Entry");
        auto group = lilf.group("Entry");
        assert(group.groupName == "Entry"); 
        group["Name"] = "Programmer";
        group["Name[ru_RU]"] = "Разработчик";
        group["Name[ru@jargon]"] = "Кодер";
        group["Name[ru]"] = "Программист";
        group["Name[de_DE@dialect]"] = "Programmierer"; //just example
        group["Name[fr_FR]"] = "Programmeur";
        group["GenericName"] = "Program";
        group["GenericName[ru]"] = "Программа";
        assert(group["Name"] == "Programmer");
        assert(group.localizedValue("Name", "ru@jargon") == "Кодер");
        assert(group.localizedValue("Name", "ru_RU@jargon") == "Разработчик");
        assert(group.localizedValue("Name", "ru") == "Программист");
        assert(group.localizedValue("Name", "ru_RU.UTF-8") == "Разработчик");
        assert(group.localizedValue("Name", "nonexistent locale") == "Programmer");
        assert(group.localizedValue("Name", "de_DE@dialect") == "Programmierer");
        assert(group.localizedValue("Name", "fr_FR.UTF-8") == "Programmeur");
        assert(group.localizedValue("GenericName", "ru_RU") == "Программа");
        assert(group.localizedValue("GenericName", "fr_FR") == "Program");
        assert(group.localizedValue("GenericName", "fr_FR", false) is null);
    }
    
    /**
     * Same as localized version of opIndexAssign, but uses function syntax.
     * Note: The value is not escaped automatically upon writing. It's your responsibility to escape it.
     * Throws: IniLikeEntryException if key or value is not valid or value needs to be escaped.
     * See_Also: $(D writeEntry)
     */
    @safe final void setLocalizedValue(string key, string locale, string value) {
        this[key, locale] = value;
    }
    
    /**
     * Removes entry by key. Do nothing if not value associated with key found.
     * Returns: true if entry was removed, false otherwise.
     */
    @safe final bool removeEntry(string key) nothrow pure {
        return _listMap.remove(key);
    }
    
    ///ditto, but remove entry by localized key
    @safe final void removeEntry(string key, string locale) nothrow pure {
        removeEntry(localizedKey(key, locale));
    }
    
    /**
     * Iterate by Key-Value pairs. Values are left in escaped form.
     * Returns: Range of Tuple!(string, "key", string, "value").
     * See_Also: $(D value), $(D localizedValue)
     */
    @nogc @safe final auto byKeyValue() const nothrow {
        return staticByKeyValue(_listMap.byNode);
    }
    
    /**
     * Empty range of the same type as byKeyValue. Can be used in derived classes if it's needed to have empty range.
     * Returns: Empty range of Tuple!(string, "key", string, "value").
     */
    @nogc @safe static auto emptyByKeyValue() nothrow {
        const ListMap!(string, IniLikeLine) listMap;
        return staticByKeyValue(listMap.byNode);
    }

    ///
    unittest
    {
        assert(emptyByKeyValue().empty);
        auto group = new IniLikeGroup("Group name");
        static assert(is(typeof(emptyByKeyValue()) == typeof(group.byKeyValue()) ));
    }
    
    private @nogc @safe static auto staticByKeyValue(Range)(Range nodes) nothrow {
        return nodes.map!(node => node.value).filter!(v => v.type == IniLikeLine.Type.KeyValue).map!(v => keyValueTuple(v.key, v.value));
    }
    
    /**
     * Get name of this group.
     * Returns: The name of this group.
     */
    @nogc @safe final string groupName() const nothrow pure {
        return _name;
    }
    
    /**
     * Returns: Range of $(D IniLikeLine)s included in this group.
     */
    @trusted final auto byIniLine() const {
        return _listMap.byNode.map!(node => node.value);
    }
    
    /**
     * Add comment line into the group.
     * Returns: Line added as comment.
     * See_Also: $(D byIniLine), $(D prependComment)
     */
    @safe final string appendComment(string comment) nothrow pure {
        comment = makeComment(comment);
        _listMap.append(IniLikeLine.fromComment(comment));
        return comment;
    }
    
    /**
     * Add comment line at the start of group (after group header, before any key-value pairs).
     * Returns: Line added as comment.
     * See_Also: $(D byIniLine), $(D appendComment)
     */
    @safe final string prependComment(string comment) nothrow pure {
        comment = makeComment(comment);
        _listMap.prepend(IniLikeLine.fromComment(comment));
        return comment;
    }
    
protected:
    /**
     * Validate key before setting value to key for this group and throw exception if not valid.
     * Can be reimplemented in derived classes. 
     * Default implementation checks if key is not empty string, does not look like comment and does not contain new line or carriage return characters.
     * Params:
     *  key = key to validate.
     *  value = value that is being set to key.
     * Throws: $(D IniLikeEntryException) if either key is invalid.
     * See_Also: $(D validateValue)
     */
    @trusted void validateKey(string key, string value) const {
        if (key.empty || key.strip.empty) {
            throw new IniLikeEntryException("key must not be empty", _name, key, value);
        }
        if (key.isComment()) {
            throw new IniLikeEntryException("key must not start with #", _name, key, value);
        }
        if (key.canFind('=')) {
            throw new IniLikeEntryException("key must not have '=' character in it", _name, key, value);
        }
        if (key.needEscaping()) {
            throw new IniLikeEntryException("key must not contain new line characters", _name, key, value);
        }
    }
    
    ///
    unittest
    {
        auto ilf = new IniLikeFile();
        ilf.addGroup("Group");
        
        auto entryException = collectException!IniLikeEntryException(ilf.group("Group")[""] = "Value1");
        assert(entryException !is null);
        assert(entryException.groupName == "Group");
        assert(entryException.key == "");
        assert(entryException.value == "Value1");
        
        entryException = collectException!IniLikeEntryException(ilf.group("Group")["    "] = "Value2");
        assert(entryException !is null);
        assert(entryException.key == "    ");
        assert(entryException.value == "Value2");
        
        entryException = collectException!IniLikeEntryException(ilf.group("Group")["New\nLine"] = "Value3");
        assert(entryException !is null);
        assert(entryException.key == "New\nLine");
        assert(entryException.value == "Value3");
        
        entryException = collectException!IniLikeEntryException(ilf.group("Group")["# Comment"] = "Value4");
        assert(entryException !is null);
        assert(entryException.key == "# Comment");
        assert(entryException.value == "Value4");
        
        entryException = collectException!IniLikeEntryException(ilf.group("Group")["Everyone=Is"] = "Equal");
        assert(entryException !is null);
        assert(entryException.key == "Everyone=Is");
        assert(entryException.value == "Equal");
    }
    
    /**
     * Validate value for key before setting value to key for this group and throw exception if not valid.
     * Can be reimplemented in derived classes. 
     * Default implementation checks if value is escaped.
     * Params:
     *  key = key the value is being set to.
     *  value = value to validate. Considered to be escaped.
     * Throws: $(D IniLikeEntryException) if value is invalid.
     * See_Also: $(D validateKey)
     */
    @trusted void validateValue(string key, string value) const {
        if (value.needEscaping()) {
            throw new IniLikeEntryException("The value needs to be escaped", _name, key, value);
        }
    }
    
    ///
    unittest
    {
        auto ilf = new IniLikeFile();
        ilf.addGroup("Group");
        
        auto entryException = collectException!IniLikeEntryException(ilf.group("Group")["Key"] = "New\nline");
        assert(entryException !is null);
        assert(entryException.key == "Key");
        assert(entryException.value == "New\nline");
    }
    
    /**
     * Utility function that calls validateKey and validateValue.
     * See_Also: $(D validateKey), $(D validateValue)
     */
    @safe final void validateKeyAndValue(string key, string value) const {
        validateKey(key, value);
        validateValue(key, value);
    }
    
private:
    ListMap!(string, IniLikeLine) _listMap;
    string _name;
}

///Base class for ini-like format errors.
class IniLikeException : Exception
{
    ///
    this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure nothrow @safe {
        super(msg, file, line, next);
    }
}

/**
 * Exception thrown on the file read error.
 */
class IniLikeReadException : IniLikeException
{
    /**
     * Create IniLikeReadException with msg, lineNumber and fileName.
     */
    this(string msg, size_t lineNumber, string fileName = null, IniLikeEntryException entryException = null, string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure nothrow @safe {
        super(msg, file, line, next);
        _lineNumber = lineNumber;
        _fileName = fileName;
        _entryException = entryException;
    }
    
    /** 
     * Number of line in the file where the exception occured, starting from 1.
     * 0 means that error is not bound to any existing line, but instead relate to file at whole (e.g. required group or key is missing).
     * Don't confuse with $(B line) property of $(B Throwable).
     */
    @nogc @safe size_t lineNumber() const nothrow pure {
        return _lineNumber;
    }
    
    /**
     * Number of line in the file where the exception occured, starting from 0. 
     * Don't confuse with $(B line) property of $(B Throwable).
     */
    @nogc @safe size_t lineIndex() const nothrow pure {
        return _lineNumber ? _lineNumber - 1 : 0;
    }
    
    /**
     * Name of ini-like file where error occured. 
     * Can be empty if fileName was not given upon IniLikeFile creating.
     * Don't confuse with $(B file) property of $(B Throwable).
     */
    @nogc @safe string fileName() const nothrow pure {
        return _fileName;
    }
    
    /**
     * Original IniLikeEntryException which caused this error.
     * This will have the same msg.
     * Returns: $(D IniLikeEntryException) object or null if the cause of error was something else.
     */
    @nogc @safe IniLikeEntryException entryException() nothrow pure {
        return _entryException;
    }
    
private:
    size_t _lineNumber;
    string _fileName;
    IniLikeEntryException _entryException;
}

/**
 * Exception thrown when trying to set invalid key or value.
 */
class IniLikeEntryException : IniLikeException
{
    this(string msg, string group, string key, string value, string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure nothrow @safe {
        super(msg, file, line, next);
        _group = group;
        _key = key;
        _value = value;
    }
    
    /**
     * The key the value associated with.
     */
    @nogc @safe string key() const nothrow pure {
        return _key;
    }
    
    /**
     * The value associated with key.
     */
    @nogc @safe string value() const nothrow pure {
        return _value;
    }
    
    /**
     * Name of group where error occured.
     */
    @nogc @safe string groupName() const nothrow pure {
        return _group;
    }
    
private:
    string _group;
    string _key;
    string _value;
}

/**
 * Ini-like file.
 * 
 */
class IniLikeFile
{
protected:
    /**
     * Add comment for group.
     * This function is called only in constructor and can be reimplemented in derived classes.
     * Params:
     *  comment = Comment line to add.
     *  currentGroup = The group returned recently by createGroup during parsing. Can be null (e.g. if discarded)
     *  groupName = The name of the currently parsed group. Set even if currentGroup is null.
     * See_Also: $(D createGroup), $(D IniLikeGroup.appendComment)
     */
    @trusted void addCommentForGroup(string comment, IniLikeGroup currentGroup, string groupName)
    {
        if (currentGroup) {
            currentGroup.appendComment(comment);
        }
    }
    
    /**
     * Add key/value pair for group.
     * This function is called only in constructor and can be reimplemented in derived classes.
     * Params:
     *  key = Key to insert or set.
     *  value = Value to set for key.
     *  currentGroup = The group returned recently by createGroup during parsing. Can be null (e.g. if discarded)
     *  groupName = The name of the currently parsed group. Set even if currentGroup is null.
     * See_Also: $(D createGroup)
     */
    @trusted void addKeyValueForGroup(string key, string value, IniLikeGroup currentGroup, string groupName)
    {
        if (currentGroup) {
            if (currentGroup.contains(key)) {
                throw new Exception("key already exists");
            }
            currentGroup[key] = value;
        }
    }
    
    /**
     * Create iniLikeGroup by groupName.
     * This function is called only in constructor and can be reimplemented in derived classes, 
     * e.g. to insert additional checks or create specific derived class depending on groupName.
     * Returned value is later passed to addCommentForGroup and addKeyValueForGroup methods as currentGroup. 
     * Reimplemented method also is allowed to return null.
     * Default implementation just returns empty IniLikeGroup with name set to groupName.
     * Throws:
     *  $(D IniLikeException) if group with such name already exists.
     * See_Also:
     *  $(D addKeyValueForGroup), $(D addCommentForGroup)
     */
    @trusted IniLikeGroup createGroup(string groupName)
    {
        if (group(groupName) !is null) {
            throw new IniLikeException("group already exists");
        }
        return createEmptyGroup(groupName);
    }
    
    /**
     * Can be used in derived classes to create instance of IniLikeGroup.
     */
    @safe static createEmptyGroup(string groupName) {
        return new IniLikeGroup(groupName);
    }
    
public:
    /**
     * Construct empty IniLikeFile, i.e. without any groups or values
     */
    @nogc @safe this() nothrow {
        
    }
    
    /**
     * Read from file.
     * Throws:
     *  $(B ErrnoException) if file could not be opened.
     *  $(D IniLikeReadException) if error occured while reading the file.
     */
    @trusted this(string fileName) {
        this(iniLikeFileReader(fileName), fileName);
    }
    
    /**
     * Read from range of inilike.range.IniLikeReader.
     * Note: All exceptions thrown within constructor are turning into IniLikeReadException.
     * Throws:
     *  $(D IniLikeReadException) if error occured while parsing.
     */
    this(IniLikeReader)(IniLikeReader reader, string fileName = null)
    {
        size_t lineNumber = 0;
        IniLikeGroup currentGroup;
        
        version(DigitalMars) {
            static void foo(size_t ) {}
        }
        
        try {
            foreach(line; reader.byLeadingLines)
            {
                lineNumber++;
                if (line.isComment || line.strip.empty) {
                    appendLeadingComment(line);
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
                
                currentGroup = addGroup(groupName);
                
                foreach(line; g.byEntry)
                {
                    lineNumber++;
                    
                    if (line.isComment || line.strip.empty) {
                        addCommentForGroup(line, currentGroup, groupName);
                    } else {
                        const t = parseKeyValue(line);
                        
                        string key = t.key.stripRight;
                        string value = t.value.stripLeft;
                        
                        if (key.length == 0 && value.length == 0) {
                            throw new IniLikeException("Expected comment, empty line or key value inside group");
                        } else {
                            addKeyValueForGroup(key, value, currentGroup, groupName);
                        }
                    }
                }
            }
            
            _fileName = fileName;
            
        }
        catch(IniLikeEntryException e) {
            throw new IniLikeReadException(e.msg, lineNumber, fileName, e, e.file, e.line, e.next);
        }
        catch (Exception e) {
            throw new IniLikeReadException(e.msg, lineNumber, fileName, null, e.file, e.line, e.next);
        }
    }
    
    /**
     * Get group by name.
     * Returns: IniLikeGroup instance associated with groupName or null if not found.
     * See_Also: $(D byGroup)
     */
    @nogc @safe final inout(IniLikeGroup) group(string groupName) nothrow inout pure {
        auto pick = _listMap.getNode(groupName);
        if (pick) {
            return pick.value;
        }
        return null;
    }
    
    /**
     * Create new group using groupName.
     * Returns: Newly created instance of IniLikeGroup.
     * Throws: IniLikeException if group with such name already exists or groupName is empty.
     * See_Also: $(D removeGroup), $(D group)
     */
    @safe final IniLikeGroup addGroup(string groupName) {
        if (groupName.length == 0) {
            throw new IniLikeException("empty group name");
        }
        
        auto iniLikeGroup = createGroup(groupName);
        if (iniLikeGroup !is null) {
            _listMap.insertBack(groupName, iniLikeGroup);
        }
        return iniLikeGroup;
    }
    
    /**
     * Remove group by name. Do nothing if group with such name does not exist.
     * Returns: true if group was deleted, false otherwise.
     * See_Also: $(D addGroup), $(D group)
     */
    @safe bool removeGroup(string groupName) nothrow {
        return _listMap.remove(groupName);
    }
    
    /**
     * Range of groups in order how they were defined in file.
     * See_Also: $(D group)
     */
    @nogc @safe final auto byGroup() inout nothrow {
        return _listMap.byNode().map!(node => node.value);
    }
    
    ///ditto
//     @nogc @safe final auto byGroup() nothrow {
//         return _listMap.byNode().map!(node => node.value);
//     }
    
    
    /**
     * Save object to the file using .ini-like format.
     * Throws: ErrnoException if the file could not be opened or an error writing to the file occured.
     * See_Also: $(D saveToString), $(D save)
     */
    @trusted final void saveToFile(string fileName) const {
        import std.stdio : File;
        
        auto f = File(fileName, "w");
        void dg(in string line) {
            f.writeln(line);
        }
        save(&dg);
    }
    
    /**
     * Save object to string using .ini like format.
     * Returns: A string that represents the contents of file.
     * See_Also: $(D saveToFile), $(D save)
     */
    @trusted final string saveToString() const {
        auto a = appender!(string[])();
        save(a);
        return a.data.join("\n");
    }
    
    /**
     * Use Output range or delegate to retrieve strings line by line. 
     * Those strings can be written to the file or be showed in text area.
     * Note: returned strings don't have trailing newline character.
     */
    final void save(OutRange)(OutRange sink) const if (isOutputRange!(OutRange, string)) {
        foreach(line; leadingComments()) {
            put(sink, line);
        }
        
        foreach(group; byGroup()) {
            put(sink, "[" ~ group.groupName ~ "]");
            foreach(line; group.byIniLine()) {
                if (line.type == IniLikeLine.Type.Comment) {
                    put(sink, line.comment);
                } else if (line.type == IniLikeLine.Type.KeyValue) {
                    put(sink, line.key ~ "=" ~ line.value);
                }
            }
        }
    }
    
    /**
     * File path where the object was loaded from.
     * Returns: File name as was specified on the object creation.
     */
    @nogc @safe final string fileName() nothrow const pure {
        return _fileName;
    }
    
    /**
     * Leading comments.
     * Returns: Range of leading comments (before any group)
     * See_Also: $(D appendLeadingComment), $(D prependLeadingComment)
     */
    @nogc @safe final auto leadingComments() const nothrow pure {
        return _leadingComments;
    }
    
    ///
    unittest
    {
        auto ilf = new IniLikeFile();
        assert(ilf.appendLeadingComment("First") == "#First");
        assert(ilf.appendLeadingComment("#Second") == "#Second");
        assert(ilf.appendLeadingComment("Sneaky\nKey=Value") == "#Sneaky Key=Value");
        assert(ilf.appendLeadingComment("# New Line\n") == "# New Line");
        assert(ilf.appendLeadingComment("") == "");
        assert(ilf.appendLeadingComment("\n") == "");
        assert(ilf.prependLeadingComment("Shebang") == "#Shebang");
        assert(ilf.leadingComments().equal(["#Shebang", "#First", "#Second", "#Sneaky Key=Value", "# New Line", "", ""]));
        ilf.clearLeadingComments();
        assert(ilf.leadingComments().empty);
    }
    
    /**
     * Add leading comment. This will be appended to the list of leadingComments.
     * Note: # will be prepended automatically if line is not empty and does not have # at the start. 
     *  The last new line character will be removed if present. Others will be replaced with whitespaces.
     * Returns: Line that was added as comment.
     * See_Also: $(D leadingComments), $(D prependLeadingComment)
     */
    @safe string appendLeadingComment(string line) nothrow {
        line = makeComment(line);
        _leadingComments ~= line;
        return line;
    }
    
    /**
     * Prepend leading comment (e.g. for setting shebang line).
     * Returns: Line that was added as comment.
     * See_Also: $(D leadingComments), $(D appendLeadingComment)
     */
    @safe string prependLeadingComment(string line) nothrow pure {
        line = makeComment(line);
        _leadingComments = line ~ _leadingComments;
        return line;
    }
    
    /**
     * Remove all coments met before groups.
     * See_Also: $(D leadingComments)
     */
    @nogc final @safe void clearLeadingComments() nothrow {
        _leadingComments = null;
    }
    
private:
    string _fileName;
    ListMap!(string, IniLikeGroup, 8) _listMap;
    string[] _leadingComments;
}

///
unittest
{
    import std.file;
    import std.path;
    import std.stdio;
    
    string contents = 
`# The first comment
[First Entry]
# Comment
GenericName=File manager
GenericName[ru]=Файловый менеджер
NeedUnescape=yes\\i\tneed
NeedUnescape[ru]=да\\я\tнуждаюсь
# Another comment
[Another Group]
Name=Commander
Comment=Manage files
# The last comment`;

    auto ilf = new IniLikeFile(iniLikeStringReader(contents), "contents.ini");
    assert(ilf.fileName() == "contents.ini");
    assert(equal(ilf.leadingComments(), ["# The first comment"]));
    assert(ilf.group("First Entry"));
    assert(ilf.group("Another Group"));
    assert(ilf.saveToString() == contents);
    
    string tempFile = buildPath(tempDir(), "inilike-unittest-tempfile");
    try {
        assertNotThrown!IniLikeReadException(ilf.saveToFile(tempFile));
        auto fileContents = cast(string)std.file.read(tempFile);
        static if( __VERSION__ < 2067 ) {
            assert(equal(fileContents.splitLines, contents.splitLines), "Contents should be preserved as is");
        } else {
            assert(equal(fileContents.lineSplitter, contents.lineSplitter), "Contents should be preserved as is");
        }
        
        IniLikeFile filf; 
        assertNotThrown!IniLikeReadException(filf = new IniLikeFile(tempFile));
        assert(filf.fileName() == tempFile);
        remove(tempFile);
    } catch(Exception e) {
        //environmental error in unittests
    }
    
    auto firstEntry = ilf.group("First Entry");
    
    assert(!firstEntry.contains("NonExistent"));
    assert(firstEntry.contains("GenericName"));
    assert(firstEntry.contains("GenericName[ru]"));
    assert(firstEntry["GenericName"] == "File manager");
    assert(firstEntry.value("GenericName") == "File manager");
    
    assert(firstEntry.value("NeedUnescape") == `yes\\i\tneed`);
    assert(firstEntry.readEntry("NeedUnescape") == "yes\\i\tneed");
    assert(firstEntry.localizedValue("NeedUnescape", "ru") == `да\\я\tнуждаюсь`);
    assert(firstEntry.readEntry("NeedUnescape", "ru") == "да\\я\tнуждаюсь");
    
    firstEntry.writeEntry("NeedEscape", "i\rneed\nescape");
    assert(firstEntry.value("NeedEscape") == `i\rneed\nescape`);
    firstEntry.writeEntry("NeedEscape", "мне\rнужно\nэкранирование", "ru");
    assert(firstEntry.localizedValue("NeedEscape", "ru") == `мне\rнужно\nэкранирование`);
    
    firstEntry["GenericName"] = "Manager of files";
    assert(firstEntry["GenericName"] == "Manager of files");
    firstEntry["Authors"] = "Unknown";
    assert(firstEntry["Authors"] == "Unknown");
    
    assert(firstEntry.localizedValue("GenericName", "ru") == "Файловый менеджер");
    firstEntry.setLocalizedValue("GenericName", "ru", "Менеджер файлов");
    assert(firstEntry.localizedValue("GenericName", "ru") == "Менеджер файлов");
    firstEntry.setLocalizedValue("Authors", "ru", "Неизвестны");
    assert(firstEntry.localizedValue("Authors", "ru") == "Неизвестны");
    
    firstEntry.removeEntry("GenericName");
    assert(!firstEntry.contains("GenericName"));
    firstEntry.removeEntry("GenericName", "ru");
    assert(!firstEntry.contains("GenericName[ru]"));
    firstEntry["GenericName"] = "File Manager";
    assert(firstEntry["GenericName"] == "File Manager");
    
    assert(ilf.group("Another Group")["Name"] == "Commander");
    assert(equal(ilf.group("Another Group").byKeyValue(), [ keyValueTuple("Name", "Commander"), keyValueTuple("Comment", "Manage files") ]));
    
    assert(ilf.group("Another Group").appendComment("The lastest comment"));
    assert(ilf.group("Another Group").prependComment("The first comment"));
    
    assert(equal(
        ilf.group("Another Group").byIniLine(), 
        [IniLikeLine.fromComment("#The first comment"), IniLikeLine.fromKeyValue("Name", "Commander"), IniLikeLine.fromKeyValue("Comment", "Manage files"), IniLikeLine.fromComment("# The last comment"), IniLikeLine.fromComment("#The lastest comment")]
    ));
    
    assert(equal(ilf.byGroup().map!(g => g.groupName), ["First Entry", "Another Group"]));
    
    assert(!ilf.removeGroup("NonExistent Group"));
    
    assert(ilf.removeGroup("Another Group"));
    assert(!ilf.group("Another Group"));
    assert(equal(ilf.byGroup().map!(g => g.groupName), ["First Entry"]));
    
    ilf.addGroup("Another Group");
    assert(ilf.group("Another Group"));
    assert(ilf.group("Another Group").byIniLine().empty);
    assert(ilf.group("Another Group").byKeyValue().empty);
    
    ilf.addGroup("Other Group");
    assert(equal(ilf.byGroup().map!(g => g.groupName), ["First Entry", "Another Group", "Other Group"]));
    
    assertThrown!IniLikeException(ilf.addGroup(""));
    
    import std.range : isForwardRange;
    
    const IniLikeFile cilf = ilf;
    static assert(isForwardRange!(typeof(cilf.byGroup())));
    static assert(isForwardRange!(typeof(cilf.group("First Entry").byKeyValue())));
    static assert(isForwardRange!(typeof(cilf.group("First Entry").byIniLine())));
    
    contents = 
`[Group]
GenericName=File manager
[Group]
GenericName=Commander`;

    auto shouldThrow = collectException!IniLikeReadException(new IniLikeFile(iniLikeStringReader(contents), "config.ini"));
    assert(shouldThrow !is null, "Duplicate groups should throw");
    assert(shouldThrow.lineNumber == 3);
    assert(shouldThrow.lineIndex == 2);
    assert(shouldThrow.fileName == "config.ini");
    
    contents = 
`[Group]
Key=Value1
Key=Value2`;

    shouldThrow = collectException!IniLikeReadException(new IniLikeFile(iniLikeStringReader(contents)));
    assert(shouldThrow !is null, "Duplicate key should throw");
    assert(shouldThrow.lineNumber == 3);
    
    contents =
`[Group]
Key=Value
=File manager`;

    shouldThrow = collectException!IniLikeReadException(new IniLikeFile(iniLikeStringReader(contents)));
    assert(shouldThrow !is null, "Empty key should throw");
    assert(shouldThrow.lineNumber == 3);
    
    contents = 
`[Group]
#Comment
Valid=Key
NotKeyNotGroupNotComment`;

    shouldThrow = collectException!IniLikeReadException(new IniLikeFile(iniLikeStringReader(contents)));
    assert(shouldThrow !is null, "Invalid entry should throw");
    assert(shouldThrow.lineNumber == 4);
    
    contents = 
`#Comment
NotComment
[Group]
Valid=Key`;
    shouldThrow = collectException!IniLikeReadException(new IniLikeFile(iniLikeStringReader(contents)));
    assert(shouldThrow !is null, "Invalid comment should throw");
    assert(shouldThrow.lineNumber == 2);
}
