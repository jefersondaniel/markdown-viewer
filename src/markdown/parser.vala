/* Block-level Markdown parser.
 *
 * Follows CommonMark + GitHub extensions (tables, task lists, strikethrough,
 * autolinks) closely enough for everyday documents. Container blocks
 * (block quotes, list items, HTML containers) are parsed recursively: their
 * lines are collected, the container prefix is stripped, and the result is
 * parsed again as a document of its own.
 */

namespace Markdown {

    class SrcLine {
        public string text;
        public int num;

        public SrcLine (string text, int num) {
            this.text = text;
            this.num = num;
        }
    }

    public class LinkRef {
        public string url;
        public string title;

        public LinkRef (string url, string title) {
            this.url = url;
            this.title = title;
        }
    }

    struct ListMarker {
        public bool ordered;
        public char delim;
        public int number;
        public int width;
        public string content;
    }

    public class Parser {
        HashTable<string, LinkRef> refs = new HashTable<string, LinkRef> (str_hash, str_equal);

        public Block parse (string text) {
            var doc = new Block (BlockKind.DOCUMENT);
            parse_lines (split_lines (text), doc);
            resolve_inlines (doc);
            return doc;
        }

        /* ---- Lines ---- */

        static GenericArray<SrcLine> split_lines (string text) {
            var lines = new GenericArray<SrcLine> ();
            string[] raw = text.split ("\n");
            int start = 0;

            // YAML front matter is metadata, not content.
            if (raw.length > 1 && raw[0].strip () == "---") {
                for (int k = 1; k < raw.length; k++) {
                    string l = raw[k].strip ();
                    if (l == "---" || l == "...") {
                        start = k + 1;
                        break;
                    }
                }
            }

            for (int k = start; k < raw.length; k++) {
                string l = raw[k];
                if (l.has_suffix ("\r")) {
                    l = l.substring (0, l.length - 1);
                }
                lines.add (new SrcLine (expand_tabs (l), k));
            }
            return lines;
        }

        /* Tabs in the indentation become spaces (tab stops of 4). */
        static string expand_tabs (string s) {
            if (s.index_of_char ('\t') < 0) {
                return s;
            }
            var sb = new StringBuilder ();
            int i = 0;
            int col = 0;
            for (; i < s.length; i++) {
                if (s[i] == ' ') {
                    sb.append_c (' ');
                    col++;
                } else if (s[i] == '\t') {
                    int spaces = 4 - (col % 4);
                    for (int k = 0; k < spaces; k++) {
                        sb.append_c (' ');
                    }
                    col += spaces;
                } else {
                    break;
                }
            }
            sb.append (s.substring (i));
            return sb.str;
        }

        internal static bool is_blank (string s) {
            for (int i = 0; i < s.length; i++) {
                if (s[i] != ' ' && s[i] != '\t') {
                    return false;
                }
            }
            return true;
        }

        static int indent_of (string s) {
            int i = 0;
            while (i < s.length && s[i] == ' ') {
                i++;
            }
            return i;
        }

        static int run_length (string s, int from, char c) {
            int i = from;
            while (i < s.length && s[i] == c) {
                i++;
            }
            return i - from;
        }

        /* ---- Block detection helpers ---- */

        static bool is_thematic_break (string t) {
            if (t.length < 3) {
                return false;
            }
            char c = t[0];
            if (c != '*' && c != '-' && c != '_') {
                return false;
            }
            int count = 0;
            for (int i = 0; i < t.length; i++) {
                if (t[i] == c) {
                    count++;
                } else if (t[i] != ' ' && t[i] != '\t') {
                    return false;
                }
            }
            return count >= 3;
        }

        static bool is_setext (string t, char c) {
            if (t.length == 0) {
                return false;
            }
            for (int i = 0; i < t.length; i++) {
                if (t[i] != c) {
                    return false;
                }
            }
            return true;
        }

        static bool is_atx (string t) {
            if (t.length == 0 || t[0] != '#') {
                return false;
            }
            int lvl = run_length (t, 0, '#');
            return lvl <= 6 && (t.length == lvl || t[lvl] == ' ');
        }

        static bool is_fence (string t) {
            if (t.length < 3 || (t[0] != '`' && t[0] != '~')) {
                return false;
            }
            return run_length (t, 0, t[0]) >= 3;
        }

        static bool is_html_block_start (string t) {
            return t.has_prefix ("<!--")
                || /^<\/?(div|p|center|details|summary|h[1-6]|hr|br|table|pre|ul|ol|li|blockquote|section|figure|picture)(\s|\/?>|$)/i.match (t);
        }

        static bool match_list_marker (string line, out ListMarker m) {
            m = ListMarker ();
            m.content = "";
            int len = line.length;
            int p = indent_of (line);
            if (p > 3 || p >= len) {
                return false;
            }

            int q;
            char c = line[p];
            if (c == '-' || c == '+' || c == '*') {
                m.ordered = false;
                m.delim = c;
                q = p + 1;
            } else if (c.isdigit ()) {
                q = p;
                while (q < len && line[q].isdigit () && q - p < 9) {
                    q++;
                }
                if (q >= len || (line[q] != '.' && line[q] != ')')) {
                    return false;
                }
                m.ordered = true;
                m.number = int.parse (line.substring (p, q - p));
                m.delim = line[q];
                q++;
            } else {
                return false;
            }

            if (q < len && line[q] != ' ') {
                return false;
            }

            int r = q;
            while (r < len && line[r] == ' ') {
                r++;
            }
            if (r >= len) {
                m.width = q + 1;
            } else if (r - q > 4) {
                // Content is an indented code block; the marker eats one space.
                m.width = q + 1;
                m.content = line.substring (q + 1);
            } else {
                m.width = r;
                m.content = line.substring (r);
            }
            return true;
        }

        /* Can this line interrupt a paragraph? */
        static bool starts_block (string line) {
            if (indent_of (line) > 3) {
                return false;
            }
            string t = line.chug ();
            if (t.length == 0) {
                return false;
            }
            if (is_atx (t) || t[0] == '>' || is_fence (t) || is_thematic_break (t)) {
                return true;
            }
            ListMarker m;
            if (match_list_marker (line, out m) && !is_blank (m.content) && (!m.ordered || m.number == 1)) {
                return true;
            }
            return t[0] == '<' && is_html_block_start (t);
        }

        static string[] split_row (string s) {
            string t = s.strip ();
            if (t.has_prefix ("|")) {
                t = t.substring (1);
            }
            if (t.has_suffix ("|") && !t.has_suffix ("\\|")) {
                t = t.substring (0, t.length - 1);
            }

            string[] cells = {};
            var cur = new StringBuilder ();
            bool in_code = false;
            for (int k = 0; k < t.length; k++) {
                char c = t[k];
                if (c == '\\' && k + 1 < t.length && t[k + 1] == '|') {
                    cur.append_c ('|');
                    k++;
                    continue;
                }
                if (c == '`') {
                    in_code = !in_code;
                }
                if (c == '|' && !in_code) {
                    cells += cur.str.strip ();
                    cur.truncate (0);
                    continue;
                }
                cur.append_c (c);
            }
            cells += cur.str.strip ();
            return cells;
        }

        static bool is_table_start (string header, string delim) {
            if (indent_of (header) > 3 || !header.contains ("|")) {
                return false;
            }
            string d = delim.strip ();
            if (!/^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?$/.match (d)) {
                return false;
            }
            return split_row (header).length == split_row (d).length;
        }

        internal static string normalize_label (string s) {
            return string.joinv (" ", Regex.split_simple ("\\s+", s.strip ())).casefold ();
        }

        static Align parse_align (string attrs) {
            MatchInfo mi;
            if (/align\s*=\s*["']?(left|center|right)/i.match (attrs, 0, out mi)) {
                switch (mi.fetch (1).down ()) {
                case "center":
                    return Align.CENTER;
                case "right":
                    return Align.RIGHT;
                default:
                    return Align.LEFT;
                }
            }
            return Align.NONE;
        }

        /* ---- Block parsing ---- */

        /* Parses `lines` into children of `parent`. Returns whether blank lines
         * separated any of the blocks (used to tell tight from loose lists). */
        bool parse_lines (GenericArray<SrcLine> lines, Block parent) {
            int n = (int) lines.length;
            int i = 0;
            bool blank_between = false;
            bool seen_block = false;
            bool pending_blank = false;
            int lead_line = -1;

            while (i < n) {
                string line = lines[i].text;
                int num = lines[i].num;

                if (is_blank (line)) {
                    pending_blank = true;
                    i++;
                    continue;
                }
                if (seen_block && pending_blank) {
                    blank_between = true;
                }
                pending_blank = false;
                seen_block = true;

                int ind = indent_of (line);
                string t = line.chug ();

                // Indented code block.
                if (ind >= 4) {
                    int j = i;
                    int last = i;
                    while (j < n) {
                        string l = lines[j].text;
                        if (!is_blank (l)) {
                            if (indent_of (l) < 4) {
                                break;
                            }
                            last = j;
                        }
                        j++;
                    }
                    var code = new StringBuilder ();
                    for (int k = i; k <= last; k++) {
                        string l = lines[k].text;
                        code.append (l.length >= 4 ? l.substring (4) : "");
                        code.append_c ('\n');
                    }
                    var b = new Block (BlockKind.CODE);
                    b.code = code.str;
                    b.line = num;
                    parent.add (b);
                    i = last + 1;
                    continue;
                }

                // Fenced code block.
                if (is_fence (t)) {
                    char fc = t[0];
                    int flen = run_length (t, 0, fc);
                    string info = t.substring (flen).strip ();
                    if (fc != '`' || !info.contains ("`")) {
                        var code = new StringBuilder ();
                        int j = i + 1;
                        while (j < n) {
                            string l = lines[j].text;
                            string lt = l.chug ();
                            if (indent_of (l) <= 3 && lt.length > 0 && lt[0] == fc) {
                                int run = run_length (lt, 0, fc);
                                if (run >= flen && is_blank (lt.substring (run))) {
                                    j++;
                                    break;
                                }
                            }
                            int strip = int.min (ind, indent_of (l));
                            code.append (l.substring (strip));
                            code.append_c ('\n');
                            j++;
                        }
                        var b = new Block (BlockKind.CODE);
                        int space = info.index_of_char (' ');
                        b.info = space > 0 ? info.substring (0, space) : info;
                        b.code = code.str;
                        b.line = num;
                        parent.add (b);
                        i = j;
                        continue;
                    }
                }

                // HTML comments are hidden.
                if (t.has_prefix ("<!--")) {
                    int j = i;
                    while (j < n && !lines[j].text.contains ("-->")) {
                        j++;
                    }
                    i = j + 1;
                    continue;
                }

                // Block-level HTML from the supported subset.
                if (t[0] == '<') {
                    int consumed = parse_html_block (lines, i, parent);
                    if (consumed > 0) {
                        i += consumed;
                        continue;
                    }
                }

                // ATX heading.
                if (is_atx (t)) {
                    int lvl = run_length (t, 0, '#');
                    string content = t.substring (lvl).strip ();
                    // Optional closing sequence of #s.
                    int end = content.length;
                    while (end > 0 && content[end - 1] == '#') {
                        end--;
                    }
                    if (end == 0 || content[end - 1] == ' ') {
                        content = content.substring (0, end).strip ();
                    }
                    var h = new Block (BlockKind.HEADING);
                    h.level = lvl;
                    h.raw = content;
                    h.line = num;
                    parent.add (h);
                    if (lvl == 1) {
                        lead_line = num + 1;
                    }
                    i++;
                    continue;
                }

                if (is_thematic_break (t)) {
                    parent.add (new Block (BlockKind.RULE));
                    i++;
                    continue;
                }

                // Block quote.
                if (t[0] == '>') {
                    var inner = new GenericArray<SrcLine> ();
                    int j = i;
                    bool prev_text = false;
                    while (j < n) {
                        string l = lines[j].text;
                        string lt = l.chug ();
                        if (indent_of (l) <= 3 && lt.length > 0 && lt[0] == '>') {
                            string rest = lt.substring (1);
                            if (rest.has_prefix (" ")) {
                                rest = rest.substring (1);
                            }
                            inner.add (new SrcLine (rest, lines[j].num));
                            prev_text = !is_blank (rest) && !is_fence (rest.chug ());
                            j++;
                        } else if (prev_text && !is_blank (l) && !starts_block (l)) {
                            // Lazy continuation of a paragraph inside the quote.
                            inner.add (new SrcLine (l, lines[j].num));
                            j++;
                        } else {
                            break;
                        }
                    }
                    var q = new Block (BlockKind.BLOCKQUOTE);
                    q.line = num;
                    parse_lines (inner, q);
                    parent.add (q);
                    i = j;
                    continue;
                }

                // List.
                ListMarker m;
                if (match_list_marker (line, out m)) {
                    i = parse_list (lines, i, m, parent, out pending_blank);
                    continue;
                }

                // Table.
                if (i + 1 < n && is_table_start (line, lines[i + 1].text)) {
                    i = parse_table (lines, i, parent);
                    continue;
                }

                // Link reference definition.
                if (t[0] == '[') {
                    MatchInfo mi;
                    if (/^\[([^\]]+)\]:\s*(<[^>]*>|\S+)(?:\s+("[^"]*"|'[^']*'|\([^)]*\)))?\s*$/.match (t, 0, out mi)) {
                        string label = normalize_label (mi.fetch (1));
                        string url = mi.fetch (2);
                        if (url.has_prefix ("<") && url.has_suffix (">")) {
                            url = url.substring (1, url.length - 2);
                        }
                        string title = mi.fetch (3) ?? "";
                        if (title.length >= 2) {
                            title = title.substring (1, title.length - 2);
                        }
                        if (!refs.contains (label)) {
                            refs.insert (label, new LinkRef (url, title));
                        }
                        i++;
                        continue;
                    }
                }

                // Paragraph, possibly turned into a setext heading.
                var sb = new StringBuilder ();
                int j = i;
                int setext = 0;
                while (j < n) {
                    string l = lines[j].text;
                    if (is_blank (l)) {
                        break;
                    }
                    if (j > i) {
                        string lt = l.strip ();
                        if (indent_of (l) <= 3 && is_setext (lt, '=')) {
                            setext = 1;
                            j++;
                            break;
                        }
                        if (indent_of (l) <= 3 && is_setext (lt, '-')) {
                            setext = 2;
                            j++;
                            break;
                        }
                        if (starts_block (l) || (j + 1 < n && is_table_start (l, lines[j + 1].text))) {
                            break;
                        }
                    }
                    if (sb.len > 0) {
                        sb.append_c ('\n');
                    }
                    sb.append (l.chug ());
                    j++;
                }

                if (setext > 0) {
                    var h = new Block (BlockKind.HEADING);
                    h.level = setext;
                    h.raw = sb.str.strip ();
                    h.line = num;
                    parent.add (h);
                } else {
                    var p = new Block (BlockKind.PARAGRAPH);
                    p.raw = sb.str.chomp ();
                    p.line = num;
                    p.lead = num == lead_line && j == i + 1;
                    parent.add (p);
                }
                i = j;
            }
            return blank_between;
        }

        int parse_list (GenericArray<SrcLine> lines, int i, ListMarker first, Block parent, out bool trailing_blank) {
            int n = (int) lines.length;
            var list = new Block (BlockKind.LIST);
            list.ordered = first.ordered;
            list.start = first.number;
            list.line = lines[i].num;

            int j = i;
            bool gap = false;
            while (j < n) {
                ListMarker m;
                if (!match_list_marker (lines[j].text, out m) || m.ordered != first.ordered || m.delim != first.delim) {
                    break;
                }
                if (j > i && is_thematic_break (lines[j].text.chug ())) {
                    break;
                }
                if (gap) {
                    list.tight = false;
                }

                var item_lines = new GenericArray<SrcLine> ();
                item_lines.add (new SrcLine (m.content, lines[j].num));
                bool starts_blank = is_blank (m.content);
                bool prev_blank = starts_blank;
                int k = j + 1;
                while (k < n) {
                    string l = lines[k].text;
                    if (is_blank (l)) {
                        // An item may start with at most one blank line.
                        if (starts_blank && item_lines.length == 1) {
                            break;
                        }
                        item_lines.add (new SrcLine ("", lines[k].num));
                        prev_blank = true;
                        k++;
                        continue;
                    }
                    if (indent_of (l) >= m.width) {
                        item_lines.add (new SrcLine (l.substring (m.width), lines[k].num));
                        prev_blank = false;
                        k++;
                        continue;
                    }
                    ListMarker sibling;
                    if (match_list_marker (l, out sibling)) {
                        break;
                    }
                    if (!prev_blank && !starts_block (l) && !(k + 1 < n && is_table_start (l, lines[k + 1].text))) {
                        // Lazy continuation line.
                        item_lines.add (new SrcLine (l.chug (), lines[k].num));
                        k++;
                        continue;
                    }
                    break;
                }

                int trailing = 0;
                while (item_lines.length > 1 && is_blank (item_lines[item_lines.length - 1].text)) {
                    item_lines.remove_index (item_lines.length - 1);
                    trailing++;
                }
                gap = trailing > 0;

                var item = new Block (BlockKind.ITEM);
                item.line = lines[j].num;
                string head = item_lines[0].text;
                if (head.length >= 3 && head[0] == '[' && head[2] == ']'
                    && (head[1] == ' ' || head[1] == 'x' || head[1] == 'X')
                    && (head.length == 3 || head[3] == ' ')) {
                    item.task = true;
                    item.checked = head[1] != ' ';
                    item_lines[0].text = head.length > 4 ? head.substring (4) : "";
                }
                if (parse_lines (item_lines, item)) {
                    list.tight = false;
                }
                list.add (item);
                j = k;
            }

            parent.add (list);
            trailing_blank = gap;
            return j;
        }

        int parse_table (GenericArray<SrcLine> lines, int i, Block parent) {
            int n = (int) lines.length;
            string[] header = split_row (lines[i].text);
            string[] delims = split_row (lines[i + 1].text);

            var table = new Block (BlockKind.TABLE);
            table.line = lines[i].num;
            var aligns = new Align[header.length];
            for (int k = 0; k < header.length; k++) {
                string d = delims[k];
                bool left = d.has_prefix (":");
                bool right = d.has_suffix (":");
                aligns[k] = left && right ? Align.CENTER : right ? Align.RIGHT : left ? Align.LEFT : Align.NONE;
            }
            table.aligns = aligns;

            add_row (table, header, true);
            int j = i + 2;
            while (j < n) {
                string l = lines[j].text;
                if (is_blank (l) || starts_block (l) || !l.contains ("|")) {
                    break;
                }
                add_row (table, split_row (l), false);
                j++;
            }
            parent.add (table);
            return j;
        }

        static void add_row (Block table, string[] cells, bool header) {
            var row = new Block (BlockKind.TABLE_ROW);
            row.header = header;
            for (int k = 0; k < table.aligns.length; k++) {
                var cell = new Block (BlockKind.TABLE_CELL);
                cell.raw = k < cells.length ? cells[k] : "";
                cell.align = table.aligns[k];
                row.add (cell);
            }
            table.add (row);
        }

        /* Handles the block-level HTML subset. Returns the number of lines
         * consumed, or 0 to let the line be parsed as an ordinary paragraph
         * (where unknown tags are dropped and their text is kept). */
        int parse_html_block (GenericArray<SrcLine> lines, int i, Block parent) {
            int n = (int) lines.length;
            string t = lines[i].text.strip ();
            MatchInfo mi;
            if (!/^<(\/?)([a-zA-Z][a-zA-Z0-9]*)((?:\s[^>]*)?)\/?>/.match (t, 0, out mi)) {
                return 0;
            }
            bool closing = mi.fetch (1) == "/";
            string tag = mi.fetch (2).down ();
            string attrs = mi.fetch (3) ?? "";
            int ms, me;
            mi.fetch_pos (0, out ms, out me);
            string rest = t.substring (me);

            switch (tag) {
            case "p":
            case "div":
            case "center":
            case "details":
            case "section":
            case "figure":
                if (closing) {
                    return 1;  // stray closing tag
                }
                break;
            case "hr":
                parent.add (new Block (BlockKind.RULE));
                return 1;
            case "br":
                if (!is_blank (rest)) {
                    return 0;
                }
                parent.add (new Block (BlockKind.SPACER));
                return 1;
            case "h1":
            case "h2":
            case "h3":
            case "h4":
            case "h5":
            case "h6":
                if (closing) {
                    return 1;
                }
                int ci = rest.down ().index_of ("</" + tag);
                if (ci < 0) {
                    return 0;
                }
                var h = new Block (BlockKind.HEADING);
                h.level = tag[1] - '0';
                h.raw = rest.substring (0, ci).strip ();
                h.align = parse_align (attrs);
                h.line = lines[i].num;
                parent.add (h);
                return 1;
            default:
                return 0;
            }

            // A container: collect everything up to the matching closing tag.
            Regex open_re, close_re;
            try {
                open_re = new Regex ("<" + tag + "(\\s[^>]*)?>", RegexCompileFlags.CASELESS);
                close_re = new Regex ("</" + tag + "\\s*>", RegexCompileFlags.CASELESS);
            } catch (RegexError e) {
                return 0;
            }

            var inner = new GenericArray<SrcLine> ();
            int depth = 1;
            int j = i;
            string seg = rest;
            while (true) {
                int close_at = -1;
                int pos = 0;
                while (pos <= seg.length) {
                    MatchInfo om, cm;
                    int os = -1, oe = -1, cs = -1, ce = -1;
                    try {
                        if (open_re.match_full (seg, -1, pos, 0, out om)) {
                            om.fetch_pos (0, out os, out oe);
                        }
                        if (close_re.match_full (seg, -1, pos, 0, out cm)) {
                            cm.fetch_pos (0, out cs, out ce);
                        }
                    } catch (RegexError e) {
                        break;
                    }
                    if (cs < 0) {
                        if (os >= 0) {
                            depth++;
                        }
                        break;
                    }
                    if (os >= 0 && os < cs) {
                        depth++;
                        pos = oe;
                        continue;
                    }
                    depth--;
                    if (depth == 0) {
                        close_at = cs;
                        break;
                    }
                    pos = ce;
                }

                if (close_at >= 0) {
                    string before = seg.substring (0, close_at);
                    if (!is_blank (before)) {
                        inner.add (new SrcLine (before, lines[j].num));
                    }
                    j++;
                    break;
                }
                if (j > i || !is_blank (seg)) {
                    inner.add (new SrcLine (seg, lines[j].num));
                }
                j++;
                if (j >= n) {
                    return 0;  // never closed: treat the tag as plain text
                }
                seg = lines[j].text;
            }

            // Content inside HTML is commonly indented; that is not a code block.
            int common = int.MAX;
            for (int k = 0; k < inner.length; k++) {
                if (!is_blank (inner[k].text)) {
                    common = int.min (common, indent_of (inner[k].text));
                }
            }
            if (common != int.MAX && common > 0) {
                for (int k = 0; k < inner.length; k++) {
                    string l = inner[k].text;
                    inner[k].text = l.length >= common ? l.substring (common) : "";
                }
            }

            if (tag == "details") {
                var d = new Block (BlockKind.DETAILS);
                d.open = /\bopen\b/i.match (attrs);
                d.line = lines[i].num;
                extract_summary (inner, d);
                parse_lines (inner, d);
                parent.add (d);
            } else {
                var c = new Block (BlockKind.CONTAINER);
                c.align = tag == "center" ? Align.CENTER : parse_align (attrs);
                c.line = lines[i].num;
                parse_lines (inner, c);
                parent.add (c);
            }
            return j - i;
        }

        static void extract_summary (GenericArray<SrcLine> inner, Block details) {
            for (int k = 0; k < inner.length; k++) {
                string l = inner[k].text;
                MatchInfo mi;
                if (!/<summary[^>]*>/i.match (l, 0, out mi)) {
                    continue;
                }
                int s, e;
                mi.fetch_pos (0, out s, out e);
                string prefix = l.substring (0, s);
                var sb = new StringBuilder ();
                string tail = l.substring (e);
                int k2 = k;
                string suffix = "";
                while (true) {
                    int ci = tail.down ().index_of ("</summary>");
                    if (ci >= 0) {
                        sb.append (tail.substring (0, ci));
                        suffix = tail.substring (ci + 10);
                        break;
                    }
                    sb.append (tail);
                    sb.append_c (' ');
                    k2++;
                    if (k2 >= inner.length) {
                        k2--;
                        break;
                    }
                    tail = inner[k2].text;
                }
                details.summary = sb.str.strip ();
                if (k2 == k) {
                    inner[k].text = prefix + suffix;
                } else {
                    inner[k].text = prefix;
                    for (int x = k + 1; x < k2; x++) {
                        inner[x].text = "";
                    }
                    inner[k2].text = suffix;
                }
                return;
            }
        }

        /* ---- Inline pass ---- */

        void resolve_inlines (Block b) {
            switch (b.kind) {
            case BlockKind.PARAGRAPH:
            case BlockKind.HEADING:
            case BlockKind.TABLE_CELL:
                b.inlines = new InlineParser (b.raw, refs).parse ();
                break;
            case BlockKind.DETAILS:
                b.summary_inlines = new InlineParser (b.summary != "" ? b.summary : "Details", refs).parse ();
                break;
            default:
                break;
            }
            for (int k = 0; k < b.children.length; k++) {
                resolve_inlines (b.children[k]);
            }
        }
    }
}
