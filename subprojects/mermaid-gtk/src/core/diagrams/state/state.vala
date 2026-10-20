/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * State diagrams. The syntax follows Mermaid 12.2.0's
 * src/diagrams/state/parser/stateDiagram.jison, the model its stateDb.ts and
 * the drawing its dataFetcher.ts.
 * Copyright (c) 2014-2022 Knut Sveidqvist and Mermaid contributors. MIT License.
 */

namespace Mermaid {

    internal enum StateType {
        DEFAULT,
        START,
        END,
        FORK,
        JOIN,
        CHOICE
    }

    /* A composite state's content, or one of its "--" separated regions. */
    internal class StateRegion {
        public string id;
        public StateItem? owner;
        public StateRegion? parent;
        public string? dir;
        /* Set when this region is one of several in its composite. */
        public bool divider;
        public StateItem? start;
        public StateItem? end;
    }

    internal class StateItem {
        public string id;
        public StateType type = StateType.DEFAULT;
        public GenericArray<string> descriptions = new GenericArray<string> ();
        public StateRegion? region;
        /* For composite states: their regions. */
        public GenericArray<StateRegion>? regions;
        public GenericArray<string> classes = new GenericArray<string> ();
        public CssStyle style = new CssStyle ();
        public string? note;
        public bool note_left;
    }

    internal class StateRelation {
        public StateItem from;
        public StateItem to;
        public string label = "";
    }

    /* A state with a title above its descriptions. */
    internal class StateBox : GNode {
        public string[] lines = {};
        public string? note;
        public bool note_left;
        Size title;
        Size body;
        Size note_size;
        double state_width;
        const double NOTE_GAP = 24;

        public StateBox (string id) {
            base (id);
            shape = ShapeKind.ROUNDED;
            padding = 8;
        }

        public override void measure (TextMeasurer m) {
            title = Mermaid.measure (m, label, text_style);
            if (lines.length > 0) {
                body = Mermaid.measure (m, string.joinv ("\n", lines), text_style);
                state_width = double.max (title.width, body.width) + 2 * padding + 10;
                height = title.height + body.height + 4 * padding;
            } else {
                state_width = title.width + 4 * padding;
                height = title.height + 2 * padding;
            }
            width = state_width;
            if (note != null) {
                note_size = Mermaid.measure (m, note, text_style);
                width += NOTE_GAP + note_size.width + 2 * padding;
                height = double.max (height, note_size.height + 2 * padding);
            }
        }

        public override double anchor_x () {
            return state_x ();
        }

        /* The center of the state itself, which shares the node with its note. */
        double state_x () {
            if (note == null) {
                return x;
            }
            return note_left ? x + width / 2 - state_width / 2 : x - width / 2 + state_width / 2;
        }

        double state_height () {
            return lines.length > 0 ? title.height + body.height + 4 * padding : title.height + 2 * padding;
        }

        public override Path outline () {
            var p = new Path ();
            double sh = state_height ();
            p.rounded_rect (state_x () - state_width / 2, y - sh / 2, state_width, sh, 5);
            return p;
        }

        public override void draw (Scene scene) {
            double sx = state_x (), sh = state_height ();
            var s = scene.add_shape (outline (), fill, stroke, stroke_width);
            s.line_style = line_style;
            double top = y - sh / 2;
            if (lines.length > 0) {
                var t = scene.add_text (label, sx, top + padding + title.height / 2, text_style);
                t.color = color;
                var line = new Path ();
                double ly = top + 2 * padding + title.height;
                line.move_to (sx - state_width / 2, ly);
                line.line_to (sx + state_width / 2, ly);
                scene.add_shape (line, Paint (Ink.NONE), stroke, stroke_width);
                var b = scene.add_text (string.joinv ("\n", lines), sx - state_width / 2 + padding,
                                        ly + padding + body.height / 2, text_style, Align.START);
                b.color = color;
            } else {
                var t = scene.add_text (label, sx, y, text_style);
                t.color = color;
            }
            if (note != null) {
                double nw = note_size.width + 2 * padding, nh = note_size.height + 2 * padding;
                double nx = note_left ? x - width / 2 : x + width / 2 - nw;
                var box = new Path ();
                box.rect (nx, y - nh / 2, nw, nh);
                scene.add_shape (box, Paint (Ink.NOTE_FILL), Paint (Ink.NOTE_STROKE));
                var link = new Path ();
                double from = note_left ? nx + nw : nx;
                double to = note_left ? sx - state_width / 2 : sx + state_width / 2;
                link.move_to (from, y);
                link.line_to (to, y);
                var l = scene.add_shape (link, Paint (Ink.NONE), Paint (Ink.NOTE_STROKE));
                l.line_style = LineStyle.DASHED;
                scene.add_text (note, nx + nw / 2, y, text_style);
            }
        }
    }

    public class StateDiagram : Diagram {
        public override string kind {
            get { return "state"; }
        }

        internal StateRegion root = new StateRegion ();
        internal Dagre.Dict<StateItem> states = new Dagre.Dict<StateItem> ();
        internal GenericArray<StateRelation> relations = new GenericArray<StateRelation> ();
        internal HashTable<string, CssStyle> classes = new HashTable<string, CssStyle> (str_hash, str_equal);
        internal GenericArray<StateRegion> regions = new GenericArray<StateRegion> ();

        construct {
            root.id = "root";
            regions.add (root);
        }

        internal StateItem get_state (string id, StateRegion region) {
            var s = states[id];
            if (s == null) {
                s = new StateItem ();
                s.id = id;
                s.region = region;
                states[id] = s;
            }
            return s;
        }

        /* The region's own start or end point, for "[*]". */
        internal StateItem terminal (StateRegion region, bool start) {
            var existing = start ? region.start : region.end;
            if (existing != null) {
                return existing;
            }
            var s = new StateItem ();
            s.type = start ? StateType.START : StateType.END;
            s.region = region;
            if (start) {
                region.start = s;
            } else {
                region.end = s;
            }
            return s;
        }

        string node_id (StateItem s) {
            if (s.type == StateType.START) {
                return s.region.id + "_start";
            }
            if (s.type == StateType.END) {
                return s.region.id + "_end";
            }
            return s.id;
        }

        /* The group a state is drawn in: its region, or its composite state. */
        string? group_of (StateRegion? region) {
            if (region == null || region == root) {
                return null;
            }
            return region.divider ? region.id : region.owner.id;
        }

        void apply_style (GNode n, StateItem s) {
            var style = new CssStyle ();
            if (classes["default"] != null) {
                style.merge (classes["default"]);
            }
            foreach (unowned string c in s.classes) {
                if (classes[c] != null) {
                    style.merge (classes[c]);
                }
            }
            style.merge (s.style);
            if (style.fill != null) {
                n.fill = style.fill;
            }
            if (style.stroke != null) {
                n.stroke = style.stroke;
            }
            if (style.color != null) {
                n.color = style.color;
            }
            if (style.stroke_width >= 0) {
                n.stroke_width = style.stroke_width;
            }
            if (style.dashed) {
                n.line_style = LineStyle.DASHED;
            }
            if (style.bold) {
                n.text_style.bold = true;
            }
            if (style.italic) {
                n.text_style.italic = true;
            }
        }

        void add_node (GraphRender r, StateItem s) {
            if (r.node (node_id (s)) != null) {
                return;
            }
            bool horizontal = root.dir == "LR" || root.dir == "RL";
            GNode n;
            switch (s.type) {
            case StateType.START:
                n = new GNode (node_id (s));
                n.shape = ShapeKind.SMALL_CIRCLE;
                break;
            case StateType.END:
                n = new GNode (node_id (s));
                n.shape = ShapeKind.FRAMED_CIRCLE;
                break;
            case StateType.FORK:
            case StateType.JOIN:
                n = new GNode (s.id);
                n.shape = ShapeKind.FORK;
                n.width = horizontal ? 10 : 70;
                n.height = horizontal ? 70 : 10;
                break;
            case StateType.CHOICE:
                n = new GNode (s.id);
                n.shape = ShapeKind.DIAMOND;
                n.width = n.height = 28;
                break;
            default:
                if (s.regions != null) {
                    n = new GNode (s.id);
                    n.is_group = true;
                    n.group_style = GroupStyle.STATE;
                    n.label = Label.from_text (s.descriptions.length == 1 ? s.descriptions[0] : s.id);
                    n.dir = s.regions[0].dir;
                } else {
                    var box = new StateBox (s.id);
                    if (s.descriptions.length == 1) {
                        box.label = Label.from_text (s.descriptions[0]);
                    } else {
                        box.label = Label.from_text (s.id);
                        string[] lines = {};
                        foreach (unowned string d in s.descriptions) {
                            lines += Label.from_text (d);
                        }
                        box.lines = lines;
                    }
                    if (s.note != null) {
                        box.note = Label.from_text (s.note);
                        box.note_left = s.note_left;
                    }
                    n = box;
                }
                apply_style (n, s);
                break;
            }
            n.parent = group_of (s.region);
            r.add_node (n);
        }

        internal override Scene build (TextMeasurer m) {
            var r = new GraphRender ();
            r.rankdir = root.dir ?? "TB";

            // Regions of composites with "--" are groups of their own.
            foreach (var region in regions) {
                if (region.divider) {
                    var n = new GNode (region.id);
                    n.is_group = true;
                    n.group_style = GroupStyle.DIVIDER;
                    n.parent = region.owner.id;
                    n.dir = region.dir;
                    r.add_node (n);
                }
            }
            foreach (var s in states.values ()) {
                add_node (r, s);
            }
            foreach (var region in regions) {
                if (region.start != null) {
                    add_node (r, region.start);
                }
                if (region.end != null) {
                    add_node (r, region.end);
                }
            }
            foreach (var rel in relations) {
                var e = new GEdge (node_id (rel.from), node_id (rel.to));
                e.label = Label.from_text (rel.label);
                e.thickness = 1;
                r.add_edge (e);
            }
            return r.render (m);
        }
    }

    namespace StateParser {

        class Parser {
            public StateDiagram d = new StateDiagram ();
            Source src;
            GenericArray<StateRegion> stack = new GenericArray<StateRegion> ();
            int divider_count;

            public Parser (Source src) {
                this.src = src;
                stack.add (d.root);
            }

            StateRegion region {
                get { return stack[stack.length - 1]; }
            }

            public void run (int first) throws ParseError {
                for (int i = first + 1; i < src.lines.length; i++) {
                    string l = src.lines[i].strip ();
                    if (l == "" || l.has_prefix ("#") || l.has_prefix ("%%")) {
                        continue;
                    }
                    if (common_statement (src, ref i, d, false)) {
                        continue;
                    }
                    statement (ref i, l);
                }
                if (stack.length > 1) {
                    throw syntax_error (src.lines.length - 1, "A composite state is missing its “}”");
                }
            }

            /* The state for an id as written, handling "[*]" and ":::class". */
            StateItem ref_state (string text, bool as_start) {
                string id = text.strip ();
                string? cls = null;
                int sep = id.index_of (":::");
                if (sep >= 0) {
                    cls = id.substring (sep + 3).strip ();
                    id = id.substring (0, sep).strip ();
                }
                StateItem s;
                if (id == "[*]") {
                    s = d.terminal (region, as_start);
                } else {
                    s = d.get_state (id, region);
                }
                if (cls != null) {
                    s.classes.add (cls);
                }
                return s;
            }

            void statement (ref int i, string l) throws ParseError {
                if (l == "}") {
                    if (stack.length <= 1) {
                        throw syntax_error (i, "Unexpected “}”");
                    }
                    // Pop the composite and any of its regions.
                    var owner = region.owner;
                    while (stack.length > 1 && region.owner == owner) {
                        stack.remove_index (stack.length - 1);
                    }
                    return;
                }
                if (l == "--") {
                    divide (i);
                    return;
                }
                if (l.has_prefix ("direction ") || l.has_prefix ("direction\t")) {
                    string dir = l.substring (10).strip ();
                    if (dir == "TD") {
                        dir = "TB";
                    }
                    if (!(dir in new string[] { "TB", "BT", "LR", "RL" })) {
                        throw syntax_error (i, "Unknown direction “%s”".printf (dir));
                    }
                    region.dir = dir;
                    if (region.owner != null && region.owner.regions != null) {
                        foreach (var rg in region.owner.regions) {
                            if (rg.dir == null) {
                                rg.dir = dir;
                            }
                        }
                    }
                    return;
                }
                if (l.has_prefix ("hide empty description") || l.has_prefix ("scale ") || l.has_prefix ("click ")) {
                    return;
                }
                if (l.has_prefix ("classDef ")) {
                    string rest = l.substring (9).strip ();
                    int sp = first_space (rest);
                    if (sp < 0) {
                        throw syntax_error (i, "Expected styles after the class name");
                    }
                    string name = rest.substring (0, sp);
                    var cls = d.classes[name];
                    if (cls == null) {
                        cls = new CssStyle ();
                        d.classes[name] = cls;
                    }
                    cls.apply (rest.substring (sp + 1));
                    return;
                }
                if (l.has_prefix ("class ")) {
                    string rest = l.substring (6).strip ();
                    int sp = rest.last_index_of_char (' ');
                    if (sp < 0) {
                        throw syntax_error (i, "Expected “class STATES CLASS”");
                    }
                    string cls = rest.substring (sp + 1).strip ();
                    foreach (unowned string id in rest.substring (0, sp).split (",")) {
                        d.get_state (id.strip (), region).classes.add (cls);
                    }
                    return;
                }
                if (l.has_prefix ("style ")) {
                    string rest = l.substring (6).strip ();
                    int sp = first_space (rest);
                    if (sp < 0) {
                        throw syntax_error (i, "Expected styles after the state");
                    }
                    foreach (unowned string id in rest.substring (0, sp).split (",")) {
                        d.get_state (id.strip (), region).style.apply (rest.substring (sp + 1));
                    }
                    return;
                }
                if (l.has_prefix ("note ")) {
                    note (ref i, l);
                    return;
                }
                if (l.has_prefix ("state ")) {
                    state_statement (i, l.substring (6).strip ());
                    return;
                }

                int arrow = l.index_of ("-->");
                if (arrow >= 0) {
                    string left = l.substring (0, arrow);
                    string right = l.substring (arrow + 3);
                    string label = "";
                    int colon = label_colon (right);
                    if (colon >= 0) {
                        label = right.substring (colon + 1).strip ();
                        right = right.substring (0, colon);
                    }
                    if (left.strip () == "" || right.strip () == "") {
                        throw syntax_error (i, "A transition needs a state on both sides of “-->”");
                    }
                    var rel = new StateRelation ();
                    rel.from = ref_state (left, true);
                    rel.to = ref_state (right, false);
                    rel.label = label;
                    d.relations.add (rel);
                    return;
                }

                int colon = l.index_of_char (':');
                if (colon > 0 && !l.has_prefix (":::") && l.index_of (":::") != colon) {
                    var s = ref_state (l.substring (0, colon), true);
                    s.descriptions.add (l.substring (colon + 1).strip ());
                    return;
                }
                if (l.contains (" ") && !l.contains (":::")) {
                    throw syntax_error (i, "Unexpected “%s”".printf (l));
                }
                ref_state (l, true);
            }

            /* The ":" that starts a label, skipping ":::class". */
            static int label_colon (string s) {
                for (int k = 0; k < s.length; k++) {
                    if (s[k] == ':') {
                        if (k + 2 < s.length && s[k + 1] == ':' && s[k + 2] == ':') {
                            k += 2;
                            continue;
                        }
                        return k;
                    }
                }
                return -1;
            }

            static int first_space (string s) {
                for (int k = 0; k < s.length; k++) {
                    if (s[k].isspace ()) {
                        return k;
                    }
                }
                return -1;
            }

            /* "--" splits the current composite into regions. */
            void divide (int i) throws ParseError {
                var current = region;
                var owner = current.owner;
                if (owner == null) {
                    throw syntax_error (i, "“--” is only allowed inside a composite state");
                }
                if (!current.divider) {
                    // The content so far becomes the first region.
                    current.divider = true;
                    current.id = "divider-id-%d".printf (++divider_count);
                }
                var next = new StateRegion ();
                next.id = "divider-id-%d".printf (++divider_count);
                next.owner = owner;
                next.parent = current.parent;
                next.divider = true;
                next.dir = current.dir;
                owner.regions.add (next);
                d.regions.add (next);
                stack[stack.length - 1] = next;
            }

            void state_statement (int i, string text) throws ParseError {
                string rest = text;
                bool opens = rest.has_suffix ("{");
                if (opens) {
                    rest = rest.substring (0, rest.length - 1).strip ();
                }
                StateItem s;
                if (rest.has_prefix ("\"")) {
                    int end = rest.index_of_char ('"', 1);
                    if (end < 0) {
                        throw syntax_error (i, "The state description has no closing quote");
                    }
                    string descr = rest.substring (1, end - 1);
                    string after = rest.substring (end + 1).strip ();
                    if (!after.has_prefix ("as ")) {
                        throw syntax_error (i, "Expected “as ID” after the description");
                    }
                    s = ref_state (after.substring (3).strip (), true);
                    s.descriptions.add (descr);
                } else {
                    string id = rest;
                    StateType type = StateType.DEFAULT;
                    foreach (unowned string marker in new string[] { "<<fork>>", "[[fork]]" }) {
                        if (id.has_suffix (marker)) {
                            type = StateType.FORK;
                            id = id.substring (0, id.length - marker.length).strip ();
                        }
                    }
                    foreach (unowned string marker in new string[] { "<<join>>", "[[join]]" }) {
                        if (id.has_suffix (marker)) {
                            type = StateType.JOIN;
                            id = id.substring (0, id.length - marker.length).strip ();
                        }
                    }
                    foreach (unowned string marker in new string[] { "<<choice>>", "[[choice]]" }) {
                        if (id.has_suffix (marker)) {
                            type = StateType.CHOICE;
                            id = id.substring (0, id.length - marker.length).strip ();
                        }
                    }
                    string? descr = null;
                    int colon = id.index_of_char (':');
                    if (colon > 0 && id.index_of (":::") != colon) {
                        descr = id.substring (colon + 1).strip ();
                        id = id.substring (0, colon).strip ();
                    }
                    if (id.contains (" ") && !id.contains (":::")) {
                        throw syntax_error (i, "State names must be a single word, “%s” isn't".printf (id));
                    }
                    s = ref_state (id, true);
                    if (type != StateType.DEFAULT) {
                        s.type = type;
                    }
                    if (descr != null) {
                        s.descriptions.add (descr);
                    }
                }
                if (opens) {
                    if (s.regions == null) {
                        s.regions = new GenericArray<StateRegion> ();
                        var inner = new StateRegion ();
                        inner.id = s.id;
                        inner.owner = s;
                        inner.parent = region;
                        s.regions.add (inner);
                        d.regions.add (inner);
                    }
                    stack.add (s.regions[s.regions.length - 1]);
                }
            }

            void note (ref int i, string l) throws ParseError {
                string rest = l.substring (5).strip ();
                bool left;
                if (rest.has_prefix ("left of ")) {
                    left = true;
                    rest = rest.substring (8).strip ();
                } else if (rest.has_prefix ("right of ")) {
                    left = false;
                    rest = rest.substring (9).strip ();
                } else if (rest.has_prefix ("\"")) {
                    // Floating notes aren't drawn.
                    return;
                } else {
                    throw syntax_error (i, "Expected “left of” or “right of” after “note”");
                }
                string id;
                string text;
                int colon = rest.index_of_char (':');
                if (colon >= 0) {
                    id = rest.substring (0, colon).strip ();
                    text = rest.substring (colon + 1).strip ();
                } else {
                    id = rest.strip ();
                    var sb = new StringBuilder ();
                    bool closed = false;
                    while (i + 1 < src.lines.length) {
                        i++;
                        string line = src.lines[i].strip ();
                        if (line == "end note") {
                            closed = true;
                            break;
                        }
                        if (sb.len > 0) {
                            sb.append_c ('\n');
                        }
                        sb.append (line);
                    }
                    if (!closed) {
                        throw syntax_error (i, "A note is missing its “end note”");
                    }
                    text = sb.str;
                }
                var s = ref_state (id, true);
                s.note = text;
                s.note_left = left;
            }
        }

        internal StateDiagram parse (Source src, int first) throws ParseError {
            var p = new Parser (src);
            p.run (first);
            return p.d;
        }
    }
}
