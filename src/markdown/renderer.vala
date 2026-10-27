/* Renders a Markdown document tree into native GTK widgets.
 *
 * Text blocks become Gtk.Labels with Pango markup, code blocks become
 * read-only GtkSourceViews with syntax highlighting, tables become grids, and
 * images are decoded with GDK. No web engine involved.
 */

namespace Markdown {

    public class Renderer : Object {
        public signal void link_activated (string uri);
        public signal void task_toggled (int line, bool active);

        public File? base_dir { get; set; }
        public bool dark { get; set; }
        public bool read_only { get; set; }
        public string highlight { get; set; default = ""; }

        public int match_count { get; private set; }
        public GenericArray<Gtk.Widget> match_widgets = new GenericArray<Gtk.Widget> ();

        /* The selectable text of the note, in reading order. */
        public GenericArray<Notes.TextSegment> segments = new GenericArray<Notes.TextSegment> ();

        HashTable<string, Gtk.Widget> anchors = new HashTable<string, Gtk.Widget> (str_hash, str_equal);
        HashTable<string, int> slug_counts = new HashTable<string, int> (str_hash, str_equal);
        Regex? highlight_re;
        bool label_matched;

        /* How copied text joins the next segment to the one before: blocks are
         * separated by a blank line, list items by a line break, table cells
         * by a tab. `next_separator` overrides it for one segment. */
        string block_separator = "\n\n";
        string? next_separator;

        /* Decoded images are shared across renders, which happen on every edit in
         * side-by-side mode. */
        static HashTable<string, Gdk.Texture>? texture_cache;
        static HashTable<string, bool>? failed_images;

        const string[] BULLETS = { "•", "◦", "▪" };

        public Gtk.Widget render (Block doc) {
            if (highlight != "") {
                try {
                    highlight_re = new Regex (Regex.escape_string (highlight), RegexCompileFlags.CASELESS);
                } catch (RegexError e) {
                    highlight_re = null;
                }
            }
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);
            box.add_css_class ("markdown");
            box.set_cursor_from_name ("text");
            render_children (doc, box, Align.NONE, 0);
            return box;
        }

        void add_segment (Gtk.Widget widget) {
            segments.add (new Notes.TextSegment (widget, next_separator ?? block_separator));
            next_separator = null;
        }

        public Gtk.Widget? get_anchor (string slug) {
            return anchors.lookup (slug);
        }

        void render_children (Block parent, Gtk.Box into, Align align, int depth) {
            for (int k = 0; k < parent.children.length; k++) {
                Block b = parent.children[k];
                Gtk.Widget? w = render_block (b, align, depth);
                if (w == null) {
                    continue;
                }
                // Keep a title and its subtitle visually together.
                if (b.kind == BlockKind.HEADING && b.level == 1 && k + 1 < parent.children.length
                    && parent.children[k + 1].lead) {
                    var group = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
                    group.append (w);
                    group.append (render_block (parent.children[k + 1], align, depth));
                    into.append (group);
                    k++;
                    continue;
                }
                into.append (w);
            }
        }

        Gtk.Widget? render_block (Block b, Align align, int depth) {
            switch (b.kind) {
            case BlockKind.PARAGRAPH:
                return inline_block (b.inlines, b.lead ? "md-lead" : "md-p", align);

            case BlockKind.HEADING:
                var heading = inline_block (b.inlines, "md-h%d".printf (b.level), b.align != Align.NONE ? b.align : align);
                heading.add_css_class ("md-heading");
                register_anchor (b.inlines != null ? b.inlines.plain_text () : "", heading);
                return heading;

            case BlockKind.BLOCKQUOTE:
                var quote = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
                quote.add_css_class ("md-blockquote");
                render_children (b, quote, align, depth);
                return quote;

            case BlockKind.LIST:
                return list_widget (b, align, depth);

            case BlockKind.CODE:
                if (b.info.strip ().down () == "mermaid") {
                    return diagram_widget (b);
                }
                return code_widget (b);

            case BlockKind.RULE:
                var rule = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
                rule.add_css_class ("md-hr");
                return rule;

            case BlockKind.TABLE:
                return table_widget (b);

            case BlockKind.CONTAINER:
                var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);
                render_children (b, box, b.align != Align.NONE ? b.align : align, depth);
                return box;

            case BlockKind.DETAILS:
                return details_widget (b, align, depth);

            case BlockKind.SPACER:
                var spacer = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
                spacer.height_request = 4;
                return spacer;

            default:
                return null;
            }
        }

        /* ---- Text ---- */

        static bool is_image_like (Inline node) {
            if (node.kind == InlineKind.IMAGE) {
                return true;
            }
            if (node.kind != InlineKind.LINK || node.first == null) {
                return false;
            }
            bool has_image = false;
            for (Inline? c = node.first; c != null; c = c.next) {
                if (c.kind == InlineKind.IMAGE) {
                    has_image = true;
                } else if (!(c.kind == InlineKind.TEXT && c.text.strip () == "")
                           && c.kind != InlineKind.SOFTBREAK) {
                    return false;
                }
            }
            return has_image;
        }

        static bool range_is_blank (Inline? from, Inline? stop) {
            for (Inline? c = from; c != null && c != stop; c = c.next) {
                if (c.kind == InlineKind.SOFTBREAK || c.kind == InlineKind.HARDBREAK) {
                    continue;
                }
                if (c.kind != InlineKind.TEXT || c.text.strip () != "") {
                    return false;
                }
            }
            return true;
        }

        /* A paragraph-like block. Images can't live inside a label, so a paragraph
         * with images is split into text runs and image rows. */
        Gtk.Widget inline_block (Inline? inlines, string css, Align align) {
            Inline root = inlines ?? new Inline (InlineKind.ROOT);

            bool has_images = false;
            for (Inline? c = root.first; c != null; c = c.next) {
                if (is_image_like (c)) {
                    has_images = true;
                    break;
                }
            }
            if (!has_images) {
                return text_label (root.first, null, css, align);
            }

            var column = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            Notes.WrapBox? row = null;
            Inline? start = root.first;
            for (Inline? c = root.first; c != null; c = c.next) {
                if (!is_image_like (c)) {
                    continue;
                }
                if (!range_is_blank (start, c)) {
                    column.append (text_label (start, c, css, align));
                    row = null;
                }
                if (row == null) {
                    row = new Notes.WrapBox ();
                    row.line_align = to_halign (align);
                    column.append (row);
                }
                Inline image = c;
                string? link = null;
                if (c.kind == InlineKind.LINK) {
                    link = c.url;
                    for (Inline? x = c.first; x != null; x = x.next) {
                        if (x.kind == InlineKind.IMAGE) {
                            image = x;
                            break;
                        }
                    }
                }
                row.append (image_widget (image, link));
                start = c.next;
            }
            if (start != null && !range_is_blank (start, null)) {
                column.append (text_label (start, null, css, align));
            }
            return column;
        }

        /* Labels aren't selectable themselves: Notes.TextSelection selects across
         * all the segments of the note. */
        Gtk.Label text_label (Inline? from, Inline? stop, string css, Align align, bool selectable = true) {
            var sb = new StringBuilder ();
            label_matched = false;
            for (Inline? c = from; c != null && c != stop; c = c.next) {
                markup_node (sb, c, false);
            }
            string markup = sb.str.strip ();

            var label = new Gtk.Label (null);
            try {
                // Links are a GtkLabel extension that Pango itself doesn't accept.
                string pango_only = /<a [^>]*>|<\/a>/.replace (markup, -1, 0, "");
                Pango.AttrList attrs;
                string text;
                unichar accel;
                Pango.parse_markup (pango_only, -1, 0, out attrs, out text, out accel);
                label.set_markup (markup);
            } catch (Error e) {
                label.set_text (plain_range (from, stop));
            }
            label.wrap = true;
            label.wrap_mode = Pango.WrapMode.WORD_CHAR;
            label.xalign = align == Align.CENTER ? 0.5f : align == Align.RIGHT ? 1.0f : 0.0f;
            label.justify = align == Align.CENTER ? Gtk.Justification.CENTER
                : align == Align.RIGHT ? Gtk.Justification.RIGHT : Gtk.Justification.LEFT;
            label.add_css_class (css);
            label.activate_link.connect ((uri) => {
                link_activated (uri);
                return true;
            });
            if (label_matched) {
                match_widgets.add (label);
            }
            if (selectable) {
                add_segment (label);
            }
            return label;
        }

        static string plain_range (Inline? from, Inline? stop) {
            var holder = new StringBuilder ();
            for (Inline? c = from; c != null && c != stop; c = c.next) {
                if (c.kind == InlineKind.TEXT || c.kind == InlineKind.CODE) {
                    holder.append (c.text);
                } else if (c.kind == InlineKind.SOFTBREAK || c.kind == InlineKind.HARDBREAK) {
                    holder.append_c ('\n');
                } else {
                    holder.append (c.plain_text ());
                }
            }
            return holder.str;
        }

        void markup_children (StringBuilder sb, Inline node, bool in_link) {
            for (Inline? c = node.first; c != null; c = c.next) {
                markup_node (sb, c, in_link);
            }
        }

        void wrap (StringBuilder sb, Inline node, string open, string close, bool in_link) {
            sb.append (open);
            markup_children (sb, node, in_link);
            sb.append (close);
        }

        void markup_node (StringBuilder sb, Inline node, bool in_link) {
            switch (node.kind) {
            case InlineKind.TEXT:
                sb.append (escape (node.text));
                break;
            // Like GitHub comments and most note apps, a line break in the source is kept.
            case InlineKind.SOFTBREAK:
            case InlineKind.HARDBREAK:
                sb.append_c ('\n');
                break;
            case InlineKind.CODE:
                sb.append ("<span font_family=\"monospace\" size=\"90%\" background=\"#7f7f7f\" bgalpha=\"16%\"> ");
                sb.append (escape (node.text));
                sb.append (" </span>");
                break;
            case InlineKind.EMPH:
                wrap (sb, node, "<i>", "</i>", in_link);
                break;
            case InlineKind.STRONG:
                wrap (sb, node, "<b>", "</b>", in_link);
                break;
            case InlineKind.STRIKE:
                wrap (sb, node, "<s>", "</s>", in_link);
                break;
            case InlineKind.UNDERLINE:
                wrap (sb, node, "<u>", "</u>", in_link);
                break;
            case InlineKind.SUB:
                wrap (sb, node, "<sub>", "</sub>", in_link);
                break;
            case InlineKind.SUP:
                wrap (sb, node, "<sup>", "</sup>", in_link);
                break;
            case InlineKind.SMALL:
                wrap (sb, node, "<small>", "</small>", in_link);
                break;
            case InlineKind.MONO:
                wrap (sb, node, "<span font_family=\"monospace\" size=\"90%\">", "</span>", in_link);
                break;
            case InlineKind.KBD:
                wrap (sb, node,
                      "<span font_family=\"monospace\" size=\"smaller\" background=\"#7f7f7f\" bgalpha=\"22%\"> ",
                      " </span>", in_link);
                break;
            case InlineKind.MARK:
                wrap (sb, node, "<span background=\"#f9f06b\" foreground=\"#1e1e1e\">", "</span>", in_link);
                break;
            case InlineKind.LINK:
                if (in_link || node.url == "") {
                    markup_children (sb, node, in_link);
                    break;
                }
                sb.append ("<a href=\"");
                sb.append (Markup.escape_text (node.url));
                sb.append_c ('"');
                if (node.title != "") {
                    sb.append (" title=\"");
                    sb.append (Markup.escape_text (node.title));
                    sb.append_c ('"');
                }
                sb.append_c ('>');
                markup_children (sb, node, true);
                sb.append ("</a>");
                break;
            case InlineKind.IMAGE:
                // An image in the middle of a sentence: show its description.
                string alt = node.plain_text ();
                sb.append ("<i>");
                sb.append (escape (alt != "" ? alt : "image"));
                sb.append ("</i>");
                break;
            default:
                markup_children (sb, node, in_link);
                break;
            }
        }

        /* Escapes text for Pango markup and wraps search matches in a highlight. */
        string escape (string s) {
            if (highlight_re == null) {
                return Markup.escape_text (s);
            }
            var sb = new StringBuilder ();
            int last = 0;
            MatchInfo mi;
            try {
                if (highlight_re.match (s, 0, out mi)) {
                    do {
                        int a, b;
                        mi.fetch_pos (0, out a, out b);
                        if (b <= a) {
                            break;
                        }
                        sb.append (Markup.escape_text (s.substring (last, a - last)));
                        sb.append ("<span background=\"#f6d32d\" foreground=\"#1e1e1e\">");
                        sb.append (Markup.escape_text (s.substring (a, b - a)));
                        sb.append ("</span>");
                        last = b;
                        match_count++;
                        label_matched = true;
                    } while (mi.next ());
                }
            } catch (RegexError e) {
            }
            sb.append (Markup.escape_text (s.substring (last)));
            return sb.str;
        }

        void register_anchor (string text, Gtk.Widget widget) {
            var sb = new StringBuilder ();
            string low = text.down ();
            int idx = 0;
            unichar ch;
            while (low.get_next_char (ref idx, out ch)) {
                if (ch.isalnum () || ch == '_' || ch == '-') {
                    sb.append_unichar (ch);
                } else if (ch == ' ') {
                    sb.append_c ('-');
                }
            }
            string slug = sb.str;
            int seen = slug_counts.lookup (slug);
            slug_counts.insert (slug, seen + 1);
            if (seen > 0) {
                slug = "%s-%d".printf (slug, seen);
            }
            anchors.insert (slug, widget);
        }

        static Gtk.Align to_halign (Align align) {
            switch (align) {
            case Align.CENTER:
                return Gtk.Align.CENTER;
            case Align.RIGHT:
                return Gtk.Align.END;
            default:
                return Gtk.Align.START;
            }
        }

        /* ---- Lists ---- */

        /* A method rather than a closure: a closure would hold the check button
         * and the renderer, so neither would be freed when the preview is
         * replaced. */
        void on_task_check_toggled (Gtk.CheckButton check) {
            task_toggled (check.get_data<int> ("md-line"), check.active);
        }

        Gtk.Widget list_widget (Block list, Align align, int depth) {
            int spacing = list.tight ? 4 : 12;
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, spacing);
            box.add_css_class ("md-list");
            int number = list.start;
            string outer_separator = block_separator;
            next_separator = next_separator ?? outer_separator;
            block_separator = "\n";
            for (int k = 0; k < list.children.length; k++) {
                Block item = list.children[k];
                var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);

                Gtk.Widget marker;
                if (item.task) {
                    var check = new Gtk.CheckButton ();
                    check.active = item.checked;
                    check.sensitive = !read_only;
                    check.add_css_class ("md-task");
                    check.set_cursor_from_name ("default");
                    check.set_data<int> ("md-line", item.line);
                    check.toggled.connect (on_task_check_toggled);
                    marker = check;
                } else if (list.ordered) {
                    var num = new Gtk.Label ("%d.".printf (number++));
                    num.xalign = 1;
                    num.width_chars = 3;
                    num.add_css_class ("md-number");
                    marker = num;
                } else {
                    var bullet = new Gtk.Label (BULLETS[depth % BULLETS.length]);
                    bullet.width_chars = 2;
                    bullet.add_css_class ("md-bullet");
                    marker = bullet;
                }
                // Text markers sit on the baseline of the item's first line.
                marker.valign = item.task ? Gtk.Align.START : Gtk.Align.BASELINE_FILL;
                row.append (marker);

                var content = new Gtk.Box (Gtk.Orientation.VERTICAL, spacing);
                content.hexpand = true;
                content.baseline_child = 0;
                content.valign = Gtk.Align.BASELINE_FILL;
                render_children (item, content, align, depth + 1);
                row.append (content);
                box.append (row);
            }
            block_separator = outer_separator;
            return box;
        }

        /* ---- Code ---- */

        static GtkSource.Language? language_for (string info) {
            if (info == "") {
                return null;
            }
            var lm = GtkSource.LanguageManager.get_default ();
            string id = info.down ();
            switch (id) {
            case "js": case "javascript": case "jsx": case "node": case "mjs":
                id = "js";
                break;
            case "ts": case "tsx":
                id = "typescript";
                break;
            case "py": case "python":
                id = "python3";
                break;
            case "sh": case "bash": case "shell": case "zsh": case "console":
                id = "sh";
                break;
            case "c++": case "cc": case "hpp": case "cxx":
                id = "cpp";
                break;
            case "cs": case "csharp": case "c#":
                id = "c-sharp";
                break;
            case "rs":
                id = "rust";
                break;
            case "rb":
                id = "ruby";
                break;
            case "yml":
                id = "yaml";
                break;
            case "md":
                id = "markdown";
                break;
            case "golang":
                id = "go";
                break;
            case "patch":
                id = "diff";
                break;
            case "docker":
                id = "dockerfile";
                break;
            case "make":
                id = "makefile";
                break;
            case "kt":
                id = "kotlin";
                break;
            default:
                break;
            }
            var lang = lm.get_language (id);
            if (lang == null) {
                lang = lm.guess_language ("file." + info, null);
            }
            return lang;
        }

        /* Parsed diagrams by source, so that re-rendering keeps their layouts. */
        static HashTable<string, Mermaid.Diagram>? diagrams;

        static Mermaid.Diagram parse_diagram (string code) throws Mermaid.ParseError {
            if (diagrams == null || diagrams.size () > 64) {
                diagrams = new HashTable<string, Mermaid.Diagram> (str_hash, str_equal);
            }
            var d = diagrams[code];
            if (d == null) {
                d = Mermaid.parse (code);
                diagrams[code] = d;
            }
            return d;
        }

        /*
         * A Mermaid diagram. When it can't be drawn, the source is shown as
         * code with a note saying why.
         */
        Gtk.Widget diagram_widget (Block b) {
            string code = b.code;
            if (code.has_suffix ("\n")) {
                code = code.substring (0, code.length - 1);
            }

            Mermaid.Diagram diagram;
            try {
                diagram = parse_diagram (code);
            } catch (Mermaid.ParseError e) {
                var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
                box.append (code_widget (b));
                string reason;
                if (e is Mermaid.ParseError.UNSUPPORTED) {
                    reason = _("This diagram can't be shown: %s.").printf (e.message);
                } else {
                    reason = _("This diagram has an error. %s").printf (e.message);
                }
                var note = new Gtk.Label (reason);
                note.xalign = 0;
                note.wrap = true;
                note.wrap_mode = Pango.WrapMode.WORD_CHAR;
                note.margin_start = 4;
                note.add_css_class ("dim-label");
                note.add_css_class ("caption");
                box.append (note);
                return box;
            }

            var view = new Mermaid.View (diagram);
            view.accent = Adw.StyleManager.get_default ().get_accent_color_rgba ();
            view.hexpand = true;
            // Wide diagrams scroll, like code, instead of shrinking past reading.
            view.min_scale = 0.75;
            view.set_cursor_from_name ("default");

            var scroller = new Gtk.ScrolledWindow ();
            scroller.vscrollbar_policy = Gtk.PolicyType.NEVER;
            scroller.hscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            scroller.propagate_natural_height = true;
            scroller.child = view;

            var copy = copy_button (code, _("Copy Diagram Source"));

            var overlay = new Gtk.Overlay ();
            overlay.child = scroller;
            overlay.add_overlay (copy);
            overlay.overflow = Gtk.Overflow.HIDDEN;
            overlay.add_css_class ("md-diagram");
            return overlay;
        }

        /* The button that copies a code block or a diagram's source. It's built
         * in a static method, and its handler uses the button it's given instead
         * of capturing it, so the closure holds neither the button nor the
         * renderer. Either would keep the replaced preview from being freed. */
        static Gtk.Button copy_button (string code, string tooltip) {
            var copy = new Gtk.Button.from_icon_name ("edit-copy-symbolic");
            copy.tooltip_text = tooltip;
            copy.halign = Gtk.Align.END;
            copy.valign = Gtk.Align.START;
            copy.margin_top = 6;
            copy.margin_end = 6;
            copy.add_css_class ("flat");
            copy.add_css_class ("md-copy");
            copy.set_cursor_from_name ("default");
            copy.clicked.connect ((button) => {
                button.get_clipboard ().set_text (code);
                button.icon_name = "object-select-symbolic";
                Timeout.add (1500, () => {
                    button.icon_name = "edit-copy-symbolic";
                    return Source.REMOVE;
                });
            });
            return copy;
        }

        Gtk.Widget code_widget (Block b) {
            string code = b.code;
            if (code.has_suffix ("\n")) {
                code = code.substring (0, code.length - 1);
            }

            var buffer = new GtkSource.Buffer (null);
            buffer.text = code;
            buffer.highlight_matching_brackets = false;
            var lang = language_for (b.info);
            if (lang != null) {
                buffer.language = lang;
            }
            buffer.style_scheme = GtkSource.StyleSchemeManager.get_default ().get_scheme (dark ? "Adwaita-dark" : "Adwaita");

            var view = new GtkSource.View.with_buffer (buffer);
            view.editable = false;
            view.cursor_visible = false;
            view.monospace = true;
            view.top_margin = 14;
            view.bottom_margin = 14;
            view.left_margin = 12;
            view.right_margin = 48;
            view.wrap_mode = Gtk.WrapMode.NONE;
            view.hexpand = true;
            // Notes.TextSelection selects the code along with the text around it.
            view.can_target = false;
            view.focusable = false;
            add_segment (view);

            var scroller = new Gtk.ScrolledWindow ();
            scroller.vscrollbar_policy = Gtk.PolicyType.NEVER;
            scroller.hscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            scroller.propagate_natural_height = true;
            scroller.hexpand = true;
            scroller.child = view;

            // Line numbers as a plain dim column; GtkSourceView's gutter follows
            // the style scheme and would draw its own background.
            var body = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            int lines = code.split ("\n").length;
            if (lines > 1) {
                var numbers = new StringBuilder ();
                for (int k = 1; k <= lines; k++) {
                    numbers.append_printf (k < lines ? "%d\n" : "%d", k);
                }
                var gutter = new Gtk.Label (numbers.str);
                gutter.xalign = 1;
                gutter.yalign = 0;
                gutter.valign = Gtk.Align.START;
                gutter.margin_top = 14;
                gutter.margin_start = 16;
                gutter.add_css_class ("md-code-gutter");
                body.append (gutter);
            }
            body.append (scroller);

            var copy = copy_button (code, _("Copy"));

            var overlay = new Gtk.Overlay ();
            overlay.child = body;
            overlay.add_overlay (copy);
            overlay.overflow = Gtk.Overflow.HIDDEN;
            overlay.add_css_class ("md-code-block");
            return overlay;
        }

        /* ---- Tables ---- */

        Gtk.Widget table_widget (Block table) {
            var grid = new Gtk.Grid ();
            int rows = (int) table.children.length;
            for (int r = 0; r < rows; r++) {
                Block row = table.children[r];
                int cols = (int) row.children.length;
                for (int c = 0; c < cols; c++) {
                    Block cell = row.children[c];
                    if (c > 0) {
                        next_separator = "\t";
                    } else if (r > 0) {
                        next_separator = "\n";
                    }
                    var label = text_label (cell.inlines != null ? cell.inlines.first : null, null,
                                            "md-cell-label", cell.align);
                    label.max_width_chars = 40;

                    var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
                    box.add_css_class ("md-cell");
                    if (row.header) {
                        box.add_css_class ("md-cell-header");
                    }
                    if (r == rows - 1) {
                        box.add_css_class ("md-cell-last-row");
                    }
                    if (c == cols - 1) {
                        box.add_css_class ("md-cell-last-col");
                    }
                    box.append (label);
                    grid.attach (box, c, r);
                }
            }

            // Wide tables wrap their cells to fit the column instead of scrolling.
            var frame = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            frame.add_css_class ("md-table");
            frame.overflow = Gtk.Overflow.HIDDEN;
            frame.halign = Gtk.Align.START;
            frame.append (grid);
            return frame;
        }

        /* ---- Details ---- */

        Gtk.Widget details_widget (Block b, Align align, int depth) {
            var expander = new Gtk.Expander (null);
            expander.label_widget = text_label (b.summary_inlines != null ? b.summary_inlines.first : null, null,
                                                "md-summary", Align.NONE, false);
            expander.expanded = b.open;
            expander.add_css_class ("md-details");
            expander.set_cursor_from_name ("default");

            var inner = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);
            inner.set_cursor_from_name ("text");
            inner.margin_top = 10;
            inner.margin_start = 24;
            render_children (b, inner, align, depth);
            expander.child = inner;
            return expander;
        }

        /* ---- Images ---- */

        Gtk.Widget image_widget (Inline image, string? link) {
            var holder = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            holder.set_cursor_from_name ("default");
            var view = new Notes.ImageView (image.width);
            holder.append (view);

            string alt = image.plain_text ();
            if (image.title != "") {
                holder.tooltip_text = image.title;
            } else if (alt != "") {
                holder.tooltip_text = alt;
            }

            if (link != null && link != "") {
                var click = new Gtk.GestureClick ();
                click.released.connect (() => link_activated (link));
                holder.add_controller (click);
                holder.set_cursor_from_name ("pointer");
            }

            load_image.begin (image.url, view, holder, alt);
            return holder;
        }

        File? resolve_image (string src) {
            string? scheme = Uri.peek_scheme (src);
            if (scheme != null) {
                return File.new_for_uri (src);
            }
            string path = Uri.unescape_string (src) ?? src;
            int q = path.index_of_char ('?');
            if (q >= 0) {
                path = path.substring (0, q);
            }
            if (path.has_prefix ("/")) {
                return File.new_for_path (path);
            }
            return base_dir != null ? base_dir.resolve_relative_path (path) : null;
        }

        async void load_image (string src, Notes.ImageView view, Gtk.Box holder, string alt) {
            if (texture_cache == null) {
                texture_cache = new HashTable<string, Gdk.Texture> (str_hash, str_equal);
                failed_images = new HashTable<string, bool> (str_hash, str_equal);
            }

            File? file = src.has_prefix ("data:") ? null : resolve_image (src);
            string key = file != null ? file.get_uri () : src;
            Gdk.Texture? texture = texture_cache.lookup (key);

            if (texture == null && !failed_images.contains (key)) {
                try {
                    Bytes bytes;
                    if (src.has_prefix ("data:")) {
                        int comma = src.index_of_char (',');
                        if (comma < 0 || !src.substring (0, comma).has_suffix (";base64")) {
                            throw new IOError.NOT_SUPPORTED ("unsupported data URI");
                        }
                        bytes = new Bytes.take (Base64.decode (src.substring (comma + 1)));
                    } else if (file != null) {
                        bytes = yield file.load_bytes_async (null, null);
                    } else {
                        throw new IOError.NOT_FOUND ("no base directory");
                    }
                    texture = decode_texture (bytes);
                    texture_cache.insert (key, texture);
                } catch (Error e) {
                    failed_images.insert (key, true);
                }
            }

            if (texture != null) {
                view.set_paintable (texture);
                return;
            }

            // Show the description where the image would have been.
            holder.remove (view);
            var fallback = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            fallback.add_css_class ("md-image-missing");
            fallback.append (new Gtk.Image.from_icon_name ("image-missing-symbolic"));
            var label = new Gtk.Label (alt != "" ? alt : Path.get_basename (src));
            label.ellipsize = Pango.EllipsizeMode.END;
            fallback.append (label);
            holder.append (fallback);
        }

        static Gdk.Texture decode_texture (Bytes bytes) throws Error {
            try {
                return Gdk.Texture.from_bytes (bytes);
            } catch (Error e) {
                // Formats GDK doesn't handle natively (SVG, GIF, WebP...) go through gdk-pixbuf.
                var pixbuf = new Gdk.Pixbuf.from_stream (new MemoryInputStream.from_bytes (bytes));
                var format = pixbuf.has_alpha ? Gdk.MemoryFormat.R8G8B8A8 : Gdk.MemoryFormat.R8G8B8;
                return new Gdk.MemoryTexture (pixbuf.width, pixbuf.height, format,
                                              pixbuf.read_pixel_bytes (), pixbuf.rowstride);
            }
        }
    }
}
