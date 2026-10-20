/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Class diagrams. The syntax follows Mermaid 12.2.0's
 * src/diagrams/class/parser/classDiagram.jison and classDb.ts, and the
 * drawing its rendering-elements/shapes/classBox.ts.
 * Copyright (c) 2014-2022 Knut Sveidqvist and Mermaid contributors. MIT License.
 */

namespace Mermaid {

    internal class ClassInfo {
        public string id;
        public string label;
        public GenericArray<string> annotations = new GenericArray<string> ();
        public GenericArray<string> attributes = new GenericArray<string> ();
        public GenericArray<string> methods = new GenericArray<string> ();
        public string? namespace_name;
        public GenericArray<string> classes = new GenericArray<string> ();
        public CssStyle style = new CssStyle ();
    }

    internal class ClassRelation {
        public string from;
        public string to;
        public Marker from_marker = Marker.NONE;
        public Marker to_marker = Marker.NONE;
        public bool dashed;
        public string label = "";
        public string from_cardinality = "";
        public string to_cardinality = "";
    }

    internal class ClassNote {
        public string id;
        public string text;
        public string? target;
    }

    /* A class drawn as a box with its name, attributes and methods. */
    internal class ClassBox : GNode {
        public string[] annotations = {};
        public string[] attributes = {};
        public string[] methods = {};
        Size head;
        Size attrs;
        Size meths;
        const double PAD = 10;
        const double ROW_GAP = 6;

        public ClassBox (string id) {
            base (id);
        }

        string header_markup () {
            var sb = new StringBuilder ();
            foreach (unowned string a in annotations) {
                sb.append ("<small>«%s»</small>\n".printf (a));
            }
            sb.append ("<b>%s</b>".printf (label));
            return sb.str;
        }

        public override void measure (TextMeasurer m) {
            head = Mermaid.measure (m, header_markup (), text_style);
            attrs = attributes.length > 0 ? Mermaid.measure (m, string.joinv ("\n", attributes), text_style)
                : Size () { width = 0, height = 0 };
            meths = methods.length > 0 ? Mermaid.measure (m, string.joinv ("\n", methods), text_style)
                : Size () { width = 0, height = 0 };
            width = double.max (head.width, double.max (attrs.width, meths.width)) + 2 * PAD;
            width = double.max (width, 60);
            height = head.height + attrs.height + meths.height + 2 * PAD + 4 * ROW_GAP;
        }

        public override Path outline () {
            var p = new Path ();
            p.rect (x - width / 2, y - height / 2, width, height);
            return p;
        }

        public override void draw (Scene scene) {
            double left = x - width / 2, top = y - height / 2;
            var s = scene.add_shape (outline (), fill, stroke, stroke_width);
            s.line_style = line_style;
            double cy = top + PAD;
            var t = scene.add_text (header_markup (), x, cy + head.height / 2, text_style);
            t.color = color;
            cy += head.height + PAD;
            separator (scene, left, cy);
            cy += ROW_GAP;
            if (attributes.length > 0) {
                var a = scene.add_text (string.joinv ("\n", attributes), left + PAD, cy + attrs.height / 2,
                                        text_style, Align.START);
                a.color = color;
            }
            cy += attrs.height + ROW_GAP;
            separator (scene, left, cy);
            cy += ROW_GAP;
            if (methods.length > 0) {
                var mt = scene.add_text (string.joinv ("\n", methods), left + PAD, cy + meths.height / 2,
                                         text_style, Align.START);
                mt.color = color;
            }
        }

        void separator (Scene scene, double left, double y) {
            var line = new Path ();
            line.move_to (left, y);
            line.line_to (left + width, y);
            scene.add_shape (line, Paint (Ink.NONE), stroke, stroke_width);
        }
    }

    internal class NoteNode : GNode {
        public NoteNode (string id) {
            base (id);
            padding = 10;
            fill = Paint (Ink.NOTE_FILL);
            stroke = Paint (Ink.NOTE_STROKE);
        }

        public override void measure (TextMeasurer m) {
            var size = Mermaid.measure (m, label, text_style);
            width = size.width + 2 * padding;
            height = size.height + 2 * padding;
        }
    }

    public class ClassDiagram : Diagram {
        public override string kind {
            get { return "class"; }
        }

        internal string direction = "TB";
        internal Dagre.Dict<ClassInfo> classes = new Dagre.Dict<ClassInfo> ();
        internal GenericArray<ClassRelation> relations = new GenericArray<ClassRelation> ();
        internal GenericArray<ClassNote> notes = new GenericArray<ClassNote> ();
        internal GenericArray<string> namespaces = new GenericArray<string> ();
        internal HashTable<string, CssStyle> styles = new HashTable<string, CssStyle> (str_hash, str_equal);

        internal ClassInfo class_info (string id) {
            var c = classes[id];
            if (c == null) {
                c = new ClassInfo ();
                c.id = id;
                c.label = id;
                classes[id] = c;
            }
            return c;
        }

        /* A member as displayed: generics in angle brackets, static underlined, abstract in italics. */
        internal static string member_markup (string text, out bool is_method) {
            string t = text.strip ();
            bool is_static = false, is_abstract = false;
            is_method = t.contains (")");
            if (is_method) {
                int close = t.last_index_of_char (')');
                string after = t.substring (close + 1).strip ();
                if (after.has_prefix ("$")) {
                    is_static = true;
                    after = after.substring (1).strip ();
                } else if (after.has_prefix ("*")) {
                    is_abstract = true;
                    after = after.substring (1).strip ();
                }
                t = t.substring (0, close + 1);
                if (after != "") {
                    t += " : " + after;
                }
            } else if (t.has_suffix ("$")) {
                is_static = true;
                t = t.substring (0, t.length - 1);
            } else if (t.has_suffix ("*")) {
                is_abstract = true;
                t = t.substring (0, t.length - 1);
            }
            string markup = Label.escape (generics (t));
            if (is_static) {
                markup = "<u>" + markup + "</u>";
            }
            if (is_abstract) {
                markup = "<i>" + markup + "</i>";
            }
            return markup;
        }

        /* "List~int~" is written for "List<int>". */
        internal static string generics (string s) {
            var sb = new StringBuilder ();
            bool open = true;
            foreach (char c in s.to_utf8 ()) {
                if (c == '~') {
                    sb.append_c (open ? '<' : '>');
                    open = !open;
                } else {
                    sb.append_c (c);
                }
            }
            return sb.str;
        }

        void apply_style (GNode n, ClassInfo c) {
            var style = new CssStyle ();
            if (styles["default"] != null) {
                style.merge (styles["default"]);
            }
            foreach (unowned string cls in c.classes) {
                if (styles[cls] != null) {
                    style.merge (styles[cls]);
                }
            }
            style.merge (c.style);
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
        }

        internal override Scene build (TextMeasurer m) {
            var r = new GraphRender ();
            r.rankdir = direction;
            foreach (unowned string ns in namespaces) {
                var g = new GNode ("namespace:" + ns);
                g.is_group = true;
                g.label = Label.escape (ns);
                r.add_node (g);
            }
            foreach (var c in classes.values ()) {
                var box = new ClassBox (c.id);
                box.label = Label.escape (generics (c.label));
                string[] annotations = {};
                foreach (unowned string a in c.annotations) {
                    annotations += Label.escape (a);
                }
                box.annotations = annotations;
                string[] attrs = {}, meths = {};
                foreach (unowned string a in c.attributes) {
                    bool is_method;
                    attrs += member_markup (a, out is_method);
                }
                foreach (unowned string a in c.methods) {
                    bool is_method;
                    meths += member_markup (a, out is_method);
                }
                box.attributes = attrs;
                box.methods = meths;
                if (c.namespace_name != null) {
                    box.parent = "namespace:" + c.namespace_name;
                }
                apply_style (box, c);
                r.add_node (box);
            }
            foreach (var note in notes) {
                var n = new NoteNode (note.id);
                n.label = Label.from_text (note.text);
                r.add_node (n);
                if (note.target != null && r.node (note.target) != null) {
                    var e = new GEdge (note.id, note.target);
                    e.end_marker = Marker.NONE;
                    e.line_style = LineStyle.DASHED;
                    e.thickness = 1;
                    r.add_edge (e);
                }
            }
            foreach (var rel in relations) {
                var e = new GEdge (rel.from, rel.to);
                e.start_marker = rel.from_marker;
                e.end_marker = rel.to_marker;
                e.line_style = rel.dashed ? LineStyle.DASHED : LineStyle.SOLID;
                e.thickness = 1;
                e.label = Label.from_text (rel.label);
                e.start_label = rel.from_cardinality != "" ? Label.escape (rel.from_cardinality) : null;
                e.end_label = rel.to_cardinality != "" ? Label.escape (rel.to_cardinality) : null;
                r.add_edge (e);
            }
            return r.render (m);
        }
    }

    namespace ClassParser {

        class Parser {
            public ClassDiagram d = new ClassDiagram ();
            Source src;
            string? current_namespace;
            int note_count;

            public Parser (Source src) {
                this.src = src;
            }

            public void run (int first) throws ParseError {
                for (int i = first + 1; i < src.lines.length; i++) {
                    string l = src.lines[i].strip ();
                    if (l == "" || l.has_prefix ("%%")) {
                        continue;
                    }
                    if (common_statement (src, ref i, d)) {
                        continue;
                    }
                    statement (ref i, l);
                }
                if (current_namespace != null) {
                    throw syntax_error (src.lines.length - 1, "A namespace is missing its “}”");
                }
            }

            /* A class name: a word, "`any text`" or a name with ~generics~. */
            static string clean_name (string s) {
                string t = s.strip ();
                if (t.has_prefix ("`") && t.has_suffix ("`") && t.length >= 2) {
                    return t.substring (1, t.length - 2);
                }
                return t;
            }

            /* "Name", "Name~T~", "Name[\"Label\"]" and "Name:::cssClass". */
            ClassInfo class_ref (string text) {
                string t = text.strip ();
                string? css = null;
                int sep = t.index_of (":::");
                if (sep >= 0) {
                    css = t.substring (sep + 3).strip ();
                    t = t.substring (0, sep).strip ();
                }
                string? label = null;
                int bracket = t.index_of ("[");
                if (bracket > 0 && t.has_suffix ("]")) {
                    label = unquote (t.substring (bracket + 1, t.length - bracket - 2).strip ());
                    t = t.substring (0, bracket).strip ();
                }
                string id = clean_name (t);
                string? generic = null;
                int tilde = id.index_of_char ('~');
                if (tilde > 0) {
                    generic = id.substring (tilde);
                    id = id.substring (0, tilde);
                }
                var c = d.class_info (id);
                if (generic != null) {
                    c.label = id + generic;
                }
                if (label != null) {
                    c.label = label;
                }
                if (css != null) {
                    c.classes.add (css);
                }
                if (current_namespace != null && c.namespace_name == null) {
                    c.namespace_name = current_namespace;
                }
                return c;
            }

            void add_member (ClassInfo c, string member) {
                string m = member.strip ();
                if (m == "") {
                    return;
                }
                if (m.has_prefix ("<<") && m.has_suffix (">>")) {
                    c.annotations.add (m.substring (2, m.length - 4).strip ());
                    return;
                }
                if (m.contains ("(") && m.contains (")")) {
                    c.methods.add (m);
                } else {
                    c.attributes.add (m);
                }
            }

            static bool keyword (string l, string word, out string rest) {
                rest = "";
                if (l.has_prefix (word + " ") || l.has_prefix (word + "\t")) {
                    rest = l.substring (word.length).strip ();
                    return true;
                }
                return false;
            }

            void statement (ref int i, string l) throws ParseError {
                string rest;
                if (l == "}") {
                    if (current_namespace == null) {
                        throw syntax_error (i, "Unexpected “}”");
                    }
                    current_namespace = null;
                    return;
                }
                if (keyword (l, "direction", out rest)) {
                    string dir = rest == "TD" ? "TB" : rest;
                    if (!(dir in new string[] { "TB", "BT", "LR", "RL" })) {
                        throw syntax_error (i, "Unknown direction “%s”".printf (rest));
                    }
                    d.direction = dir;
                    return;
                }
                if (keyword (l, "namespace", out rest)) {
                    string name = rest;
                    if (name.has_suffix ("{")) {
                        name = name.substring (0, name.length - 1).strip ();
                    } else {
                        i++;
                        if (i >= src.lines.length || src.lines[i].strip () != "{") {
                            throw syntax_error (i, "Expected “{” after the namespace name");
                        }
                    }
                    current_namespace = name;
                    if (!(name in d.namespaces.data)) {
                        d.namespaces.add (name);
                    }
                    return;
                }
                if (keyword (l, "class", out rest)) {
                    class_statement (ref i, rest);
                    return;
                }
                if (l.has_prefix ("<<")) {
                    // "<<interface>> Shape".
                    int close = l.index_of (">>");
                    if (close < 0) {
                        throw syntax_error (i, "An annotation needs “>>”");
                    }
                    string annotation = l.substring (2, close - 2).strip ();
                    var c = class_ref (l.substring (close + 2));
                    c.annotations.add (annotation);
                    return;
                }
                if (keyword (l, "note", out rest)) {
                    note_statement (i, rest);
                    return;
                }
                if (keyword (l, "classDef", out rest)) {
                    int sp = rest.index_of_char (' ');
                    if (sp < 0) {
                        throw syntax_error (i, "Expected styles after the class name");
                    }
                    foreach (unowned string name in rest.substring (0, sp).split (",")) {
                        var style = d.styles[name];
                        if (style == null) {
                            style = new CssStyle ();
                            d.styles[name] = style;
                        }
                        style.apply (rest.substring (sp + 1));
                    }
                    return;
                }
                if (keyword (l, "cssClass", out rest)) {
                    // cssClass "A,B" className
                    int q = rest.last_index_of_char ('"');
                    if (q <= 0) {
                        throw syntax_error (i, "Expected cssClass \"Classes\" name");
                    }
                    string ids = rest.substring (1, q - 1);
                    string cls = rest.substring (q + 1).strip ();
                    foreach (unowned string id in ids.split (",")) {
                        d.class_info (id.strip ()).classes.add (cls);
                    }
                    return;
                }
                if (keyword (l, "style", out rest)) {
                    int sp = rest.index_of_char (' ');
                    if (sp < 0) {
                        throw syntax_error (i, "Expected styles after the class");
                    }
                    d.class_info (rest.substring (0, sp)).style.apply (rest.substring (sp + 1));
                    return;
                }
                if (keyword (l, "click", out rest) || keyword (l, "link", out rest) || keyword (l, "callback", out rest)) {
                    return;
                }
                if (try_relation (i, l)) {
                    return;
                }
                int colon = l.index_of_char (':');
                if (colon > 0 && l.index_of (":::") != colon) {
                    // "Animal : +int age".
                    var c = class_ref (l.substring (0, colon));
                    add_member (c, l.substring (colon + 1));
                    return;
                }
                if (!l.contains (" ") || l.has_prefix ("`")) {
                    class_ref (l);
                    return;
                }
                throw syntax_error (i, "Unexpected “%s”".printf (l));
            }

            void class_statement (ref int i, string rest) throws ParseError {
                string head = rest;
                bool body = false;
                int brace = head.index_of_char ('{');
                string inline_body = "";
                if (brace >= 0) {
                    body = true;
                    inline_body = head.substring (brace + 1);
                    head = head.substring (0, brace).strip ();
                }
                var c = class_ref (head);
                if (!body) {
                    return;
                }
                // Members until "}", possibly on the same line.
                string b = inline_body;
                while (true) {
                    int close = b.index_of_char ('}');
                    if (close >= 0) {
                        foreach (unowned string mem in b.substring (0, close).split ("\n")) {
                            add_member (c, mem);
                        }
                        return;
                    }
                    add_member (c, b);
                    i++;
                    if (i >= src.lines.length) {
                        throw syntax_error (i - 1, "The class “%s” is missing its “}”".printf (c.id));
                    }
                    b = src.lines[i];
                }
            }

            void note_statement (int i, string rest) throws ParseError {
                string target = null;
                string text = rest;
                if (rest.has_prefix ("for ")) {
                    string r = rest.substring (4).strip ();
                    int q = r.index_of_char ('"');
                    if (q < 0) {
                        throw syntax_error (i, "Expected note for CLASS \"text\"");
                    }
                    target = clean_name (r.substring (0, q));
                    text = r.substring (q);
                }
                text = text.strip ();
                if (text.has_prefix ("\"") && text.has_suffix ("\"") && text.length >= 2) {
                    text = text.substring (1, text.length - 2);
                }
                var note = new ClassNote ();
                note.id = "note%d".printf (++note_count);
                note.text = text.replace ("\\n", "<br>");
                note.target = target;
                d.notes.add (note);
            }

            /*
             * "A <|-- B", "A \"1\" --> \"*\" B : label", "A ()-- B" and the
             * other relation forms.
             */
            bool try_relation (int i, string l) throws ParseError {
                // The label after the relation.
                string body = l;
                string label = "";
                int colon = find_label_colon (l);
                if (colon >= 0) {
                    label = l.substring (colon + 1).strip ();
                    body = l.substring (0, colon);
                }
                // Find the line: "--" or "..".
                int line_at = -1;
                bool dashed = false;
                bool quoted = false;
                for (int p = 0; p + 1 < body.length; p++) {
                    if (body[p] == '"') {
                        quoted = !quoted;
                    }
                    if (quoted) {
                        continue;
                    }
                    if ((body[p] == '-' && body[p + 1] == '-') || (body[p] == '.' && body[p + 1] == '.')) {
                        line_at = p;
                        dashed = body[p] == '.';
                        break;
                    }
                }
                if (line_at < 0) {
                    return false;
                }
                string left = body.substring (0, line_at);
                string right = body.substring (line_at + 2);

                Marker from_marker = Marker.NONE, to_marker = Marker.NONE;
                string lt = left.chomp ();
                if (lt.has_suffix ("<|")) {
                    from_marker = Marker.EXTENSION;
                    lt = lt.substring (0, lt.length - 2);
                } else if (lt.has_suffix ("()")) {
                    from_marker = Marker.LOLLIPOP;
                    lt = lt.substring (0, lt.length - 2);
                } else if (lt.has_suffix ("*")) {
                    from_marker = Marker.COMPOSITION;
                    lt = lt.substring (0, lt.length - 1);
                } else if (lt.has_suffix ("o") && lt.length >= 2 && (lt[lt.length - 2] == ' ' || lt[lt.length - 2] == '"')) {
                    from_marker = Marker.AGGREGATION;
                    lt = lt.substring (0, lt.length - 1);
                } else if (lt.has_suffix ("<")) {
                    from_marker = Marker.DEPENDENCY;
                    lt = lt.substring (0, lt.length - 1);
                }
                string rt = right.chug ();
                if (rt.has_prefix ("|>")) {
                    to_marker = Marker.EXTENSION;
                    rt = rt.substring (2);
                } else if (rt.has_prefix ("()")) {
                    to_marker = Marker.LOLLIPOP;
                    rt = rt.substring (2);
                } else if (rt.has_prefix ("*")) {
                    to_marker = Marker.COMPOSITION;
                    rt = rt.substring (1);
                } else if (rt.has_prefix ("o") && rt.length >= 2 && (rt[1] == ' ' || rt[1] == '"')) {
                    to_marker = Marker.AGGREGATION;
                    rt = rt.substring (1);
                } else if (rt.has_prefix (">")) {
                    to_marker = Marker.DEPENDENCY;
                    rt = rt.substring (1);
                }

                string from_card = "", to_card = "";
                lt = lt.strip ();
                rt = rt.strip ();
                if (lt.has_suffix ("\"") && lt.length >= 2) {
                    int q = lt.length - 2;
                    while (q >= 0 && lt[q] != '"') {
                        q--;
                    }
                    if (q >= 0) {
                        from_card = lt.substring (q + 1, lt.length - q - 2);
                        lt = lt.substring (0, q).strip ();
                    }
                }
                if (rt.has_prefix ("\"")) {
                    int q = rt.index_of_char ('"', 1);
                    if (q > 0) {
                        to_card = rt.substring (1, q - 1);
                        rt = rt.substring (q + 1).strip ();
                    }
                }
                if (lt == "" || rt == "") {
                    throw syntax_error (i, "A relation needs a class on both sides");
                }
                var rel = new ClassRelation ();
                rel.from = class_ref (lt).id;
                rel.to = class_ref (rt).id;
                rel.from_marker = from_marker;
                rel.to_marker = to_marker;
                rel.dashed = dashed;
                rel.label = label;
                rel.from_cardinality = from_card;
                rel.to_cardinality = to_card;
                d.relations.add (rel);
                return true;
            }

            static int find_label_colon (string l) {
                bool quoted = false;
                for (int k = 0; k < l.length; k++) {
                    if (l[k] == '"') {
                        quoted = !quoted;
                    } else if (l[k] == ':' && !quoted) {
                        if (k + 2 < l.length && l[k + 1] == ':' && l[k + 2] == ':') {
                            k += 2;
                            continue;
                        }
                        return k;
                    }
                }
                return -1;
            }
        }

        internal ClassDiagram parse (Source src, int first) throws ParseError {
            var p = new Parser (src);
            p.run (first);
            return p.d;
        }
    }
}
