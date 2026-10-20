/* SPDX-License-Identifier: GPL-3.0-or-later */

namespace Mermaid {

    /* Measures text for the layout. The GTK part implements it with Pango. */
    public interface TextMeasurer : Object {
        /*
         * The size of `markup` (see Text) in the given style. With a positive
         * wrap_width, lines longer than that wrap.
         */
        public abstract void measure (string markup, TextStyle style, double wrap_width,
                                      out double width, out double height);
    }

    /*
     * A measurer with fixed character widths, so that layouts are the same on
     * every machine. Used by the tests.
     */
    public class FixedMeasurer : Object, TextMeasurer {
        public void measure (string markup, TextStyle style, double wrap_width,
                             out double width, out double height) {
            string plain = Label.strip_markup (markup);
            double char_width = style.size * (style.monospace ? 0.6 : 0.55);
            double line_height = style.size * 1.25;
            width = 0;
            int lines = 0;
            foreach (unowned string line in plain.split ("\n")) {
                double w = line.char_count () * char_width;
                if (style.bold) {
                    w *= 1.1;
                }
                int count = 1;
                if (wrap_width > 0 && w > wrap_width) {
                    count = (int) Math.ceil (w / wrap_width);
                    w = wrap_width;
                }
                width = double.max (width, w);
                lines += count;
            }
            height = lines * line_height;
        }
    }

    /* Mermaid's default font size; the scene is in pixels at this size. */
    public const double FONT_SIZE = 16;

    /* Turning label text from diagram sources into Text markup. */
    namespace Label {

        public string escape (string text) {
            return Markup.escape_text (text);
        }

        /* The text of `markup`, without tags. */
        public string strip_markup (string markup) {
            string plain = strip_tags (markup);
            if (!plain.contains ("&")) {
                return plain;
            }
            return plain.replace ("&lt;", "<").replace ("&gt;", ">").replace ("&quot;", "\"")
                .replace ("&apos;", "'").replace ("&#39;", "'").replace ("&amp;", "&");
        }

        /*
         * Mermaid's entity codes: "#quot;", "#35;" or "#9829;" stand for
         * characters that the syntax would otherwise take.
         */
        string decode_entities (string text) {
            if (!text.contains ("#") && !text.contains ("&")) {
                return text;
            }
            try {
                var re = /[#&](#?)([a-zA-Z]+|x[0-9a-fA-F]+|[0-9]+);/;
                return re.replace_eval (text, -1, 0, 0, (info, res) => {
                    string name = info.fetch (2);
                    unichar c = 0;
                    if (name[0].isdigit ()) {
                        c = (unichar) int.parse (name);
                    } else if (name[0] == 'x' && name.length > 1 && name[1].isxdigit ()) {
                        c = (unichar) ulong.parse (name.substring (1), 16);
                    } else {
                        switch (name) {
                        case "quot": c = '"'; break;
                        case "amp": c = '&'; break;
                        case "lt": c = '<'; break;
                        case "gt": c = '>'; break;
                        case "apos": c = '\''; break;
                        case "nbsp": c = 0xa0; break;
                        case "hash": c = '#'; break;
                        case "semi": c = ';'; break;
                        }
                    }
                    if (c != 0 && c.validate ()) {
                        res.append_unichar (c);
                    } else {
                        res.append (info.fetch (0));
                    }
                    return false;
                });
            } catch (RegexError e) {
                return text;
            }
        }

        /*
         * A plain label: "<br>" breaks lines, and the inline tags b, strong,
         * i, em, s, del, code and u keep their meaning. Other tags are
         * dropped but their text is kept.
         */
        public string from_text (string text) {
            var sb = new StringBuilder ();
            int i = 0;
            while (i < text.length) {
                if (text[i] == '<') {
                    int end = text.index_of_char ('>', i);
                    if (end > i) {
                        string tag = text.substring (i + 1, end - i - 1).strip ().down ();
                        bool closing = tag.has_prefix ("/");
                        if (closing) {
                            tag = tag.substring (1).strip ();
                        }
                        string name = tag.split (" ")[0].replace ("/", "");
                        string? pango = null;
                        switch (name) {
                        case "br":
                            sb.append_c ('\n');
                            i = end + 1;
                            continue;
                        case "b":
                        case "strong":
                            pango = "b";
                            break;
                        case "i":
                        case "em":
                            pango = "i";
                            break;
                        case "s":
                        case "del":
                        case "strike":
                            pango = "s";
                            break;
                        case "u":
                            pango = "u";
                            break;
                        case "code":
                        case "tt":
                            pango = "tt";
                            break;
                        case "sub":
                        case "sup":
                            pango = name;
                            break;
                        }
                        if (name.length > 0 && (name[0].isalpha () || closing)) {
                            if (pango != null) {
                                sb.append_printf (closing ? "</%s>" : "<%s>", pango);
                            }
                            i = end + 1;
                            continue;
                        }
                    }
                }
                int next = text.index_of_char ('<', i + 1);
                if (next < 0) {
                    next = text.length;
                }
                sb.append (escape (decode_entities (text.substring (i, next - i))));
                i = next;
            }
            return balance (sb.str);
        }

        /*
         * A Markdown string (in "`...`" quotes): **bold**, *italic* or
         * _italic_, and line breaks are kept.
         */
        public string from_markdown (string text) {
            var sb = new StringBuilder ();
            bool bold = false, italic = false;
            string src = text.strip ();
            int i = 0;
            while (i < src.length) {
                char c = src[i];
                if ((c == '*' || c == '_') && i + 1 < src.length && src[i + 1] == c) {
                    sb.append (bold ? "</b>" : "<b>");
                    bold = !bold;
                    i += 2;
                    continue;
                }
                if (c == '*' || c == '_') {
                    sb.append (italic ? "</i>" : "<i>");
                    italic = !italic;
                    i++;
                    continue;
                }
                if (c == '\n') {
                    // Lines are joined into paragraphs; a blank line breaks them.
                    int j = i + 1;
                    while (j < src.length && (src[j] == ' ' || src[j] == '\t')) {
                        j++;
                    }
                    if (j < src.length && src[j] == '\n') {
                        sb.append ("\n");
                        i = j + 1;
                    } else {
                        sb.append ("\n");
                        i = j;
                    }
                    continue;
                }
                int next = i + 1;
                while (next < src.length && src[next] != '*' && src[next] != '_' && src[next] != '\n') {
                    next++;
                }
                sb.append (escape (decode_entities (src.substring (i, next - i))));
                i = next;
            }
            if (italic) {
                sb.append ("</i>");
            }
            if (bold) {
                sb.append ("</b>");
            }
            return balance (sb.str);
        }

        /* Fixes up unbalanced tags so that the markup always parses. */
        string balance (string markup) {
            MarkupParser parser = { null, null, null, null, null };
            var context = new MarkupParseContext (parser, 0, null, null);
            try {
                context.parse ("<m>" + markup + "</m>", -1);
                context.end_parse ();
                return markup;
            } catch (MarkupError e) {
                return escape (strip_markup (markup));
            }
        }

        string strip_tags (string markup) {
            try {
                return /<[^>]*>/.replace (markup, -1, 0, "");
            } catch (RegexError e) {
                return markup;
            }
        }

        /* A label from the source, `markdown` for "`...`" strings. */
        public string parse (string text, bool markdown = false) {
            return markdown ? from_markdown (text) : from_text (text);
        }
    }

    /* Measures and keeps a label's size. */
    internal struct Size {
        public double width;
        public double height;
    }

    internal Size measure (TextMeasurer m, string markup, TextStyle style, double wrap_width = 0) {
        double w, h;
        if (markup == "") {
            return Size () { width = 0, height = 0 };
        }
        m.measure (markup, style, wrap_width, out w, out h);
        return Size () { width = w, height = h };
    }
}
