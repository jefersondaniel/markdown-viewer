/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Entity relationship diagrams. The syntax follows Mermaid 12.2.0's
 * src/diagrams/er/parser/erDiagram.jison and erDb.ts, and the drawing its
 * rendering-elements/shapes/erBox.ts.
 * Copyright (c) 2014-2022 Knut Sveidqvist and Mermaid contributors. MIT License.
 */

namespace Mermaid {

    internal class ErAttribute {
        public string type;
        public string name;
        public string keys = "";
        public string comment = "";
    }

    internal class ErEntity {
        public string id;
        public string label;
        public GenericArray<ErAttribute> attributes = new GenericArray<ErAttribute> ();
        public GenericArray<string> classes = new GenericArray<string> ();
        public CssStyle style = new CssStyle ();
    }

    internal class ErRelation {
        public string from;
        public string to;
        public Marker from_card;
        public Marker to_card;
        public bool identifying = true;
        public string label = "";
    }

    /* An entity: its name above a table of attributes. */
    internal class ErBox : GNode {
        public GenericArray<ErAttribute> attributes = new GenericArray<ErAttribute> ();
        Size head;
        double[] col_width = new double[4];
        double row_height;
        const double PAD = 8;
        const double MIN_WIDTH = 100;
        const double MIN_HEIGHT = 75;

        public ErBox (string id) {
            base (id);
        }

        string cell (ErAttribute a, int col) {
            switch (col) {
            case 0:
                return Label.escape (ClassDiagram.generics (a.type));
            case 1:
                return Label.escape (a.name);
            case 2:
                return Label.escape (a.keys);
            default:
                return Label.escape (a.comment);
            }
        }

        public override void measure (TextMeasurer m) {
            head = Mermaid.measure (m, "<b>" + label + "</b>", text_style);
            row_height = text_style.size * 1.25 + PAD;
            for (int c = 0; c < 4; c++) {
                col_width[c] = 0;
            }
            foreach (var a in attributes) {
                for (int c = 0; c < 4; c++) {
                    string t = cell (a, c);
                    if (t != "") {
                        var s = Mermaid.measure (m, t, text_style);
                        col_width[c] = double.max (col_width[c], s.width + 2 * PAD);
                        row_height = double.max (row_height, s.height + PAD);
                    }
                }
            }
            double table = col_width[0] + col_width[1] + col_width[2] + col_width[3];
            width = double.max (double.max (head.width + 2 * padding, table), MIN_WIDTH);
            if (attributes.length == 0) {
                height = double.max (head.height + 2 * padding, MIN_HEIGHT);
            } else {
                height = head.height + 2 * PAD + attributes.length * row_height;
            }
            // Spread spare width over the columns.
            if (table > 0 && table < width) {
                double extra = (width - table) / 4;
                for (int c = 0; c < 4; c++) {
                    if (col_width[c] > 0) {
                        col_width[c] += extra;
                    }
                }
            }
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
            if (attributes.length == 0) {
                var t = scene.add_text ("<b>" + label + "</b>", x, y, text_style);
                t.color = color;
                return;
            }
            double header = head.height + 2 * PAD;
            var t = scene.add_text ("<b>" + label + "</b>", x, top + header / 2, text_style);
            t.color = color;
            double ry = top + header;
            for (int i = 0; i < attributes.length; i++) {
                var row = new Path ();
                row.rect (left, ry, width, row_height);
                scene.add_shape (row, i % 2 == 0 ? Paint (Ink.BACKGROUND) : Paint (Ink.GROUP_FILL), stroke, stroke_width * 0.5);
                double cx = left;
                for (int c = 0; c < 4; c++) {
                    if (col_width[c] <= 0) {
                        continue;
                    }
                    string text = cell (attributes[i], c);
                    if (text != "") {
                        var ct = scene.add_text (text, cx + PAD, ry + row_height / 2, text_style, Align.START);
                        ct.color = color;
                    }
                    cx += col_width[c];
                }
                ry += row_height;
            }
        }
    }

    public class ErDiagram : Diagram {
        public override string kind {
            get { return "er"; }
        }

        internal string direction = "TB";
        internal Dagre.Dict<ErEntity> entities = new Dagre.Dict<ErEntity> ();
        internal GenericArray<ErRelation> relations = new GenericArray<ErRelation> ();
        internal HashTable<string, CssStyle> classes = new HashTable<string, CssStyle> (str_hash, str_equal);

        internal ErEntity entity (string id) {
            var e = entities[id];
            if (e == null) {
                e = new ErEntity ();
                e.id = id;
                e.label = id;
                entities[id] = e;
            }
            return e;
        }

        internal override Scene build (TextMeasurer m) {
            var r = new GraphRender ();
            r.rankdir = direction;
            r.nodesep = 140;
            r.ranksep = 80;
            foreach (var en in entities.values ()) {
                var box = new ErBox (en.id);
                box.label = Label.escape (en.label);
                box.attributes = en.attributes;
                var style = new CssStyle ();
                if (classes["default"] != null) {
                    style.merge (classes["default"]);
                }
                foreach (unowned string c in en.classes) {
                    if (classes[c] != null) {
                        style.merge (classes[c]);
                    }
                }
                style.merge (en.style);
                if (style.fill != null) {
                    box.fill = style.fill;
                }
                if (style.stroke != null) {
                    box.stroke = style.stroke;
                }
                var text = style.text_color ();
                if (text != null) {
                    box.color = text;
                }
                if (style.stroke_width >= 0) {
                    box.stroke_width = style.stroke_width;
                }
                r.add_node (box);
            }
            foreach (var rel in relations) {
                var e = new GEdge (rel.from, rel.to);
                e.start_marker = rel.from_card;
                e.end_marker = rel.to_card;
                e.line_style = rel.identifying ? LineStyle.SOLID : LineStyle.DASHED;
                e.thickness = 1;
                e.label = Label.from_text (rel.label);
                r.add_edge (e);
            }
            return r.render (m);
        }
    }

    namespace ErParser {

        bool cardinality (string token, out Marker marker) {
            switch (token) {
            case "|o":
            case "o|":
                marker = Marker.ER_ZERO_OR_ONE;
                return true;
            case "||":
                marker = Marker.ER_ONLY_ONE;
                return true;
            case "}o":
            case "o{":
                marker = Marker.ER_ZERO_OR_MORE;
                return true;
            case "}|":
            case "|{":
                marker = Marker.ER_ONE_OR_MORE;
                return true;
            }
            marker = Marker.NONE;
            return false;
        }

        /* "NAME", "\"Any name\"" or "NAME[\"Label\"]", with an optional ":::class". */
        ErEntity entity_ref (ErDiagram d, string text) {
            string t = text.strip ();
            string? css = null;
            int sep = t.index_of (":::");
            if (sep >= 0) {
                css = t.substring (sep + 3).strip ();
                t = t.substring (0, sep).strip ();
            }
            string? label = null;
            int bracket = t.index_of_char ('[');
            if (bracket > 0 && t.has_suffix ("]")) {
                label = unquote (t.substring (bracket + 1, t.length - bracket - 2).strip ());
                t = t.substring (0, bracket).strip ();
            }
            var e = d.entity (unquote (t));
            if (label != null) {
                e.label = label;
            }
            if (css != null) {
                e.classes.add (css);
            }
            return e;
        }

        internal ErDiagram parse (Source src, int first) throws ParseError {
            var d = new ErDiagram ();
            Regex relation;
            try {
                relation = new Regex ("""^("[^"]+"|[^\s|}o{]+(?:\[[^\]]*\])?(?::::\w+)?)\s*(\|o|\|\||\}o|\}\|)(--|\.\.|\.-|-\.)(o\||\|\||o\{|\|\{)\s*("[^"]+"|\S+?)\s*(?::\s*(.*))?$""");
            } catch (RegexError e) {
                error ("%s", e.message);
            }
            for (int i = first + 1; i < src.lines.length; i++) {
                string l = src.lines[i].strip ();
                if (l == "" || common_statement (src, ref i, d)) {
                    continue;
                }
                if (l.has_prefix ("direction ")) {
                    string dir = l.substring (10).strip ();
                    if (dir == "TD") {
                        dir = "TB";
                    }
                    if (!(dir in new string[] { "TB", "BT", "LR", "RL" })) {
                        throw syntax_error (i, "Unknown direction “%s”".printf (dir));
                    }
                    d.direction = dir;
                    continue;
                }
                if (l.has_prefix ("classDef ")) {
                    string rest = l.substring (9).strip ();
                    int sp = rest.index_of_char (' ');
                    if (sp < 0) {
                        throw syntax_error (i, "Expected styles after the class name");
                    }
                    foreach (unowned string name in rest.substring (0, sp).split (",")) {
                        var cls = d.classes[name];
                        if (cls == null) {
                            cls = new CssStyle ();
                            d.classes[name] = cls;
                        }
                        cls.apply (rest.substring (sp + 1));
                    }
                    continue;
                }
                if (l.has_prefix ("class ")) {
                    string rest = l.substring (6).strip ();
                    int sp = rest.last_index_of_char (' ');
                    if (sp < 0) {
                        throw syntax_error (i, "Expected “class ENTITIES CLASS”");
                    }
                    foreach (unowned string id in rest.substring (0, sp).split (",")) {
                        d.entity (id.strip ()).classes.add (rest.substring (sp + 1).strip ());
                    }
                    continue;
                }
                if (l.has_prefix ("style ")) {
                    string rest = l.substring (6).strip ();
                    int sp = rest.index_of_char (' ');
                    if (sp < 0) {
                        throw syntax_error (i, "Expected styles after the entity");
                    }
                    foreach (unowned string id in rest.substring (0, sp).split (",")) {
                        d.entity (id.strip ()).style.apply (rest.substring (sp + 1));
                    }
                    continue;
                }

                MatchInfo mi;
                if (relation.match (l, 0, out mi)) {
                    var rel = new ErRelation ();
                    rel.from = entity_ref (d, mi.fetch (1)).id;
                    Marker from_card, to_card;
                    cardinality (mi.fetch (2), out from_card);
                    cardinality (mi.fetch (4), out to_card);
                    rel.from_card = from_card;
                    rel.to_card = to_card;
                    rel.identifying = mi.fetch (3) == "--";
                    rel.to = entity_ref (d, mi.fetch (5)).id;
                    string? label = mi.fetch (6);
                    rel.label = label != null ? unquote (label.strip ()) : "";
                    d.relations.add (rel);
                    continue;
                }

                // An entity, with its attributes in braces.
                if (l.has_suffix ("{")) {
                    var en = entity_ref (d, l.substring (0, l.length - 1));
                    bool closed = false;
                    while (i + 1 < src.lines.length) {
                        i++;
                        string a = src.lines[i].strip ();
                        if (a == "}") {
                            closed = true;
                            break;
                        }
                        if (a == "") {
                            continue;
                        }
                        en.attributes.add (attribute (i, a));
                    }
                    if (!closed) {
                        throw syntax_error (i, "The entity “%s” is missing its “}”".printf (en.id));
                    }
                    continue;
                }
                if (!l.contains (" ") || (l.has_prefix ("\"") && l.has_suffix ("\""))
                    || (l.index_of_char ('[') > 0 && l.has_suffix ("]"))) {
                    entity_ref (d, l);
                    continue;
                }
                throw syntax_error (i, "Unexpected “%s”".printf (l));
            }
            return d;
        }

        /* "type name PK, FK \"comment\"". */
        ErAttribute attribute (int i, string line) throws ParseError {
            var a = new ErAttribute ();
            string rest = line;
            int quote = rest.index_of_char ('"');
            if (quote >= 0) {
                int end = rest.last_index_of_char ('"');
                if (end > quote) {
                    a.comment = rest.substring (quote + 1, end - quote - 1);
                }
                rest = rest.substring (0, quote).strip ();
            }
            string[] words = {};
            foreach (unowned string w in rest.replace (",", " ").split (" ")) {
                if (w != "") {
                    words += w;
                }
            }
            if (words.length < 2) {
                throw syntax_error (i, "An attribute needs a type and a name, like “string name”");
            }
            a.type = words[0];
            a.name = words[1];
            string[] keys = {};
            for (int k = 2; k < words.length; k++) {
                if (words[k] == "PK" || words[k] == "FK" || words[k] == "UK") {
                    keys += words[k];
                } else {
                    throw syntax_error (i, "“%s” isn't a key; use PK, FK or UK".printf (words[k]));
                }
            }
            a.keys = string.joinv (", ", keys);
            return a;
        }
    }
}
