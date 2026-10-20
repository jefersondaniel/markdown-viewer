/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Flowcharts. The parser follows the grammar in Mermaid 12.2.0's
 * src/diagrams/flowchart/parser/flow.jison and the model its flowDb.ts.
 * Copyright (c) 2014-2022 Knut Sveidqvist and Mermaid contributors. MIT License.
 */

namespace Mermaid {

    internal class FlowVertex {
        public string id;
        public string? text;
        public bool markdown;
        public ShapeKind shape = ShapeKind.RECT;
        public bool has_shape;
        public CssStyle style = new CssStyle ();
        public GenericArray<string> classes = new GenericArray<string> ();
    }

    internal class FlowEdge {
        public string start;
        public string end;
        public string? id;
        public string text = "";
        public bool markdown;
        /* "arrow_point", "arrow_open", "double_arrow_cross" and so on. */
        public string type = "arrow_point";
        /* "normal", "thick", "dotted" or "invisible". */
        public string stroke = "normal";
        public int length = 1;
        public CssStyle style = new CssStyle ();
        public Curve? curve;
    }

    internal class FlowSubgraph {
        public string id;
        public string title;
        public bool markdown;
        public GenericArray<string> nodes = new GenericArray<string> ();
        public string? dir;
        public GenericArray<string> classes = new GenericArray<string> ();
        public CssStyle style = new CssStyle ();
    }

    public class FlowchartDiagram : Diagram {
        public override string kind {
            get { return "flowchart"; }
        }

        internal string direction = "TB";
        internal Dagre.Dict<FlowVertex> vertices = new Dagre.Dict<FlowVertex> ();
        internal GenericArray<FlowEdge> edges = new GenericArray<FlowEdge> ();
        internal GenericArray<FlowSubgraph> subgraphs = new GenericArray<FlowSubgraph> ();
        internal HashTable<string, CssStyle> classes = new HashTable<string, CssStyle> (str_hash, str_equal);
        internal CssStyle? default_link_style;
        internal Curve? default_curve;

        internal FlowVertex add_vertex (string id) {
            var v = vertices[id];
            if (v == null) {
                v = new FlowVertex ();
                v.id = id;
                vertices[id] = v;
            }
            return v;
        }

        internal FlowSubgraph? find_subgraph (string id) {
            foreach (var sg in subgraphs) {
                if (sg.id == id) {
                    return sg;
                }
            }
            return null;
        }

        CssStyle compiled_style (GenericArray<string> class_names, bool with_default) {
            var result = new CssStyle ();
            if (with_default && classes["default"] != null) {
                result.merge (classes["default"]);
            }
            foreach (unowned string c in class_names) {
                var cls = classes[c];
                if (cls != null) {
                    result.merge (cls);
                }
            }
            return result;
        }

        static void apply_style (GNode n, CssStyle s) {
            if (s.fill != null) {
                n.fill = s.fill;
            }
            if (s.stroke != null) {
                n.stroke = s.stroke;
            }
            if (s.color != null) {
                n.color = s.color;
            }
            if (s.stroke_width >= 0) {
                n.stroke_width = s.stroke_width;
            }
            if (s.dashed) {
                n.line_style = LineStyle.DASHED;
            }
            if (s.bold) {
                n.text_style.bold = true;
            }
            if (s.italic) {
                n.text_style.italic = true;
            }
        }

        internal static string label_markup (string text, bool markdown) {
            return Label.parse (text, markdown);
        }

        internal override Scene build (TextMeasurer m) {
            var r = new GraphRender ();
            r.rankdir = direction;

            // A node's parent is the innermost subgraph that lists it.
            var parent_of = new HashTable<string, string> (str_hash, str_equal);
            for (int i = subgraphs.length - 1; i >= 0; i--) {
                foreach (unowned string id in subgraphs[i].nodes) {
                    parent_of[id] = subgraphs[i].id;
                }
            }

            for (int i = subgraphs.length - 1; i >= 0; i--) {
                var sg = subgraphs[i];
                var n = new GNode (sg.id);
                n.is_group = true;
                n.label = label_markup (sg.title, sg.markdown);
                n.parent = parent_of[sg.id];
                n.dir = sg.dir;
                apply_style (n, compiled_style (sg.classes, false));
                apply_style (n, sg.style);
                r.add_node (n);
            }

            foreach (var v in vertices.values ()) {
                if (r.node (v.id) != null) {
                    // A subgraph with the same id: styles apply to it.
                    var g = r.node (v.id);
                    apply_style (g, compiled_style (v.classes, false));
                    apply_style (g, v.style);
                    continue;
                }
                var n = new GNode (v.id);
                n.shape = v.shape;
                n.label = Shapes.unlabeled (v.shape) ? "" : label_markup (v.text ?? v.id, v.markdown);
                if (v.markdown) {
                    n.wrap_width = 200;
                }
                n.parent = parent_of[v.id];
                apply_style (n, compiled_style (v.classes, true));
                apply_style (n, v.style);
                r.add_node (n);
            }

            for (int i = 0; i < edges.length; i++) {
                var fe = edges[i];
                var e = new GEdge (fe.start, fe.end);
                e.label = label_markup (fe.text, fe.markdown);
                if (fe.markdown) {
                    e.label_size.width = 0;
                }
                e.minlen = fe.length;
                string type = fe.type;
                Marker start_marker = Marker.NONE, end_marker = Marker.NONE;
                if (type != "arrow_open") {
                    bool both = type.has_prefix ("double_");
                    string base_type = both ? type.substring (7) : type;
                    Marker mk = base_type == "arrow_circle" ? Marker.CIRCLE
                        : (base_type == "arrow_cross" ? Marker.CROSS : Marker.ARROW);
                    end_marker = mk;
                    if (both) {
                        start_marker = mk;
                    }
                }
                e.start_marker = start_marker;
                e.end_marker = end_marker;
                switch (fe.stroke) {
                case "thick":
                    e.thickness = 3.5;
                    break;
                case "dotted":
                    e.line_style = LineStyle.DOTTED;
                    break;
                case "invisible":
                    e.invisible = true;
                    break;
                }
                var style = new CssStyle ();
                if (default_link_style != null) {
                    style.merge (default_link_style);
                }
                style.merge (fe.style);
                if (style.stroke != null) {
                    e.stroke = style.stroke;
                }
                if (style.stroke_width >= 0) {
                    e.thickness = style.stroke_width;
                }
                if (style.color != null) {
                    e.label_color = style.color;
                }
                if (style.dashed) {
                    e.line_style = LineStyle.DASHED;
                }
                e.curve = fe.curve ?? default_curve ?? Curve.BASIS;
                r.add_edge (e);
            }
            return r.render (m);
        }
    }

    namespace FlowchartParser {

        /* The parts of a link, from destructLink in flowDb.ts. */
        class Link {
            public string type = "arrow_open";
            public string stroke = "normal";
            public int length = 1;
            public string? text;
            public bool markdown;
            public string? id;
        }

        class Frame {
            public string? id;
            public string title = "";
            public bool markdown;
            public GenericArray<string> members = new GenericArray<string> ();
            public string? dir;
        }

        class Parser {
            public FlowchartDiagram d = new FlowchartDiagram ();
            Scanner s;
            GenericArray<Frame> frames = new GenericArray<Frame> ();
            int sub_count;

            public Parser (Scanner s) {
                this.s = s;
                frames.add (new Frame ());
            }

            Frame frame {
                get { return frames[frames.length - 1]; }
            }

            public void run () throws ParseError {
                while (true) {
                    skip_separators ();
                    if (s.eof) {
                        break;
                    }
                    statement ();
                }
                if (frames.length > 1) {
                    throw s.error ("A subgraph is missing its “end”");
                }
            }

            void skip_separators () {
                while (!s.eof) {
                    char c = s.peek ();
                    if (c == ' ' || c == '\t' || c == '\n' || c == ';' || c == '\r') {
                        s.pos++;
                    } else {
                        break;
                    }
                }
            }

            void expect_end_of_statement () throws ParseError {
                s.skip_spaces ();
                if (s.eof || s.peek () == '\n' || s.peek () == ';') {
                    return;
                }
                throw s.error ("Unexpected %s".printf (s.excerpt ()));
            }

            void statement () throws ParseError {
                if (s.at_word ("subgraph")) {
                    s.pos += 8;
                    subgraph_start ();
                    return;
                }
                if (s.at_word ("end") && frames.length > 1) {
                    s.pos += 3;
                    subgraph_end ();
                    return;
                }
                if (s.at_word ("direction")) {
                    s.pos += 9;
                    string dir = s.rest_of_statement ().strip ();
                    if (dir == "TD") {
                        dir = "TB";
                    }
                    if (!(dir in new string[] { "TB", "BT", "LR", "RL" })) {
                        throw s.error ("Unknown direction “%s”".printf (dir));
                    }
                    frame.dir = dir;
                    return;
                }
                if (s.at_word ("style")) {
                    s.pos += 5;
                    s.skip_spaces ();
                    string id = read_id ();
                    string css = s.rest_of_line ();
                    var v = d.add_vertex (id);
                    v.style.apply (css);
                    var sg = d.find_subgraph (id);
                    if (sg != null) {
                        sg.style.apply (css);
                    }
                    return;
                }
                if (s.at_word ("classDef")) {
                    s.pos += 8;
                    s.skip_spaces ();
                    string names = read_word ();
                    string css = s.rest_of_line ();
                    foreach (unowned string name in names.split (",")) {
                        var cls = d.classes[name];
                        if (cls == null) {
                            cls = new CssStyle ();
                            d.classes[name] = cls;
                        }
                        cls.apply (css);
                    }
                    return;
                }
                if (s.at_word ("class")) {
                    s.pos += 5;
                    s.skip_spaces ();
                    string ids = read_word ();
                    s.skip_spaces ();
                    string cls = s.rest_of_statement ().strip ();
                    foreach (unowned string id in ids.split (",")) {
                        set_class (id.strip (), cls);
                    }
                    return;
                }
                if (s.at_word ("linkStyle")) {
                    s.pos += 9;
                    link_style ();
                    return;
                }
                if (s.at_word ("click")) {
                    // Interaction isn't supported; the statement is ignored.
                    s.rest_of_line ();
                    return;
                }
                if (s.at ("accTitle") || s.at ("accDescr")) {
                    acc_statement ();
                    return;
                }
                vertex_statement ();
            }

            void acc_statement () {
                bool title = s.at ("accTitle");
                s.pos += 8;
                s.skip_spaces ();
                if (s.accept (":")) {
                    string value = s.rest_of_line ().strip ();
                    if (title) {
                        d.accessible_title = value;
                    } else {
                        d.accessible_description = value;
                    }
                } else if (s.accept ("{")) {
                    int end = s.text.index_of_char ('}', s.pos);
                    if (end < 0) {
                        end = s.text.length;
                    }
                    d.accessible_description = s.text.substring (s.pos, end - s.pos).strip ();
                    s.pos = int.min (end + 1, s.text.length);
                }
            }

            void set_class (string id, string cls) {
                var v = d.vertices[id];
                if (v != null) {
                    v.classes.add (cls);
                }
                var sg = d.find_subgraph (id);
                if (sg != null) {
                    sg.classes.add (cls);
                }
                // Classes on not-yet-defined nodes still apply later.
                if (v == null && sg == null) {
                    d.add_vertex (id).classes.add (cls);
                }
            }

            void link_style () throws ParseError {
                s.skip_spaces ();
                string positions = read_word ();
                s.skip_spaces ();
                Curve? curve = null;
                if (s.at_word ("interpolate")) {
                    s.pos += 11;
                    s.skip_spaces ();
                    string name = read_word ();
                    curve = name == "linear" ? Curve.LINEAR
                        : (name.has_prefix ("step") ? Curve.STEP : Curve.BASIS);
                    s.skip_spaces ();
                }
                string css = s.rest_of_line ();
                foreach (unowned string p in positions.split (",")) {
                    if (p == "default") {
                        if (d.default_link_style == null) {
                            d.default_link_style = new CssStyle ();
                        }
                        d.default_link_style.apply (css);
                        if (curve != null) {
                            d.default_curve = curve;
                        }
                        continue;
                    }
                    int index;
                    if (!int.try_parse (p, out index) || index < 0) {
                        throw s.error ("“%s” isn't a link number".printf (p));
                    }
                    if (index >= d.edges.length) {
                        throw s.error ("There is no link number %d; links are numbered from 0 to %d"
                                       .printf (index, d.edges.length - 1));
                    }
                    d.edges[index].style.apply (css);
                    if (curve != null) {
                        d.edges[index].curve = curve;
                    }
                }
            }

            /* A run of non-space characters. */
            string read_word () {
                int start = s.pos;
                while (!s.eof && !s.peek ().isspace () && s.peek () != ';') {
                    s.pos++;
                }
                return s.text.substring (start, s.pos - start);
            }

            // Subgraphs.

            void subgraph_start () throws ParseError {
                var f = new Frame ();
                s.skip_spaces ();
                string header = s.rest_of_statement ().strip ();
                if (header == "") {
                    f.id = null;
                } else {
                    int bracket = header.index_of_char ('[');
                    if (bracket > 0 && header.has_suffix ("]")) {
                        f.id = header.substring (0, bracket).strip ();
                        string title = header.substring (bracket + 1, header.length - bracket - 2).strip ();
                        string? md = markdown_string (title);
                        if (md != null) {
                            f.title = md;
                            f.markdown = true;
                        } else {
                            f.title = unquote (title);
                        }
                    } else {
                        string? md = markdown_string (header);
                        string title = md ?? unquote (header);
                        f.title = title;
                        f.markdown = md != null;
                        // A title with spaces gets a generated id.
                        f.id = title.contains (" ") || title.contains ("\t") ? null : title;
                    }
                }
                frames.add (f);
            }

            static string? markdown_string (string s) {
                if (s.has_prefix ("\"`") && s.has_suffix ("`\"") && s.length >= 4) {
                    return s.substring (2, s.length - 4);
                }
                return null;
            }

            void subgraph_end () throws ParseError {
                var f = frame;
                frames.remove_index (frames.length - 1);

                string id = f.id ?? "subGraph%d".printf (sub_count);
                sub_count++;
                var sg = new FlowSubgraph ();
                sg.id = id;
                sg.title = f.title;
                sg.markdown = f.markdown;
                sg.dir = f.dir;

                // Members that already belong to another subgraph stay there.
                var seen = new HashTable<string, bool> (str_hash, str_equal);
                foreach (unowned string m in f.members) {
                    if (m == id || seen.contains (m)) {
                        continue;
                    }
                    seen.insert (m, true);
                    bool taken = false;
                    foreach (var other in d.subgraphs) {
                        for (int k = 0; k < other.nodes.length; k++) {
                            if (other.nodes[k] == m) {
                                taken = true;
                            }
                        }
                    }
                    if (!taken) {
                        sg.nodes.add (m);
                    }
                }

                var existing = d.find_subgraph (id);
                if (existing != null) {
                    foreach (unowned string m in sg.nodes) {
                        existing.nodes.add (m);
                    }
                } else {
                    d.subgraphs.add (sg);
                }
                frame.members.add (id);
                expect_end_of_statement ();
            }

            // Vertices and links.

            void vertex_statement () throws ParseError {
                var from = node_group ();
                while (true) {
                    int before = s.pos;
                    s.skip_spaces ();
                    var link = try_link ();
                    if (link == null) {
                        s.pos = before;
                        break;
                    }
                    s.skip_spaces ();
                    var to = node_group ();
                    for (int i = 0; i < from.length; i++) {
                        for (int j = 0; j < to.length; j++) {
                            bool keep_id = i == from.length - 1 && j == 0;
                            add_link (from[i], to[j], link, keep_id ? link.id : null);
                        }
                    }
                    from = to;
                }
                expect_end_of_statement ();
            }

            void add_link (string start, string end, Link link, string? id) {
                var e = new FlowEdge ();
                e.start = start;
                e.end = end;
                e.type = link.type;
                e.stroke = link.stroke;
                e.length = int.min (link.length, 10);
                if (link.text != null) {
                    string t = link.text.strip ();
                    if (t.length >= 2 && t.has_prefix ("\"") && t.has_suffix ("\"")) {
                        t = t.substring (1, t.length - 2);
                    }
                    e.text = t;
                    e.markdown = link.markdown;
                }
                e.id = id;
                d.edges.add (e);
            }

            /* "A & B & C". */
            GenericArray<string> node_group () throws ParseError {
                var ids = new GenericArray<string> ();
                ids.add (vertex ());
                while (true) {
                    int before = s.pos;
                    s.skip_spaces ();
                    if (s.peek () == '&') {
                        s.pos++;
                        s.skip_spaces ();
                        ids.add (vertex ());
                    } else {
                        s.pos = before;
                        break;
                    }
                }
                foreach (unowned string id in ids) {
                    frame.members.add (id);
                }
                return ids;
            }

            static bool is_id_char (char c) {
                return c.isalnum () || (uchar) c >= 0x80 || "_!#$%'*+.?\\/`:,".index_of_char (c) >= 0;
            }

            /* A node id, stopping before links, shapes and separators. */
            string read_id () {
                int start = s.pos;
                while (!s.eof) {
                    char c = s.peek ();
                    if (c == '-') {
                        char n = s.peek (1);
                        if (n == '-' || n == '>' || n == '.' || n == '\0') {
                            break;
                        }
                        s.pos++;
                        continue;
                    }
                    if (c == '=') {
                        if (s.peek (1) == '=') {
                            break;
                        }
                        s.pos++;
                        continue;
                    }
                    if (c == ':' && s.at (":::")) {
                        break;
                    }
                    if (c == ',' || c == ':') {
                        // Only inside an id, as in "a:b".
                        char n = s.peek (1);
                        if (s.pos == start || !is_id_char (n) || n == ',' || n == ':') {
                            break;
                        }
                        s.pos++;
                        continue;
                    }
                    if (c == '.') {
                        // "A.->B" starts a dotted link.
                        if (s.peek (1) == '-' && s.pos > start) {
                            break;
                        }
                    }
                    if (!is_id_char (c)) {
                        break;
                    }
                    s.pos++;
                }
                return s.text.substring (start, s.pos - start);
            }

            string vertex () throws ParseError {
                string id = read_id ();
                if (id == "") {
                    throw s.error ("Expected a node, found %s".printf (s.excerpt ()));
                }
                var v = d.add_vertex (id);
                if (try_shape (v)) {
                    v.has_shape = true;
                }
                if (s.accept (":::")) {
                    string cls = read_id ();
                    v.classes.add (cls);
                }
                if (s.at ("@{")) {
                    shape_data (v);
                }
                return id;
            }

            struct Delim {
                unowned string open;
                unowned string close;
                ShapeKind shape;
            }

            const Delim[] DELIMS = {
                { "(((", ")))", ShapeKind.DOUBLE_CIRCLE },
                { "((", "))", ShapeKind.CIRCLE },
                { "([", "])", ShapeKind.STADIUM },
                { "[[", "]]", ShapeKind.SUBROUTINE },
                { "[(", ")]", ShapeKind.CYLINDER },
                { "{{", "}}", ShapeKind.HEXAGON },
                { "(-", "-)", ShapeKind.ELLIPSE },
                { "(", ")", ShapeKind.ROUNDED },
                { "{", "}", ShapeKind.DIAMOND },
                { ">", "]", ShapeKind.ODD },
                { "[", "]", ShapeKind.RECT }
            };

            bool try_shape (FlowVertex v) throws ParseError {
                // Trapezoids and parallelograms: [/ /], [\ \], [/ \], [\ /].
                if (s.at ("[/") || s.at ("[\\")) {
                    bool slash = s.peek (1) == '/';
                    s.pos += 2;
                    bool md;
                    string text = read_text ({ "/]", "\\]" }, out md);
                    bool end_slash = s.peek () == '/';
                    s.pos += 2;
                    if (slash) {
                        v.shape = end_slash ? ShapeKind.LEAN_RIGHT : ShapeKind.TRAPEZOID;
                    } else {
                        v.shape = end_slash ? ShapeKind.INV_TRAPEZOID : ShapeKind.LEAN_LEFT;
                    }
                    set_text (v, text, md);
                    return true;
                }
                foreach (var delim in DELIMS) {
                    if (s.at (delim.open)) {
                        s.pos += delim.open.length;
                        bool md;
                        string text = read_text ({ delim.close }, out md);
                        s.pos += delim.close.length;
                        v.shape = delim.shape;
                        set_text (v, text, md);
                        return true;
                    }
                }
                return false;
            }

            static void set_text (FlowVertex v, string text, bool md) {
                v.text = text;
                v.markdown = md;
            }

            /*
             * Text up to one of the closing delimiters: a "string", a
             * "`markdown string`" or plain text without brackets.
             */
            string read_text (string[] closers, out bool markdown) throws ParseError {
                markdown = false;
                s.skip_spaces ();
                string text;
                if (s.at ("\"`")) {
                    int end = s.text.index_of ("`\"", s.pos + 2);
                    if (end < 0) {
                        throw s.error ("A Markdown string has no closing “`\"”");
                    }
                    text = s.text.substring (s.pos + 2, end - s.pos - 2);
                    s.pos = end + 2;
                    markdown = true;
                } else if (s.peek () == '"') {
                    int end = s.text.index_of_char ('"', s.pos + 1);
                    if (end < 0) {
                        throw s.error ("A string has no closing quote");
                    }
                    text = s.text.substring (s.pos + 1, end - s.pos - 1);
                    s.pos = end + 1;
                } else {
                    int start = s.pos;
                    while (!s.eof) {
                        bool closing = false;
                        foreach (unowned string c in closers) {
                            if (s.at (c)) {
                                closing = true;
                            }
                        }
                        if (closing) {
                            break;
                        }
                        char c = s.peek ();
                        if ("[](){}\"".index_of_char (c) >= 0 || c == '\n') {
                            break;
                        }
                        s.pos++;
                    }
                    text = s.text.substring (start, s.pos - start).strip ();
                }
                s.skip_spaces ();
                foreach (unowned string c in closers) {
                    if (s.at (c)) {
                        return text;
                    }
                }
                throw s.error ("Expected “%s”, found %s".printf (closers[0], s.excerpt ()));
            }

            /* "@{ shape: rect, label: "Text" }". */
            void shape_data (FlowVertex v) throws ParseError {
                s.pos += 2;
                int end = s.text.index_of_char ('}', s.pos);
                // Skip over quoted values that contain "}".
                int p = s.pos;
                bool quoted = false;
                for (; p < s.text.length; p++) {
                    if (s.text[p] == '"') {
                        quoted = !quoted;
                    } else if (s.text[p] == '}' && !quoted) {
                        break;
                    }
                }
                end = p;
                if (end >= s.text.length) {
                    throw s.error ("Shape data has no closing “}”");
                }
                string body = s.text.substring (s.pos, end - s.pos);
                s.pos = end + 1;

                // An edge id: edge metadata (animation) isn't supported.
                foreach (var e in d.edges) {
                    if (e.id == v.id) {
                        d.vertices.remove (v.id);
                        return;
                    }
                }

                var pairs = split_pairs (body);
                for (int k = 0; k + 1 < pairs.length; k += 2) {
                    string key = pairs[k], value = pairs[k + 1];
                    switch (key) {
                    case "shape":
                        ShapeKind kind;
                        if (!Shapes.from_name (value, out kind)) {
                            // Shapes we can't draw yet fall back to a rectangle.
                            kind = ShapeKind.RECT;
                        }
                        v.shape = kind;
                        v.has_shape = true;
                        break;
                    case "label":
                        string? md = markdown_string ("\"" + value + "\"");
                        v.text = md ?? value;
                        v.markdown = md != null;
                        break;
                    }
                }
            }

            /* Keys and values, alternating. */
            static GenericArray<string> split_pairs (string body) {
                var result = new GenericArray<string> ();
                var sb = new StringBuilder ();
                bool quoted = false;
                string[] parts = {};
                for (int i = 0; i < body.length; i++) {
                    char c = body[i];
                    if (c == '"') {
                        quoted = !quoted;
                        sb.append_c (c);
                    } else if ((c == ',' || c == '\n') && !quoted) {
                        parts += sb.str;
                        sb.truncate ();
                    } else {
                        sb.append_c (c);
                    }
                }
                parts += sb.str;
                foreach (unowned string part in parts) {
                    int colon = part.index_of_char (':');
                    if (colon < 0) {
                        continue;
                    }
                    string key = part.substring (0, colon).strip ();
                    string value = unquote (part.substring (colon + 1).strip ());
                    result.add (key);
                    result.add (value);
                }
                return result;
            }

            /*
             * A link here: "-->", "---", "-.->", "==>", "~~~", with text as
             * "-- text -->" or "-->|text|", and an optional "id@" before it.
             */
            Link? try_link () throws ParseError {
                int start = s.pos;
                string? id = null;
                // "e1@-->".
                int at = start;
                while (at < s.text.length && is_id_char (s.text[at]) && s.text[at] != ':') {
                    at++;
                }
                if (at > start && at < s.text.length && s.text[at] == '@' && at + 1 < s.text.length
                    && s.text[at + 1] != '{') {
                    id = s.text.substring (start, at - start);
                    s.pos = at + 1;
                }

                var link = scan_link_token (false);
                if (link == null) {
                    s.pos = start;
                    return null;
                }
                link.id = id;

                if (link.text == null) {
                    // "-->|text|".
                    int before = s.pos;
                    s.skip_spaces ();
                    if (s.peek () == '|') {
                        s.pos++;
                        bool md;
                        link.text = read_text ({ "|" }, out md);
                        link.markdown = md;
                        s.pos++;
                    } else {
                        s.pos = before;
                    }
                }
                return link;
            }

            /*
             * A complete link token, or the start of one with text
             * ("-- text -->"), in which case the text and the end are read too.
             */
            Link? scan_link_token (bool only_end) throws ParseError {
                int start = s.pos;
                char head = s.peek ();
                int p = start;
                if (head == 'x' || head == 'o' || head == '<') {
                    p++;
                }
                char c = p < s.text.length ? s.text[p] : '\0';

                if (c == '~') {
                    int q = p;
                    while (q < s.text.length && s.text[q] == '~') {
                        q++;
                    }
                    if (q - p >= 3) {
                        s.pos = q;
                        var l = new Link ();
                        l.stroke = "invisible";
                        l.length = q - p - 2;
                        return l;
                    }
                    return null;
                }

                if (c == '-' || c == '=') {
                    int q = p;
                    while (q < s.text.length && s.text[q] == c) {
                        q++;
                    }
                    int count = q - p;
                    char after = q < s.text.length ? s.text[q] : '\0';
                    // Dotted: "-.->", "-..-".
                    if (c == '-' && count == 1 && after == '.') {
                        return dotted (start, p, only_end);
                    }
                    if (count >= 2) {
                        if (after == 'x' || after == 'o' || after == '>') {
                            s.pos = q + 1;
                            return destruct (s.text.substring (start, s.pos - start), null);
                        }
                        if (count >= 3) {
                            s.pos = q;
                            return destruct (s.text.substring (start, s.pos - start), null);
                        }
                        if (!only_end) {
                            // "-- text -->".
                            s.pos = q;
                            string open = s.text.substring (start, q - start);
                            return text_link (open, c);
                        }
                    }
                    return null;
                }
                if (c == '.') {
                    return dotted (start, p, only_end);
                }
                return null;
            }

            Link? dotted (int start, int p, bool only_end) throws ParseError {
                int q = p;
                if (q < s.text.length && s.text[q] == '-') {
                    q++;
                }
                int dots_start = q;
                while (q < s.text.length && s.text[q] == '.') {
                    q++;
                }
                if (q == dots_start) {
                    return null;
                }
                if (q < s.text.length && s.text[q] == '-') {
                    q++;
                    if (q < s.text.length && (s.text[q] == 'x' || s.text[q] == 'o' || s.text[q] == '>')) {
                        q++;
                    }
                    s.pos = q;
                    return destruct (s.text.substring (start, q - start), null);
                }
                if (!only_end && q - dots_start == 1 && dots_start > p) {
                    // "-. text .->".
                    s.pos = q;
                    return text_link (s.text.substring (start, q - start), '.');
                }
                return null;
            }

            Link text_link (string open, char kind) throws ParseError {
                int text_start = s.pos;
                while (!s.eof && s.peek () != '\n') {
                    int here = s.pos;
                    // The closing link may have spaces before it.
                    int q = here;
                    while (q < s.text.length && (s.text[q] == ' ' || s.text[q] == '\t')) {
                        q++;
                    }
                    s.pos = q;
                    bool candidate = kind == '.' ? (s.peek () == '.' || (s.peek () == '-' && s.peek (1) == '.'))
                        : (s.peek () == kind || ((s.peek () == 'x' || s.peek () == 'o' || s.peek () == '<')
                                                 && s.peek (1) == kind));
                    if (candidate && q > text_start) {
                        var end = scan_link_token (true);
                        if (end != null) {
                            string close = s.text.substring (q, s.pos - q);
                            string text = s.text.substring (text_start, here - text_start);
                            var l = destruct (close, open);
                            string t = text.strip ();
                            if (t.has_prefix ("\"`") && t.has_suffix ("`\"") && t.length >= 4) {
                                l.text = t.substring (2, t.length - 4);
                                l.markdown = true;
                            } else {
                                l.text = t;
                            }
                            return l;
                        }
                    }
                    s.pos = here + 1;
                }
                throw s.error ("The link text has no closing link, as in “-- text -->”");
            }

            /* destructLink from flowDb.ts. */
            Link destruct (string end_str, string? start_str) throws ParseError {
                var info = destruct_end (end_str.strip ());
                if (start_str == null) {
                    return info;
                }
                string str = start_str.strip ();
                string type = "arrow_open";
                switch (str[0]) {
                case '<':
                    type = "arrow_point";
                    str = str.substring (1);
                    break;
                case 'x':
                    type = "arrow_cross";
                    str = str.substring (1);
                    break;
                case 'o':
                    type = "arrow_circle";
                    str = str.substring (1);
                    break;
                }
                string stroke = "normal";
                if (str.contains ("=")) {
                    stroke = "thick";
                }
                if (str.contains (".")) {
                    stroke = "dotted";
                }
                if (stroke != info.stroke) {
                    throw s.error ("The start and end of a link don't match");
                }
                if (type == "arrow_open") {
                    type = info.type;
                } else {
                    if (type != info.type) {
                        throw s.error ("The start and end of a link don't match");
                    }
                    type = "double_" + type;
                }
                info.type = type;
                return info;
            }

            static Link destruct_end (string str) {
                var l = new Link ();
                string line = str.substring (0, str.length - 1);
                char last = str[str.length - 1];
                switch (last) {
                case 'x':
                    l.type = "arrow_cross";
                    if (str.has_prefix ("x")) {
                        l.type = "double_" + l.type;
                        line = line.substring (1);
                    }
                    break;
                case '>':
                    l.type = "arrow_point";
                    if (str.has_prefix ("<")) {
                        l.type = "double_" + l.type;
                        line = line.substring (1);
                    }
                    break;
                case 'o':
                    l.type = "arrow_circle";
                    if (str.has_prefix ("o")) {
                        l.type = "double_" + l.type;
                        line = line.substring (1);
                    }
                    break;
                }
                l.length = line.length - 1;
                if (line.has_prefix ("=")) {
                    l.stroke = "thick";
                }
                if (line.has_prefix ("~")) {
                    l.stroke = "invisible";
                }
                int dots = 0;
                foreach (char c in line.to_utf8 ()) {
                    if (c == '.') {
                        dots++;
                    }
                }
                if (dots > 0) {
                    l.stroke = "dotted";
                    l.length = dots;
                }
                if (l.length < 1) {
                    l.length = 1;
                }
                return l;
            }
        }

        internal FlowchartDiagram parse (Source src, int first) throws ParseError {
            string head = src.lines[first].strip ();
            int i = 0;
            while (i < head.length && !head[i].isspace () && head[i] != ';') {
                i++;
            }
            string rest = head.substring (i).strip ();
            string direction = "TB";
            if (rest != "" && rest[0] != ';') {
                int j = 0;
                while (j < rest.length && !rest[j].isspace () && rest[j] != ';') {
                    j++;
                }
                string dir = rest.substring (0, j);
                switch (dir) {
                case "TB":
                case "TD":
                case "v":
                    direction = "TB";
                    break;
                case "BT":
                case "^":
                    direction = "BT";
                    break;
                case "LR":
                case ">":
                    direction = "LR";
                    break;
                case "RL":
                case "<":
                    direction = "RL";
                    break;
                default:
                    throw syntax_error (first, "Unknown direction “%s”; use TB, TD, BT, LR or RL".printf (dir));
                }
                rest = rest.substring (j);
            }

            // Statements can follow the header on the same line, after a ";".
            string body = rest + "\n" + src.joined (first + 1);
            var parser = new Parser (new Scanner (body, first));
            parser.d.direction = direction;
            parser.run ();
            return parser.d;
        }
    }
}
