/* SPDX-License-Identifier: GPL-3.0-or-later */

namespace Mermaid {

    public errordomain ParseError {
        /* The source is not valid for its diagram type. */
        SYNTAX,
        /* A diagram type, or a feature of one, that isn't supported yet. */
        UNSUPPORTED,
        /* The source has no diagram. */
        EMPTY
    }

    /* A parsed diagram, ready to be laid out. */
    public abstract class Diagram : Object {
        /* "flowchart", "sequence", "pie", "state", "class" or "er". */
        public abstract string kind { get; }
        public string? title { get; set; }
        public string? accessible_title { get; set; }
        public string? accessible_description { get; set; }

        /* Space around the diagram, as in Mermaid. */
        public const double PADDING = 8;

        Scene? cached_scene;
        string? cached_key;

        /*
         * Like layout (), but keeps the result for the next call with the
         * same key, which names the measurer's font.
         */
        public Scene layout_cached (TextMeasurer measurer, string key) {
            if (cached_scene == null || cached_key != key) {
                cached_scene = layout (measurer);
                cached_key = key;
            }
            return cached_scene;
        }

        /* Lays out the diagram; the scene starts at (0, 0). */
        internal abstract Scene build (TextMeasurer measurer);

        /* Lays out the diagram with its title and padding. */
        public Scene layout (TextMeasurer measurer) {
            var scene = build (measurer);
            scene.fit_shapes (PADDING);
            scene.title = title;
            if (title != null && title != "" && !draws_own_title ()) {
                var style = TextStyle (FONT_SIZE * 1.125, true);
                string markup = Label.escape (title);
                var size = measure (measurer, markup, style);
                double gap = size.height + PADDING * 2;
                scene.translate (0, gap);
                double width = double.max (scene.width, size.width + PADDING * 2);
                if (width > scene.width) {
                    scene.translate ((width - scene.width) / 2, 0);
                    scene.width = width;
                }
                scene.add_text (markup, scene.width / 2, PADDING + size.height / 2, style);
                scene.height += gap;
            }
            return scene;
        }

        /* Whether build () already draws the title, as the pie chart does. */
        internal virtual bool draws_own_title () {
            return false;
        }
    }

    /*
     * The source split into lines, with front matter, directives and comments
     * blanked out so that line numbers still match.
     */
    internal class Source {
        public string[] lines;
        public string? title;

        public Source (string text) {
            lines = text.replace ("\r\n", "\n").replace ("\t", "    ").split ("\n");
            int first = 0;
            while (first < lines.length && lines[first].strip () == "") {
                first++;
            }
            // YAML front matter; only the title is used.
            if (first < lines.length && lines[first].strip () == "---") {
                int end = first + 1;
                while (end < lines.length && lines[end].strip () != "---") {
                    end++;
                }
                if (end < lines.length) {
                    for (int i = first; i <= end; i++) {
                        string l = lines[i];
                        if (l.has_prefix ("title:")) {
                            title = unquote (l.substring (6).strip ());
                        }
                        lines[i] = "";
                    }
                }
            }
            bool in_directive = false;
            for (int i = 0; i < lines.length; i++) {
                string l = lines[i].strip ();
                if (in_directive) {
                    if (l.contains ("}%%")) {
                        in_directive = false;
                    }
                    lines[i] = "";
                } else if (l.has_prefix ("%%{")) {
                    in_directive = !l.contains ("}%%");
                    lines[i] = "";
                } else if (l.has_prefix ("%%")) {
                    lines[i] = "";
                }
            }
        }

        /* The index of the first line with content, or -1. */
        public int first_line () {
            for (int i = 0; i < lines.length; i++) {
                if (lines[i].strip () != "") {
                    return i;
                }
            }
            return -1;
        }

        public string joined (int from) {
            var sb = new StringBuilder ();
            for (int i = from; i < lines.length; i++) {
                sb.append (lines[i]);
                sb.append_c ('\n');
            }
            return sb.str;
        }
    }

    internal string unquote (string s) {
        if (s.length >= 2 && ((s[0] == '"' && s[s.length - 1] == '"') || (s[0] == '\'' && s[s.length - 1] == '\''))) {
            return s.substring (1, s.length - 2);
        }
        return s;
    }

    internal ParseError syntax_error (int line, string message) {
        return new ParseError.SYNTAX ("Line %d: %s".printf (line + 1, message));
    }

    /*
     * Accessibility and title statements that most diagram types share:
     * "title …", "accTitle: …" and "accDescr: …" or "accDescr { … }".
     * Returns true when the line was one of them; multi-line descriptions
     * advance `i` to their last line.
     */
    internal bool common_statement (Source src, ref int i, Diagram d, bool allow_title = true) {
        string l = src.lines[i].strip ();
        if (allow_title && (l == "title" || l.has_prefix ("title ") || l.has_prefix ("title\t"))) {
            d.title = l.substring (5).strip ();
            return true;
        }
        if (l.has_prefix ("accTitle")) {
            string rest = l.substring (8).strip ();
            if (rest.has_prefix (":")) {
                d.accessible_title = rest.substring (1).strip ();
                return true;
            }
        }
        if (l.has_prefix ("accDescr")) {
            string rest = l.substring (8).strip ();
            if (rest.has_prefix (":")) {
                d.accessible_description = rest.substring (1).strip ();
                return true;
            }
            if (rest.has_prefix ("{")) {
                var sb = new StringBuilder (rest.substring (1));
                while (!sb.str.contains ("}") && i + 1 < src.lines.length) {
                    i++;
                    sb.append_c ('\n');
                    sb.append (src.lines[i].strip ());
                }
                string text = sb.str;
                int close = text.index_of_char ('}');
                d.accessible_description = (close >= 0 ? text.substring (0, close) : text).strip ();
                return true;
            }
        }
        return false;
    }
}
