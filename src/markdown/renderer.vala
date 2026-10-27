/* Renders a Markdown document tree into native GTK widgets.
 *
 * Text blocks become Gtk.Labels with Pango markup, code blocks become
 * read-only GtkSourceViews with syntax highlighting, tables become grids, and
 * images are decoded with GDK. No web engine involved.
 */

namespace Markdown {

    /* A top-level block of a note, or a title with its subtitle, and the
     * widgets rendered for it. Sections are kept between renders, so an edit
     * renders again only the sections whose blocks changed. The items of a
     * top-level list are sections of their own, since lists can be long. */
    class Section {
        /* Everything the widgets depend on; see Renderer.fingerprint (). */
        public string key;
        /* The source line where the section starts. Task checks keep their
         * line in "md-line" data, which moves along with it. */
        public int line;

        /* What to render, until it's rendered. */
        public Block? block;
        public Block? subtitle;

        public bool built;
        public Gtk.Widget? widget;
        public GenericArray<Section>? items;

        /* Where it was in the previous render, and whether it's used again. */
        public int index;
        public bool reused;

        public GenericArray<Notes.TextSegment> segments = new GenericArray<Notes.TextSegment> ();
        public GenericArray<Gtk.CheckButton> checks = new GenericArray<Gtk.CheckButton> ();
        /* Headings, with the slug of their text before duplicates are numbered. */
        public string[] slugs = {};
        public GenericArray<Gtk.Widget> headings = new GenericArray<Gtk.Widget> ();
        public GenericArray<Gtk.Label> labels = new GenericArray<Gtk.Label> ();

        public Section (string key, int line, Block block, Block? subtitle) {
            this.key = key;
            this.line = line;
            this.block = block;
            this.subtitle = subtitle;
        }
    }

    public class Renderer : Object {
        public signal void link_activated (string uri);
        public signal void task_toggled (int line, bool active);
        /* More of a note that is still loading was rendered. */
        public signal void appended ();

        public File? base_dir { get; set; }
        public bool read_only { get; set; }

        /* Code blocks follow the dark style without being rendered again. */
        public bool dark {
            get {
                return _dark;
            }
            set {
                if (_dark == value) {
                    return;
                }
                _dark = value;
                foreach (var segment in segments) {
                    var view = segment.widget as GtkSource.View;
                    if (view != null) {
                        ((GtkSource.Buffer) view.buffer).style_scheme = code_scheme ();
                    }
                }
            }
        }
        bool _dark;

        /* The rendered note. It stays the same widget across updates. */
        public Gtk.Box content { get; private set; }

        /* The selectable text of the note, in reading order. */
        public GenericArray<Notes.TextSegment> segments = new GenericArray<Notes.TextSegment> ();
        /* All of its text labels, in reading order, for search. */
        public GenericArray<Gtk.Label> labels = new GenericArray<Gtk.Label> ();

        GenericArray<Section> sections = new GenericArray<Section> ();
        /* The section being rendered. It collects segments, headings and matches. */
        Section? current;
        /* While a note loads, the first section that isn't rendered yet, and
         * how many sections or list items to render next. */
        int pending = -1;
        int batch_size;
        uint batch_source;
        Gdk.FrameClock? frame_clock;
        ulong paint_handler;

        /* Whether all of the note is rendered. */
        public bool complete {
            get {
                return pending < 0;
            }
        }

        HashTable<string, Gtk.Widget> anchors = new HashTable<string, Gtk.Widget> (str_hash, str_equal);

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

        construct {
            content = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);
            content.add_css_class ("markdown");
            content.set_cursor_from_name ("text");
        }

        /*
         * Shows `doc`. Sections that are the same as in what was shown before
         * keep their widgets, so GTK doesn't have to measure them again, and
         * only the others are rendered.
         */
        public void update (Block doc) {
            for (int k = 0; k < sections.length; k++) {
                sections[k].index = k;
                sections[k].reused = false;
            }
            var unused = by_key (sections);
            var next = new GenericArray<Section> ();
            var blocks = doc.children;
            for (int k = 0; k < blocks.length; k++) {
                Block block = blocks[k];
                Block? subtitle = null;
                // Keep a title and its subtitle visually together.
                if (block.kind == BlockKind.HEADING && block.level == 1 && k + 1 < blocks.length
                    && blocks[k + 1].lead) {
                    subtitle = blocks[++k];
                }
                string key = fingerprint (block, subtitle);
                Section? section = take (unused, key);
                if (section != null) {
                    move_section (section, block.line);
                } else {
                    section = new Section (key, block.line, block, subtitle);
                }
                next.add (section);
            }

            // A list that changed takes the place of the old list between the
            // same neighbors, and keeps the items that didn't change.
            int last = -1;
            for (int k = 0; k < next.length; k++) {
                Section section = next[k];
                if (section.built) {
                    last = section.index;
                    continue;
                }
                if (section.block.kind != BlockKind.LIST) {
                    continue;
                }
                for (int j = last + 1; j < sections.length && !sections[j].reused; j++) {
                    Section old = sections[j];
                    if (old.items != null) {
                        old.reused = true;
                        old.key = section.key;
                        old.line = section.line;
                        old.block = section.block;
                        next[k] = old;
                        last = j;
                        break;
                    }
                }
            }

            bool fresh = true;
            foreach (var old in sections) {
                if (!old.reused && old.widget != null) {
                    content.remove (old.widget);
                }
                if (old.built) {
                    fresh = false;
                }
            }
            sections = next;

            // A new note shows its first screen right away, and the rest is
            // rendered a little at a time, so the window keeps responding.
            // While that goes on, edits only render what is already shown.
            bool loading = pending >= 0;
            stop_loading ();
            int last_built = -1;
            for (int k = 0; k < sections.length; k++) {
                if (sections[k].built) {
                    last_built = k;
                }
            }
            int width = layout_width ();
            int screen = fresh ? screen_height () : 0;
            int filled = 0;

            Gtk.Widget? prev = null;
            for (int k = 0; k < sections.length; k++) {
                Section section = sections[k];
                if (!section.built) {
                    if ((fresh || loading) && k > last_built && filled >= screen) {
                        start_loading (k);
                        break;
                    }
                    if (fresh && section.block.kind == BlockKind.LIST) {
                        // A long list can fill the screen by itself.
                        int room = screen - filled;
                        bool whole = build_list (section, prev, true, ref room);
                        filled = screen - room;
                        if (!whole) {
                            start_loading (k);
                            break;
                        }
                    } else {
                        build (section, prev);
                        if (fresh && section.widget != null) {
                            filled += height_of (section.widget, width);
                        }
                    }
                } else {
                    if (section.block != null) {
                        update_items (section, section.block);
                        section.block = null;
                    }
                    if (section.widget != null && section.widget.get_prev_sibling () != prev) {
                        content.reorder_child_after (section.widget, prev);
                    }
                }
                if (section.widget != null) {
                    prev = section.widget;
                }
            }
            collect ();
        }

        /*
         * Renders the next part of a note that is still loading, then waits
         * for the frame that shows it. Measuring new text takes GTK far
         * longer than making the widgets, so the size of each part follows
         * how long the last frame took.
         */
        bool load_more () {
            batch_source = 0;
            if (content.get_root () == null) {
                stop_loading ();  // the note was closed
                return Source.REMOVE;
            }
            load (batch_size);
            if (pending < 0) {
                return Source.REMOVE;
            }
            frame_clock = content.get_frame_clock ();
            if (frame_clock == null) {
                batch_source = Idle.add (load_more);
                return Source.REMOVE;
            }
            paint_handler = frame_clock.after_paint.connect (on_frame_painted);
            frame_clock.request_phase (Gdk.FrameClockPhase.AFTER_PAINT);
            return Source.REMOVE;
        }

        void on_frame_painted () {
            // Aim for frames of about 25 ms, so that scrolling stays fluid.
            int64 took = int64.max (get_monotonic_time () - frame_clock.get_frame_time (), 1000);
            frame_clock.disconnect (paint_handler);
            paint_handler = 0;
            frame_clock = null;
            int next = (int) (batch_size * 25000 / took);
            batch_size = next.clamp (int.max (batch_size / 2, 1), int.min (batch_size * 2, 400));
            batch_source = Idle.add (load_more);
        }

        /*
         * Renders the rest of a note that is still loading right away, for
         * what needs all of it. Returns whether there was anything left. The
         * new widgets have their size and place after the next frame.
         */
        public bool finish () {
            if (pending < 0) {
                return false;
            }
            load (int.MAX);
            return true;
        }

        /* Renders `count` more sections or list items, from `pending` on. */
        void load (int count) {
            stop_waiting ();
            Gtk.Widget? prev = widget_before (pending);
            int room = count;
            while (pending < sections.length && room > 0) {
                Section section = sections[pending];
                if (section.block.kind == BlockKind.LIST) {
                    if (!build_list (section, prev, false, ref room)) {
                        break;
                    }
                } else {
                    build (section, prev);
                    room--;
                }
                pending++;
                if (section.widget != null) {
                    prev = section.widget;
                }
            }
            if (pending >= sections.length) {
                pending = -1;
            }
            collect ();
            appended ();
        }

        void stop_waiting () {
            if (batch_source != 0) {
                Source.remove (batch_source);
                batch_source = 0;
            }
            if (paint_handler != 0) {
                frame_clock.disconnect (paint_handler);
                paint_handler = 0;
                frame_clock = null;
            }
        }

        void stop_loading () {
            stop_waiting ();
            pending = -1;
        }

        void start_loading (int from) {
            pending = from;
            if (batch_size <= 0) {
                batch_size = 8;
            }
            batch_source = Idle.add (load_more);
        }

        Gtk.Widget? widget_before (int index) {
            for (int k = index - 1; k >= 0; k--) {
                if (sections[k].widget != null) {
                    return sections[k].widget;
                }
            }
            return null;
        }

        /* The width the sections get, or -1 before the preview has one. */
        int layout_width () {
            if (content.get_width () > 0) {
                return content.get_width ();
            }
            var parent = content.get_parent ();
            if (parent == null || parent.get_width () <= 0) {
                return -1;
            }
            return parent.get_width () - content.margin_start - content.margin_end;
        }

        int screen_height () {
            var scroller = content.get_ancestor (typeof (Gtk.ScrolledWindow));
            return scroller != null && scroller.get_height () > 0 ? scroller.get_height () : 800;
        }

        /* About how tall a new section is, to know when the first screen is full. */
        static int height_of (Gtk.Widget widget, int width) {
            if (width <= 0) {
                return 60;
            }
            int min, nat;
            widget.measure (Gtk.Orientation.HORIZONTAL, -1, out min, out nat, null, null);
            widget.measure (Gtk.Orientation.VERTICAL, int.max (width, min), out min, out nat, null, null);
            return nat;
        }

        /* Rendered sections by key. Equal sections are taken in order. */
        static HashTable<string, GenericArray<Section>> by_key (GenericArray<Section> list) {
            var table = new HashTable<string, GenericArray<Section>> (str_hash, str_equal);
            foreach (var section in list) {
                if (!section.built || toggled (section)) {
                    continue;
                }
                var same = table[section.key];
                if (same == null) {
                    same = new GenericArray<Section> ();
                    table[section.key] = same;
                }
                same.add (section);
            }
            return table;
        }

        static Section? take (HashTable<string, GenericArray<Section>> table, string key) {
            var same = table[key];
            if (same == null || same.length == 0) {
                return null;
            }
            Section section = same[0];
            same.remove_index (0);
            section.reused = true;
            return section;
        }

        /* The source of a reused section now starts at `line`. */
        static void move_section (Section section, int line) {
            int delta = line - section.line;
            if (delta == 0) {
                return;
            }
            section.line = line;
            foreach (var check in section.checks) {
                check.set_data<int> ("md-line", check.get_data<int> ("md-line") + delta);
            }
            if (section.items != null) {
                foreach (var item in section.items) {
                    move_section (item, item.line + delta);
                }
            }
        }

        /* Renders a section and shows it after `prev`. */
        void build (Section section, Gtk.Widget? prev) {
            if (section.block.kind == BlockKind.LIST) {
                int room = int.MAX;
                build_list (section, prev, false, ref room);
                return;
            }

            current = section;
            block_separator = "\n\n";
            next_separator = null;
            Gtk.Widget? widget = render_block (section.block, Align.NONE, 0);
            if (widget != null && section.subtitle != null) {
                var group = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
                group.append (widget);
                group.append (render_block (section.subtitle, Align.NONE, 0));
                widget = group;
            }
            section.widget = widget;
            section.built = true;
            if (widget != null) {
                content.insert_child_after (widget, prev);
            }
            if (widget != null && has_tasks (section.block)) {
                find_checks (widget, section.checks);
            }
            section.block = null;
            section.subtitle = null;
            current = null;
        }

        /* Renders a top-level list, from its first item that isn't rendered
         * yet, until its items fill `room`: pixels if `measure`, else a number
         * of items. Returns whether all of it is rendered. */
        bool build_list (Section section, Gtk.Widget? prev, bool measure, ref int room) {
            Block list = section.block;
            if (section.widget == null) {
                var box = new Gtk.Box (Gtk.Orientation.VERTICAL, list.tight ? 4 : 12);
                box.add_css_class ("md-list");
                section.widget = box;
                section.items = new GenericArray<Section> ();
                content.insert_child_after (box, prev);
            }
            var box = (Gtk.Box) section.widget;
            int width = measure ? layout_width () : -1;
            while (section.items.length < list.children.length && room > 0) {
                int k = (int) section.items.length;
                Block block = list.children[k];
                var item = new Section (item_key (list, k, block), block.line, block, null);
                build_item (item, list, k);
                box.append (item.widget);
                section.items.add (item);
                room -= measure ? height_of (item.widget, width) : 1;
            }
            if (section.items.length < list.children.length) {
                return false;
            }
            section.built = true;
            section.block = null;
            return true;
        }

        static string item_key (Block list, int index, Block item) {
            return "%d %d %d %s".printf ((int) list.ordered, (int) list.tight,
                                         list.ordered ? list.start + index : 0, fingerprint (item, null));
        }

        /* Shows the items of a top-level list, keeping those that didn't change. */
        void update_items (Section section, Block list) {
            var box = (Gtk.Box) section.widget;
            box.spacing = list.tight ? 4 : 12;
            foreach (var item in section.items) {
                item.reused = false;
            }
            var unused = by_key (section.items);
            var next = new GenericArray<Section> ();
            for (int k = 0; k < list.children.length; k++) {
                Block block = list.children[k];
                string key = item_key (list, k, block);
                Section? item = take (unused, key);
                if (item != null) {
                    move_section (item, block.line);
                } else {
                    item = new Section (key, block.line, block, null);
                }
                next.add (item);
            }
            foreach (var old in section.items) {
                if (!old.reused) {
                    box.remove (old.widget);
                }
            }
            section.items = next;

            Gtk.Widget? prev = null;
            for (int k = 0; k < next.length; k++) {
                Section item = next[k];
                if (!item.built) {
                    build_item (item, list, k);
                    box.insert_child_after (item.widget, prev);
                } else if (item.widget.get_prev_sibling () != prev) {
                    box.reorder_child_after (item.widget, prev);
                }
                prev = item.widget;
            }
        }

        /* The row of item `index` of `list`, rendered as a list of its own. */
        void build_item (Section item, Block list, int index) {
            var single = new Block (BlockKind.LIST);
            single.ordered = list.ordered;
            single.start = list.start + index;
            single.tight = list.tight;
            single.add (item.block);

            current = item;
            block_separator = "\n";
            next_separator = null;
            var box = (Gtk.Box) list_widget (single, Align.NONE, 0);
            Gtk.Widget row = box.get_first_child ();
            box.remove (row);
            item.widget = row;
            item.built = true;
            if (has_tasks (item.block)) {
                find_checks (row, item.checks);
            }
            item.block = null;
            current = null;
        }

        /* Whether a check in the section was clicked since it was rendered. Its
         * widgets no longer match its key until the source catches up. */
        static bool toggled (Section section) {
            foreach (var check in section.checks) {
                if (check.active != check.get_data<bool> ("md-checked")) {
                    return true;
                }
            }
            if (section.items != null) {
                foreach (var item in section.items) {
                    if (toggled (item)) {
                        return true;
                    }
                }
            }
            return false;
        }

        static bool has_tasks (Block b) {
            if (b.task) {
                return true;
            }
            foreach (var child in b.children) {
                if (has_tasks (child)) {
                    return true;
                }
            }
            return false;
        }

        static void find_checks (Gtk.Widget widget, GenericArray<Gtk.CheckButton> into) {
            var check = widget as Gtk.CheckButton;
            if (check != null && check.has_css_class ("md-task")) {
                check.set_data<bool> ("md-checked", check.active);
                into.add (check);
                return;
            }
            for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
                find_checks (child, into);
            }
        }

        /* Gathers what the rendered sections hold, in reading order. */
        void collect () {
            segments = new GenericArray<Notes.TextSegment> ();
            labels = new GenericArray<Gtk.Label> ();
            anchors.remove_all ();
            var slug_counts = new HashTable<string, int> (str_hash, str_equal);
            foreach (var section in sections) {
                if (!section.built && section.items == null) {
                    continue;  // a list that is still loading has some items
                }
                uint first = segments.length;
                if (section.items != null) {
                    foreach (var item in section.items) {
                        uint start = segments.length;
                        collect_section (item, slug_counts);
                        // List items are separated by a line break when copied.
                        if (segments.length > start) {
                            segments[start].separator = "\n";
                        }
                    }
                } else {
                    collect_section (section, slug_counts);
                }
                if (segments.length > first) {
                    segments[first].separator = "\n\n";
                }
            }
        }

        void collect_section (Section section, HashTable<string, int> slug_counts) {
            foreach (var segment in section.segments) {
                segments.add (segment);
            }
            foreach (var label in section.labels) {
                labels.add (label);
            }
            for (int k = 0; k < section.slugs.length; k++) {
                string slug = section.slugs[k];
                int seen = slug_counts.lookup (slug);
                slug_counts.insert (slug, seen + 1);
                anchors.insert (seen > 0 ? "%s-%d".printf (slug, seen) : slug, section.headings[k]);
            }
        }

        /* ---- Fingerprints ---- */

        /* A text that differs whenever the widgets of a section would. Lines are
         * counted from the start of the section, so text added above it doesn't
         * change it, while the task checks in it can still find their lines. */
        static string fingerprint (Block block, Block? subtitle) {
            var sb = new StringBuilder ();
            print_block (sb, block, block.line);
            if (subtitle != null) {
                print_block (sb, subtitle, block.line);
            }
            return sb.str;
        }

        static void print_text (StringBuilder sb, string text) {
            sb.append_printf ("%d:", text.length);
            sb.append (text);
        }

        static void print_block (StringBuilder sb, Block b, int first_line) {
            sb.append_printf ("(%d %d %d %d %d %d %d %d %d %d %d %d ", (int) b.kind,
                              b.line >= 0 ? b.line - first_line : -1, b.level, (int) b.lead,
                              (int) b.ordered, b.start, (int) b.tight, (int) b.task, (int) b.checked,
                              (int) b.align, (int) b.header, (int) b.open);
            foreach (var align in b.aligns) {
                sb.append_printf ("%d", (int) align);
            }
            print_text (sb, b.info);
            print_text (sb, b.code);
            print_inline (sb, b.inlines);
            print_inline (sb, b.summary_inlines);
            foreach (var child in b.children) {
                print_block (sb, child, first_line);
            }
            sb.append_c (')');
        }

        static void print_inline (StringBuilder sb, Inline? node) {
            if (node == null) {
                sb.append_c ('-');
                return;
            }
            sb.append_printf ("[%d %d ", (int) node.kind, node.width);
            print_text (sb, node.text);
            print_text (sb, node.url);
            print_text (sb, node.title);
            for (Inline? c = node.first; c != null; c = c.next) {
                print_inline (sb, c);
            }
            sb.append_c (']');
        }

        /* ---- Blocks ---- */

        void add_segment (Gtk.Widget widget) {
            current.segments.add (new Notes.TextSegment (widget, next_separator ?? block_separator));
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
            current.labels.add (label);
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
                sb.append (Markup.escape_text (node.text));
                break;
            // Like GitHub comments and most note apps, a line break in the source is kept.
            case InlineKind.SOFTBREAK:
            case InlineKind.HARDBREAK:
                sb.append_c ('\n');
                break;
            case InlineKind.CODE:
                sb.append ("<span font_family=\"monospace\" size=\"90%\" background=\"#7f7f7f\" bgalpha=\"16%\"> ");
                sb.append (Markup.escape_text (node.text));
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
                sb.append (Markup.escape_text (alt != "" ? alt : "image"));
                sb.append ("</i>");
                break;
            default:
                markup_children (sb, node, in_link);
                break;
            }
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
            // Duplicates are numbered once the whole note is known, in collect ().
            current.slugs += sb.str;
            current.headings.add (widget);
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

        GtkSource.StyleScheme? code_scheme () {
            return GtkSource.StyleSchemeManager.get_default ().get_scheme (dark ? "Adwaita-dark" : "Adwaita");
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
            buffer.style_scheme = code_scheme ();

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
