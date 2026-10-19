/* Inline Markdown parser: emphasis, code spans, links, images, autolinks,
 * entities, and a small subset of inline HTML.
 *
 * Emphasis and links use the CommonMark delimiter/bracket stack algorithm.
 * Inline HTML tags are first recorded as open/close markers and then folded
 * into proper container nodes, so the renderer always gets a well-nested tree.
 */

namespace Markdown {

    class Delim {
        public Inline node;
        public char ch;
        public int count;
        public int orig;
        public bool can_open;
        public bool can_close;
        public Delim? prev;
        public unowned Delim? next;
    }

    class Bracket {
        public Inline node;
        public bool image;
        public bool active = true;
        public Delim? prev_delim;
        public Bracket? prev;
        public int pos;
    }

    public class InlineParser {
        string src;
        int n;
        unowned HashTable<string, LinkRef> refs;

        Inline root;
        StringBuilder buf = new StringBuilder ();
        Delim? last_delim;
        Bracket? brackets;

        static HashTable<string, string>? entities;

        public InlineParser (string src, HashTable<string, LinkRef> refs) {
            this.src = src.strip ();
            this.n = this.src.length;
            this.refs = refs;
        }

        public Inline parse () {
            root = new Inline (InlineKind.ROOT);
            int i = 0;
            while (i < n) {
                char c = src[i];
                switch (c) {
                case '\n':
                    handle_newline ();
                    i++;
                    while (i < n && src[i] == ' ') {
                        i++;
                    }
                    break;
                case '\\':
                    i = parse_backslash (i);
                    break;
                case '`':
                    i = parse_code (i);
                    break;
                case '*':
                case '_':
                case '~':
                    i = parse_delim (i, c);
                    break;
                case '[':
                    flush ();
                    push_bracket (i, false);
                    i++;
                    break;
                case '!':
                    if (i + 1 < n && src[i + 1] == '[') {
                        flush ();
                        push_bracket (i, true);
                        i += 2;
                    } else {
                        buf.append_c ('!');
                        i++;
                    }
                    break;
                case ']':
                    i = parse_close_bracket (i);
                    break;
                case '<':
                    i = parse_lt (i);
                    break;
                case '&':
                    i = parse_entity (i);
                    break;
                default:
                    if ((c == 'h' || c == 'w') && at_word_start (i)) {
                        int e = parse_bare_url (i);
                        if (e > i) {
                            i = e;
                            break;
                        }
                    }
                    int j = i + 1;
                    while (j < n && !is_special (src[j]) && !((src[j] == 'h' || src[j] == 'w') && at_word_start (j))) {
                        j++;
                    }
                    buf.append (src.substring (i, j - i));
                    i = j;
                    break;
                }
            }
            flush ();
            process_emphasis (null);
            nest_html (root);
            return root;
        }

        /* ---- Character classes ---- */

        static bool is_special (char c) {
            return c == '\n' || c == '\\' || c == '`' || c == '*' || c == '_' || c == '~'
                || c == '[' || c == ']' || c == '!' || c == '<' || c == '&';
        }

        static bool is_ws (char c) {
            return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f';
        }

        static bool is_punct (char c) {
            return (c >= 33 && c <= 47) || (c >= 58 && c <= 64) || (c >= 91 && c <= 96) || (c >= 123 && c <= 126);
        }

        bool at_word_start (int i) {
            if (brackets != null) {
                return false;  // no bare autolinks inside link text
            }
            if (i == 0) {
                return true;
            }
            char p = src[i - 1];
            return is_ws (p) || p == '(' || p == '*' || p == '_' || p == '~';
        }

        static bool match_at (Regex re, string s, int pos, out MatchInfo mi) {
            try {
                return re.match_full (s, -1, pos, RegexMatchFlags.ANCHORED, out mi);
            } catch (RegexError e) {
                mi = null;
                return false;
            }
        }

        /* ---- Text accumulation ---- */

        void flush () {
            if (buf.len > 0) {
                root.append (new Inline (InlineKind.TEXT, buf.str));
                buf.truncate (0);
            }
        }

        void handle_newline () {
            int sp = 0;
            while (sp < buf.len && buf.str[buf.len - 1 - sp] == ' ') {
                sp++;
            }
            buf.truncate (buf.len - sp);
            flush ();
            root.append (new Inline (sp >= 2 ? InlineKind.HARDBREAK : InlineKind.SOFTBREAK));
        }

        int parse_backslash (int i) {
            if (i + 1 < n && src[i + 1] == '\n') {
                flush ();
                root.append (new Inline (InlineKind.HARDBREAK));
                i += 2;
                while (i < n && src[i] == ' ') {
                    i++;
                }
                return i;
            }
            if (i + 1 < n && is_punct (src[i + 1])) {
                buf.append_c (src[i + 1]);
                return i + 2;
            }
            buf.append_c ('\\');
            return i + 1;
        }

        int parse_code (int i) {
            int k = 0;
            while (i + k < n && src[i + k] == '`') {
                k++;
            }
            int j = i + k;
            while (j < n) {
                if (src[j] == '`') {
                    int m = 0;
                    while (j + m < n && src[j + m] == '`') {
                        m++;
                    }
                    if (m == k) {
                        string content = src.substring (i + k, j - i - k).replace ("\n", " ");
                        if (content.length >= 2 && content[0] == ' ' && content[content.length - 1] == ' '
                            && content.strip () != "") {
                            content = content.substring (1, content.length - 2);
                        }
                        flush ();
                        root.append (new Inline (InlineKind.CODE, content));
                        return j + k;
                    }
                    j += m;
                } else {
                    j++;
                }
            }
            buf.append (src.substring (i, k));
            return i + k;
        }

        /* ---- Emphasis ---- */

        int parse_delim (int i, char c) {
            int j = i;
            while (j < n && src[j] == c) {
                j++;
            }
            int count = j - i;
            if (c == '~' && count > 2) {
                buf.append (src.substring (i, count));
                return j;
            }

            char before = i > 0 ? src[i - 1] : '\n';
            char after = j < n ? src[j] : '\n';
            bool ws_before = is_ws (before), ws_after = is_ws (after);
            bool p_before = is_punct (before), p_after = is_punct (after);
            bool left = !ws_after && (!p_after || ws_before || p_before);
            bool right = !ws_before && (!p_before || ws_after || p_after);

            bool can_open, can_close;
            if (c == '_') {
                can_open = left && (!right || p_before);
                can_close = right && (!left || p_after);
            } else {
                can_open = left;
                can_close = right;
            }

            flush ();
            var node = new Inline (InlineKind.TEXT, src.substring (i, count));
            root.append (node);
            if (can_open || can_close) {
                var d = new Delim ();
                d.node = node;
                d.ch = c;
                d.count = count;
                d.orig = count;
                d.can_open = can_open;
                d.can_close = can_close;
                d.prev = last_delim;
                if (last_delim != null) {
                    last_delim.next = d;
                }
                last_delim = d;
            }
            return j;
        }

        void remove_delim (Delim d) {
            Delim keep = d;
            if (keep.next != null) {
                keep.next.prev = keep.prev;
            } else {
                last_delim = keep.prev;
            }
            if (keep.prev != null) {
                keep.prev.next = keep.next;
            }
        }

        void process_emphasis (Delim? stack_bottom) {
            unowned Delim? closer = last_delim;
            if (closer == stack_bottom) {
                closer = null;
            } else {
                while (closer != null && closer.prev != null && closer.prev != stack_bottom) {
                    closer = closer.prev;
                }
            }

            while (closer != null) {
                if (!closer.can_close) {
                    closer = closer.next;
                    continue;
                }

                unowned Delim? opener = closer.prev;
                bool found = false;
                while (opener != null && opener != stack_bottom) {
                    if (opener.ch == closer.ch && opener.can_open) {
                        bool blocked;
                        if (closer.ch == '~') {
                            blocked = opener.count != closer.count;
                        } else {
                            blocked = (opener.can_close || closer.can_open)
                                && (opener.orig + closer.orig) % 3 == 0
                                && !(opener.orig % 3 == 0 && closer.orig % 3 == 0);
                        }
                        if (!blocked) {
                            found = true;
                            break;
                        }
                    }
                    opener = opener.prev;
                }

                unowned Delim? next_closer = closer.next;
                if (!found) {
                    if (!closer.can_open) {
                        remove_delim (closer);
                    }
                    closer = next_closer;
                    continue;
                }

                int use;
                InlineKind kind;
                if (closer.ch == '~') {
                    use = closer.count;
                    kind = InlineKind.STRIKE;
                } else {
                    use = closer.count >= 2 && opener.count >= 2 ? 2 : 1;
                    kind = use == 2 ? InlineKind.STRONG : InlineKind.EMPH;
                }
                opener.count -= use;
                closer.count -= use;
                opener.node.text = opener.node.text.substring (0, opener.count);
                closer.node.text = closer.node.text.substring (0, closer.count);

                var wrapper = new Inline (kind);
                Inline? tmp = opener.node.next;
                while (tmp != null && tmp != closer.node) {
                    Inline? nx = tmp.next;
                    tmp.unlink ();
                    wrapper.append (tmp);
                    tmp = nx;
                }
                opener.node.insert_after (wrapper);

                // Delimiters between opener and closer can no longer match.
                unowned Delim? d = closer.prev;
                while (d != null && d != opener) {
                    unowned Delim? before = d.prev;
                    remove_delim (d);
                    d = before;
                }

                if (opener.count == 0) {
                    opener.node.unlink ();
                    remove_delim (opener);
                }
                if (closer.count == 0) {
                    closer.node.unlink ();
                    next_closer = closer.next;
                    remove_delim (closer);
                    closer = next_closer;
                }
            }

            while (last_delim != null && last_delim != stack_bottom) {
                remove_delim (last_delim);
            }
        }

        /* ---- Links and images ---- */

        void push_bracket (int i, bool image) {
            var node = new Inline (InlineKind.TEXT, image ? "![" : "[");
            root.append (node);
            var b = new Bracket ();
            b.node = node;
            b.image = image;
            b.prev_delim = last_delim;
            b.prev = brackets;
            b.pos = i + (image ? 2 : 1);
            brackets = b;
        }

        int parse_close_bracket (int i) {
            flush ();
            if (brackets == null) {
                buf.append_c (']');
                return i + 1;
            }
            Bracket opener = brackets;
            brackets = opener.prev;
            if (!opener.active) {
                buf.append_c (']');
                return i + 1;
            }

            string url = "", title = "";
            int end = i + 1;
            int after = i + 1;
            bool matched = after < n && src[after] == '(' && parse_link_tail (after, out url, out title, out end);

            if (!matched) {
                string label = src.substring (opener.pos, i - opener.pos);
                int e2 = after;
                if (after < n && src[after] == '[') {
                    int close = src.index_of_char (']', after + 1);
                    if (close > 0) {
                        string explicit_label = src.substring (after + 1, close - after - 1);
                        if (explicit_label.strip () != "") {
                            label = explicit_label;
                        }
                        e2 = close + 1;
                    }
                }
                var r = refs.lookup (Parser.normalize_label (label));
                if (r != null) {
                    url = r.url;
                    title = r.title;
                    end = e2;
                    matched = true;
                }
            }

            if (!matched) {
                buf.append_c (']');
                return i + 1;
            }

            var link = new Inline (opener.image ? InlineKind.IMAGE : InlineKind.LINK);
            link.url = url;
            link.title = title;
            Inline? tmp = opener.node.next;
            while (tmp != null) {
                Inline? nx = tmp.next;
                tmp.unlink ();
                link.append (tmp);
                tmp = nx;
            }
            opener.node.insert_after (link);
            opener.node.unlink ();
            process_emphasis (opener.prev_delim);

            // Links may not contain other links.
            if (!opener.image) {
                for (Bracket? b = brackets; b != null; b = b.prev) {
                    if (!b.image) {
                        b.active = false;
                    }
                }
            }
            return end;
        }

        bool parse_link_tail (int p, out string url, out string title, out int end) {
            url = "";
            title = "";
            end = p;
            int j = p + 1;
            while (j < n && is_ws (src[j])) {
                j++;
            }

            if (j < n && src[j] == '<') {
                int k = j + 1;
                while (k < n && src[k] != '>' && src[k] != '\n') {
                    k += src[k] == '\\' ? 2 : 1;
                }
                if (k >= n || src[k] != '>') {
                    return false;
                }
                url = src.substring (j + 1, k - j - 1);
                j = k + 1;
            } else {
                int depth = 0;
                int start = j;
                while (j < n) {
                    char c = src[j];
                    if (c == '\\' && j + 1 < n) {
                        j += 2;
                        continue;
                    }
                    if (c == '(') {
                        depth++;
                    } else if (c == ')') {
                        if (depth == 0) {
                            break;
                        }
                        depth--;
                    } else if (is_ws (c)) {
                        break;
                    }
                    j++;
                }
                if (j > n) {
                    return false;
                }
                url = src.substring (start, j - start);
            }

            int ws_start = j;
            while (j < n && is_ws (src[j])) {
                j++;
            }
            if (j < n && j > ws_start && (src[j] == '"' || src[j] == '\'' || src[j] == '(')) {
                char close = src[j] == '(' ? ')' : src[j];
                int k = j + 1;
                while (k < n && src[k] != close) {
                    k += src[k] == '\\' ? 2 : 1;
                }
                if (k >= n) {
                    return false;
                }
                title = src.substring (j + 1, k - j - 1);
                j = k + 1;
                while (j < n && is_ws (src[j])) {
                    j++;
                }
            }
            if (j >= n || src[j] != ')') {
                return false;
            }
            url = unescape (url);
            title = unescape (title);
            end = j + 1;
            return true;
        }

        /* Bare http(s):// and www. links (GitHub extension). */
        int parse_bare_url (int i) {
            MatchInfo mi;
            if (!match_at (/(?:https?:\/\/|www\.)[^\s<]+/, src, i, out mi)) {
                return i;
            }
            int s, e;
            mi.fetch_pos (0, out s, out e);
            string url = src.substring (i, e - i);
            while (url.length > 0) {
                char last = url[url.length - 1];
                if ("?!.,:*_~'\";".index_of_char (last) >= 0) {
                    url = url.substring (0, url.length - 1);
                    continue;
                }
                if (last == ')') {
                    int open = 0, close = 0;
                    for (int k = 0; k < url.length; k++) {
                        if (url[k] == '(') {
                            open++;
                        } else if (url[k] == ')') {
                            close++;
                        }
                    }
                    if (close > open) {
                        url = url.substring (0, url.length - 1);
                        continue;
                    }
                }
                break;
            }
            if (url == "www." || url.has_suffix ("://") || url.length == 0) {
                return i;
            }
            flush ();
            var link = new Inline (InlineKind.LINK);
            link.url = url.has_prefix ("www.") ? "https://" + url : url;
            link.append (new Inline (InlineKind.TEXT, url));
            root.append (link);
            return i + url.length;
        }

        /* ---- HTML and autolinks ---- */

        int parse_lt (int i) {
            MatchInfo mi;
            int s, e;

            if (match_at (/<([a-zA-Z][a-zA-Z0-9+.\-]{1,31}:[^\s<>]*)>/, src, i, out mi)) {
                mi.fetch_pos (0, out s, out e);
                add_autolink (mi.fetch (1), mi.fetch (1));
                return e;
            }
            if (match_at (/<([a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~\-]+@[a-zA-Z0-9](?:[a-zA-Z0-9\-]*[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9\-]*[a-zA-Z0-9])?)*)>/, src, i, out mi)) {
                mi.fetch_pos (0, out s, out e);
                add_autolink ("mailto:" + mi.fetch (1), mi.fetch (1));
                return e;
            }
            if (match_at (/<!--.*?-->/s, src, i, out mi)) {
                mi.fetch_pos (0, out s, out e);
                return e;  // comments are hidden
            }
            if (match_at (/<([a-zA-Z][a-zA-Z0-9\-]*)((?:\s+[a-zA-Z_:][a-zA-Z0-9_.:\-]*(?:\s*=\s*(?:[^\s"'=<>`]+|'[^']*'|"[^"]*"))?)*)\s*\/?>/s, src, i, out mi)) {
                mi.fetch_pos (0, out s, out e);
                flush ();
                handle_open_tag (mi.fetch (1).down (), mi.fetch (2) ?? "");
                return e;
            }
            if (match_at (/<\/([a-zA-Z][a-zA-Z0-9\-]*)\s*>/, src, i, out mi)) {
                mi.fetch_pos (0, out s, out e);
                string name = mi.fetch (1).down ();
                if (container_kind (name) != InlineKind.ROOT) {
                    flush ();
                    root.append (new Inline (InlineKind.HTML_CLOSE, name));
                }
                return e;
            }
            buf.append_c ('<');
            return i + 1;
        }

        void add_autolink (string url, string text) {
            flush ();
            var link = new Inline (InlineKind.LINK);
            link.url = url;
            link.append (new Inline (InlineKind.TEXT, text));
            root.append (link);
        }

        void handle_open_tag (string name, string attr_src) {
            var attrs = parse_attrs (attr_src);
            switch (name) {
            case "br":
                root.append (new Inline (InlineKind.HARDBREAK));
                return;
            case "img":
                var img = new Inline (InlineKind.IMAGE);
                img.url = attrs.lookup ("src") ?? "";
                img.title = attrs.lookup ("title") ?? "";
                string alt = attrs.lookup ("alt") ?? "";
                if (alt != "") {
                    img.append (new Inline (InlineKind.TEXT, alt));
                }
                string? width = attrs.lookup ("width");
                if (width != null && !width.contains ("%")) {
                    img.width = int.parse (width);
                }
                root.append (img);
                return;
            default:
                if (container_kind (name) != InlineKind.ROOT) {
                    var marker = new Inline (InlineKind.HTML_OPEN, name);
                    marker.url = attrs.lookup ("href") ?? "";
                    marker.title = attrs.lookup ("title") ?? "";
                    root.append (marker);
                }
                // Anything else is dropped; its text content stays.
                return;
            }
        }

        static HashTable<string, string> parse_attrs (string s) {
            var attrs = new HashTable<string, string> (str_hash, str_equal);
            MatchInfo mi;
            try {
                if (/([a-zA-Z_:][a-zA-Z0-9_.:\-]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/.match (s, 0, out mi)) {
                    do {
                        string name = mi.fetch (1).down ();
                        string val = "";
                        for (int g = 2; g <= 4; g++) {
                            string? v = mi.fetch (g);
                            if (v != null && v != "") {
                                val = v;
                                break;
                            }
                        }
                        attrs.insert (name, decode_entities (val));
                    } while (mi.next ());
                }
            } catch (RegexError e) {
            }
            return attrs;
        }

        /* Maps a supported inline HTML tag to its node kind; ROOT means unsupported. */
        static InlineKind container_kind (string tag) {
            switch (tag) {
            case "b":
            case "strong":
                return InlineKind.STRONG;
            case "i":
            case "em":
            case "cite":
            case "var":
                return InlineKind.EMPH;
            case "u":
            case "ins":
                return InlineKind.UNDERLINE;
            case "s":
            case "del":
            case "strike":
                return InlineKind.STRIKE;
            case "code":
            case "tt":
            case "samp":
                return InlineKind.MONO;
            case "kbd":
                return InlineKind.KBD;
            case "mark":
                return InlineKind.MARK;
            case "sub":
                return InlineKind.SUB;
            case "sup":
                return InlineKind.SUP;
            case "small":
                return InlineKind.SMALL;
            case "a":
                return InlineKind.LINK;
            default:
                return InlineKind.ROOT;
            }
        }

        /* Turns flat HTML_OPEN/HTML_CLOSE markers into nested container nodes. */
        static void nest_html (Inline container) {
            var items = new GenericArray<Inline> ();
            bool has_html = false;
            for (Inline? c = container.first; c != null; c = c.next) {
                items.add (c);
                if (c.kind == InlineKind.HTML_OPEN || c.kind == InlineKind.HTML_CLOSE) {
                    has_html = true;
                } else if (c.first != null) {
                    nest_html (c);
                }
            }
            if (!has_html) {
                return;
            }

            for (int k = 0; k < items.length; k++) {
                items[k].unlink ();
            }
            var open_nodes = new GenericArray<Inline> ();
            var open_tags = new GenericArray<string> ();
            for (int k = 0; k < items.length; k++) {
                Inline it = items[k];
                Inline target = open_nodes.length > 0 ? open_nodes[open_nodes.length - 1] : container;
                if (it.kind == InlineKind.HTML_OPEN) {
                    var node = new Inline (container_kind (it.text));
                    node.url = it.url;
                    node.title = it.title;
                    target.append (node);
                    open_nodes.add (node);
                    open_tags.add (it.text);
                } else if (it.kind == InlineKind.HTML_CLOSE) {
                    int idx = (int) open_tags.length - 1;
                    while (idx >= 0 && open_tags[idx] != it.text) {
                        idx--;
                    }
                    if (idx >= 0) {
                        open_nodes.remove_range (idx, open_nodes.length - idx);
                        open_tags.remove_range (idx, open_tags.length - idx);
                    }
                } else {
                    target.append (it);
                }
            }
        }

        /* ---- Entities and escapes ---- */

        int parse_entity (int i) {
            MatchInfo mi;
            if (match_at (/&(?:#[xX][0-9a-fA-F]{1,6}|#[0-9]{1,7}|[a-zA-Z][a-zA-Z0-9]{1,31});/, src, i, out mi)) {
                int s, e;
                mi.fetch_pos (0, out s, out e);
                string? decoded = decode_entity (src.substring (i, e - i));
                if (decoded != null) {
                    buf.append (decoded);
                    return e;
                }
            }
            buf.append_c ('&');
            return i + 1;
        }

        static string? decode_entity (string ent) {
            string body = ent.substring (1, ent.length - 2);
            if (body[0] == '#') {
                uint cp = 0;
                if (body[1] == 'x' || body[1] == 'X') {
                    for (int k = 2; k < body.length; k++) {
                        char c = body[k];
                        cp = cp * 16 + (c.isdigit () ? c - '0' : c.tolower () - 'a' + 10);
                    }
                } else {
                    cp = (uint) int.parse (body.substring (1));
                }
                if (cp == 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
                    cp = 0xFFFD;
                }
                return ((unichar) cp).to_string ();
            }

            if (entities == null) {
                entities = new HashTable<string, string> (str_hash, str_equal);
                string[] table = {
                    "amp", "&", "lt", "<", "gt", ">", "quot", "\"", "apos", "'", "nbsp", " ",
                    "copy", "©", "reg", "®", "trade", "™", "hellip", "…", "mdash", "—", "ndash", "–",
                    "laquo", "«", "raquo", "»", "ldquo", "“", "rdquo", "”", "lsquo", "‘", "rsquo", "’",
                    "bull", "•", "middot", "·", "deg", "°", "plusmn", "±", "times", "×", "divide", "÷",
                    "euro", "€", "pound", "£", "yen", "¥", "cent", "¢", "sect", "§", "para", "¶",
                    "larr", "←", "rarr", "→", "uarr", "↑", "darr", "↓", "harr", "↔", "check", "✓",
                    "hearts", "♥", "star", "☆", "frac12", "½", "frac14", "¼", "frac34", "¾",
                    "ensp", " ", "emsp", " ", "thinsp", " ", "zwj", "‍", "zwnj", "‌",
                };
                for (int k = 0; k + 1 < table.length; k += 2) {
                    entities.insert (table[k], table[k + 1]);
                }
            }
            return entities.lookup (body);
        }

        internal static string decode_entities (string s) {
            if (s.index_of_char ('&') < 0) {
                return s;
            }
            try {
                return /&(?:#[xX][0-9a-fA-F]{1,6}|#[0-9]{1,7}|[a-zA-Z][a-zA-Z0-9]{1,31});/.replace_eval (s, -1, 0, 0, (mi, result) => {
                    string ent = mi.fetch (0);
                    result.append (decode_entity (ent) ?? ent);
                    return false;
                });
            } catch (RegexError e) {
                return s;
            }
        }

        static string unescape (string s) {
            var sb = new StringBuilder ();
            for (int k = 0; k < s.length; k++) {
                if (s[k] == '\\' && k + 1 < s.length && is_punct (s[k + 1])) {
                    k++;
                }
                sb.append_c (s[k]);
            }
            return decode_entities (sb.str);
        }
    }
}
