module dlangide.ui.terminal;

import dlangui.widgets.widget;
import dlangui.widgets.controls;

struct TerminalAttr {
    ubyte bgColor = 7;
    ubyte textColor = 0;
}

struct TerminalChar {
    TerminalAttr attr;
    dchar ch = ' ';
}

__gshared static uint[16] TERMINAL_PALETTE = [
    0x000000, // black
    0xFF0000,
    0x00FF00,
    0xFFFF00,
    0x0000FF,
    0xFF00FF,
    0x00FFFF,
    0xFFFFFF, // white
    0x808080,
    0x800000,
    0x008000,
    0x808000,
    0x000080,
    0x800080,
    0x008080,
    0xC0C0C0,
];

uint attrToColor(ubyte v) {
    if (v >= 16)
        return 0;
    return TERMINAL_PALETTE[v];
}

struct TerminalLine {
    TerminalChar[] line;
    bool overflowFlag;
    bool eolFlag;
    void clear() {
        line.length = 0;
        overflowFlag = false;
        eolFlag = false;
    }
    void markLineOverflow() {}
    void markLineEol() {}
    void putCharAt(dchar ch, int x, TerminalAttr currentAttr) {
        if (x >= line.length) {
            TerminalChar d;
            d.attr = currentAttr;
            d.ch = ' ';
            while (x >= line.length) {
                line.assumeSafeAppend;
                line ~= d;
            }
        }
        line[x].attr = currentAttr;
        line[x].ch = ch;
    }
}

struct TerminalContent {
    TerminalLine[] lines;
    Rect rc;
    FontRef font;
    TerminalAttr currentAttr;
    int maxBufferLines = 3000;
    int topLine;
    int width; // width in chars
    int height; // height in chars
    int charw; // single char width
    int charh; // single char height
    int cursorx;
    int cursory;
    bool focused;
    bool _lineWrap = true;
    @property void lineWrap(bool v) {
        _lineWrap = v;
    }
    void resetTerminal() {
        for (int i = topLine; i < cast(int)lines.length; i++) {
            lines[i] = TerminalLine.init;
        }
        cursorx = 0;
        cursory = topLine;
    }
    @property int screenTopLine() {
        int y = cast(int)lines.length - height;
        if (y < 0)
            y = 0;
        return y;
    }
    void eraseScreen(int direction, bool forLine) {
        if (forLine) {
            for (int x = 0; x < width; x++) {
                if ((direction == 1 && x <= cursorx) || (direction < 1 && x >= cursorx) || (direction == 2))
                    putCharAt(' ', x, cursory);
            }
        } else {
            int screenTop = screenTopLine;
            for (int y = 0; y < height; y++) {
                int yy = screenTop + y;
                if ((direction == 1 && yy <= cursory) || (direction < 1 && yy >= cursory) || (direction == 2)) {
                    for (int x = 0; x < width; x++) {
                        putCharAt(' ', x, yy);
                    }
                }
            }
            if (direction == 2) {
                cursorx = 0;
                cursory = screenTop;
            }
        }
    }
    void moveCursorBy(int x, int y) {
        if (x) {
            cursorx += x;
            if (cursorx < 0)
                cursorx = 0;
            if (cursorx > width)
                cursorx = width;
        } else if (y) {
            int screenTop = screenTopLine;
            cursory += y;
            if (cursory < screenTop)
                cursory = screenTop;
            else if (cursory >= screenTop + height)
                cursory = screenTop + height - 1;
        }
    }
    void moveCursorTo(int x, int y) {
        int screenTop = screenTopLine;
        if (x < 0 || y < 0) {
            cursorx = 0;
            cursory = screenTop;
            return;
        }
        if (x >= 1 && x <= width + 1 && y >= 1 && x <= height) {
            cursorx = x - 1;
            cursory = screenTop + y - 1;
        }
    }
    void layout(FontRef font, Rect rc) {
        this.rc = rc;
        this.font = font;
        this.charw = font.charWidth('0');
        this.charh = font.height;
        int w = rc.width / charw;
        int h = rc.height / charh;
        setViewSize(w, h);
    }
    void setViewSize(int w, int h) {
        if (h < 2)
            h = 2;
        if (w < 16)
            w = 16;
        width = w;
        height = h;
    }
    void draw(DrawBuf buf) {
        Rect lineRect = rc;
        dchar[] text;
        text.length = 1;
        text[0] = ' ';
        int screenTopLine = cast(int)lines.length - height;
        if (screenTopLine < 0)
            screenTopLine = 0;
        for (uint i = 0; i < height && i + topLine < lines.length; i++) {
            lineRect.bottom = lineRect.top + charh;
            TerminalLine * p = &lines[i + topLine];
            // draw line in rect
            for (int x = 0; x < width; x++) {
                bool isCursorPos = x == cursorx && i + topLine == cursory;
                TerminalChar ch = x < p.line.length ? p.line[x] : TerminalChar.init;
                uint bgcolor = attrToColor(ch.attr.bgColor);
                uint textcolor = attrToColor(ch.attr.textColor);
                if (isCursorPos && focused) {
                    // invert
                    uint tmp = bgcolor;
                    bgcolor = textcolor;
                    textcolor = tmp;
                }
                Rect charrc = lineRect;
                charrc.left = lineRect.left + x * charw;
                charrc.right = charrc.left + charw;
                charrc.bottom = charrc.top + charh;
                buf.fillRect(charrc, bgcolor);
                if (isCursorPos) {
                    buf.drawFrame(charrc, focused ? (textcolor | 0xC0000000) : (textcolor | 0x80000000), Rect(1,1,1,1));
                }
                if (ch.ch >= ' ') {
                    text[0] = ch.ch;
                    font.drawText(buf, charrc.left, charrc.top, text, textcolor);
                }
            }
            lineRect.top = lineRect.bottom;
        }
    }

    void clearExtraLines(ref int yy) {
        int y = cast(int)lines.length;
        if (y >= maxBufferLines) {
            int delta = y - maxBufferLines;
            for (uint i = 0; i + delta < maxBufferLines && i + delta < lines.length; i++) {
                lines[i] = lines[i + delta];
            }
            lines.length = lines.length - delta;
            yy -= delta;
            topLine -= delta;
            if (topLine < 0)
                topLine = 0;
        }
    }

    TerminalLine * getLine(ref int yy) {
        if (yy < 0)
            yy = 0;
        while(yy >= cast(int)lines.length) {
            lines ~= TerminalLine.init;
        }
        clearExtraLines(yy);
        return &lines[yy];
    }
    void putCharAt(dchar ch, ref int x, ref int y) {
        if (x < 0)
            x = 0;
        TerminalLine * line = getLine(y);
        if (x >= width) {
            line.markLineOverflow();
            y++;
            line = getLine(y);
            x = 0;
        }
        line.putCharAt(ch, x, currentAttr);
        ensureCursorIsVisible();
    }
    int tabSize = 8;
    // supports printed characters and \r \n \t
    void putChar(dchar ch) {
        if (ch == '\a') {
            // bell
            return;
        }
        if (ch == '\b') {
            // backspace
            if (cursorx > 0) {
                cursorx--;
                putCharAt(' ', cursorx, cursory);
                ensureCursorIsVisible();
            }
            return;
        }
        if (ch == '\r') {
            cursorx = 0;
            ensureCursorIsVisible();
            return;
        }
        if (ch == '\n' || ch == '\f' || ch == '\v') {
            TerminalLine * line = getLine(cursory);
            line.markLineEol();
            cursory++;
            line = getLine(cursory);
            cursorx = 0;
            ensureCursorIsVisible();
            return;
        }
        if (ch == '\t') {
            int newx = (cursorx + tabSize) / tabSize * tabSize;
            if (newx > width) {
                TerminalLine * line = getLine(cursory);
                line.markLineEol();
                cursory++;
                line = getLine(cursory);
                cursorx = 0;
            } else {
                for (int x = cursorx; x < newx; x++) {
                    putCharAt(' ', cursorx, cursory);
                    cursorx++;
                }
            }
            ensureCursorIsVisible();
            return;
        }
        putCharAt(ch, cursorx, cursory);
        cursorx++;
        ensureCursorIsVisible();
    }

    void ensureCursorIsVisible() {
        topLine = cast(int)lines.length - height;
        if (topLine < 0)
            topLine = 0;
        if (cursory < topLine)
            cursory = topLine;
    }

    void updateScrollBar(ScrollBar sb) {
        sb.pageSize = height;
        sb.maxValue = cast(int)lines.length;
        sb.position = topLine;
    }

    void scrollTo(int y) {
        if (y + height > lines.length)
            y = cast(int)lines.length - height;
        if (y < 0)
            y = 0;
        topLine = y;
    }

}

class TerminalWidget : WidgetGroup, OnScrollHandler {
    protected ScrollBar _verticalScrollBar;
    protected TerminalContent _content;
    this() {
        this(null);
    }
    this(string ID) {
        super(ID);
        styleId = "TERMINAL";
        focusable = true;
        _verticalScrollBar = new ScrollBar("VERTICAL_SCROLLBAR", Orientation.Vertical);
        _verticalScrollBar.minValue = 0;
        _verticalScrollBar.scrollEvent = this;
        addChild(_verticalScrollBar);
    }

    void scrollTo(int y) {
        _content.scrollTo(y);
    }

    /// handle scroll event
    bool onScrollEvent(AbstractSlider source, ScrollEvent event) {
        switch(event.action) {
            /// space above indicator pressed
            case ScrollAction.PageUp:
                scrollTo(_content.topLine - (_content.height ? _content.height - 1 : 1));
                break;
            /// space below indicator pressed
            case ScrollAction.PageDown:
                scrollTo(_content.topLine + (_content.height ? _content.height - 1 : 1));
                break;
            /// up/left button pressed
            case ScrollAction.LineUp:
                scrollTo(_content.topLine - 1);
                break;
            /// down/right button pressed
            case ScrollAction.LineDown:
                scrollTo(_content.topLine + 1);
                break;
            /// slider pressed
            case ScrollAction.SliderPressed:
                break;
            /// dragging in progress
            case ScrollAction.SliderMoved:
                scrollTo(event.position);
                break;
            /// dragging finished
            case ScrollAction.SliderReleased:
                break;
            default:
                break;
        }
        return true;
    }

    /** 
    Measure widget according to desired width and height constraints. (Step 1 of two phase layout). 

    */
    override void measure(int parentWidth, int parentHeight) {
        int w = (parentWidth == SIZE_UNSPECIFIED) ? font.charWidth('0') * 80 : parentWidth;
        int h = (parentHeight == SIZE_UNSPECIFIED) ? font.height * 10 : parentHeight;
        Rect rc = Rect(0, 0, w, h);
        applyMargins(rc);
        applyPadding(rc);
        _verticalScrollBar.measure(rc.width, rc.height);
        rc.right -= _verticalScrollBar.measuredWidth;
        measuredContent(parentWidth, parentHeight, rc.width, rc.height);
    }

    /// Set widget rectangle to specified value and layout widget contents. (Step 2 of two phase layout).
    override void layout(Rect rc) {
        if (visibility == Visibility.Gone) {
            return;
        }
        _pos = rc;
        _needLayout = false;
        applyMargins(rc);
        applyPadding(rc);
        Rect sbrc = rc;
        sbrc.left = sbrc.right - _verticalScrollBar.measuredWidth;
        _verticalScrollBar.layout(sbrc);
        rc.right = sbrc.left;
        _content.layout(font, rc);
        if (outputChars.length) {
            // push buffered text
            write(""d);
            _needLayout = false;
        }
    }
    /// Draw widget at its position to buffer
    override void onDraw(DrawBuf buf) {
        if (visibility != Visibility.Visible)
            return;
        Rect rc = _pos;
        applyMargins(rc);
        auto saver = ClipRectSaver(buf, rc, alpha);
        DrawableRef bg = backgroundDrawable;
        if (!bg.isNull) {
            bg.drawTo(buf, rc, state);
        }
        applyPadding(rc);
        _verticalScrollBar.onDraw(buf);
        _content.draw(buf);
    }

    private char[] outputBuffer;
    // write utf 8
    void write(string bytes) {
        if (!bytes.length)
            return;
        import std.utf;
        outputBuffer.assumeSafeAppend;
        outputBuffer ~= bytes;
        size_t index = 0;
        dchar[] decoded;
        decoded.assumeSafeAppend;
        dchar ch = 0;
        while (index < outputBuffer.length) {
            size_t oldindex = index;
            try {
                ch = decode(outputBuffer, index);
                decoded ~= ch;
            } catch (UTFException e) {
                if (index + 4 <= outputBuffer.length) {
                    // just append invalid character
                    ch = '?';
                    index++;
                }
            }
            if (oldindex == index)
                break;
        }
        if (index > 0) {
            // move content
            for (size_t i = 0; i + index < outputBuffer.length; i++)
                outputBuffer[i] = outputBuffer[i + index];
            outputBuffer.length = outputBuffer.length - index;
        }
        if (decoded.length)
            write(cast(dstring)decoded);
    }

    static bool parseParam(dchar[] buf, ref int index, ref int value) {
        if (index >= buf.length)
            return false;
        if (buf[index] < '0' || buf[index] > '9')
            return false;
        value = 0;
        while (index < buf.length && buf[index] >= '0' && buf[index] <= '9') {
            value = value * 10 + (buf[index] - '0');
            index++;
        }
        return true;
    }

    private dchar[] outputChars;
    // write utf32
    void write(dstring chars) {
        if (!chars.length && !outputChars.length)
            return;
        outputChars.assumeSafeAppend;
        outputChars ~= chars;
        if (!_content.width)
            return;
        uint i = 0;
        for (; i < outputChars.length; i++) {
            bool unfinished = false;
            dchar ch = outputChars[i];
            dchar ch2 = i + 1 < outputChars.length ? outputChars[i + 1] : 0;
            dchar ch3 = i + 2 < outputChars.length ? outputChars[i + 2] : 0;
            //dchar ch4 = i + 3 < outputChars.length ? outputChars[i + 3] : 0;
            if (ch < ' ') {
                // control character
                if (ch == 27) {
                    if (ch2 == 0)
                        break; // unfinished ESC sequence
                    // ESC sequence
                    if (ch2 == '[') {
                        // ESC [
                        if (!ch3)
                            break; // unfinished
                        int param1 = -1;
                        int param2 = -1;
                        int index = i + 2;
                        bool questionMark = false;
                        if (index < outputChars.length && outputChars[index] == '?') {
                            questionMark = true;
                            index++;
                        }
                        parseParam(outputChars, index, param1);
                        if (index < outputChars.length && outputChars[index] == ';') {
                            index++;
                            parseParam(outputChars, index, param2);
                        }
                        if (index >= outputChars.length)
                            break; // unfinished sequence: not enough chars
                        int param1def1 = param1 >= 1 ? param1 : 1;
                        ch3 = outputChars[index];
                        i = index;
                        // command is parsed completely, ch3 == command type char

                        // ESC[7h and ESC[7l -- enable/disable line wrap
                        if (param1 == '7' && (ch3 == 'h' || ch3 == 'l')) {
                            _content.lineWrap(ch3 == 'h');
                            continue;
                        }
                        if (ch3 == 'H' || ch3 == 'f') {
                            _content.moveCursorTo(param2, param1);
                            continue;
                        }
                        if (ch3 == 'A') { // cursor up
                            _content.moveCursorBy(0, -param1def1);
                            continue;
                        }
                        if (ch3 == 'B') { // cursor down
                            _content.moveCursorBy(0, param1def1);
                            continue;
                        }
                        if (ch3 == 'C') { // cursor forward
                            _content.moveCursorBy(param1def1, 0);
                            continue;
                        }
                        if (ch3 == 'D') { // cursor back
                            _content.moveCursorBy(-param1def1, 0);
                            continue;
                        }
                        if (ch3 == 'K' || ch3 == 'J') {
                            _content.eraseScreen(param1, ch3 == 'K');
                            continue;
                        }
                    } else switch(ch2) {
                    case 'c':
                        _content.resetTerminal();
                        i++;
                        break;
                    case '=': // Set alternate keypad mode
                    case '>': // Set numeric keypad mode
                    case 'N': // Set single shift 2
                    case 'O': // Set single shift 3
                    case 'H': // Set a tab at the current column
                    case '<': // Enter/exit ANSI mode (VT52)
                        i++;
                        // ignore
                        break;
                    case '(': // default font
                    case ')': // alternate font
                        i++;
                        i++;
                        // ignore
                        break;
                    default:
                        // unsupported
                        break;
                    }
                    if (unfinished)
                        break;
                } else switch(ch) {
                    case '\a': // bell
                    case '\f': // form feed
                    case '\v': // vtab
                    case '\r': // cr
                    case '\n': // lf
                    case '\t': // tab
                    case '\b': // backspace
                        _content.putChar(ch);
                        break;
                    default:
                        break;
                }
            } else {
                _content.putChar(ch);
            }
        }
        if (i > 0) {
            if (i == outputChars.length)
                outputChars.length = 0;
            else {
                for (uint j = 0; j + i < outputChars.length; j++)
                    outputChars[j] = outputChars[j + i];
                outputChars.length = outputChars.length - i;
            }
        }
        _content.updateScrollBar(_verticalScrollBar);
    }

    /// override to handle focus changes
    override protected void handleFocusChange(bool focused, bool receivedFocusFromKeyboard = false) {
        if (focused)
            _content.focused = true;
        else {
            _content.focused = false;
        }
        super.handleFocusChange(focused);
    }

}
