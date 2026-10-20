/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Lays out and draws node-and-edge diagrams (flowcharts, state and class
 * diagrams) with dagre. Follows Mermaid 12.2.0's
 * src/rendering-util/layout-algorithms/dagre/index.js and mermaid-graphlib.js
 * for clusters, and rendering-elements/edges.js and markers.js for edges.
 * Copyright (c) 2014-2022 Knut Sveidqvist and Mermaid contributors. MIT License.
 * The basis curve follows d3-shape's curveBasis.
 * Copyright 2010-2022 Mike Bostock. ISC License.
 */

namespace Mermaid {

    public enum Marker {
        NONE,
        /* A filled arrowhead. */
        ARROW,
        CIRCLE,
        CROSS,
        /* Class diagrams: inheritance (hollow triangle). */
        EXTENSION,
        /* Class diagrams: a filled diamond. */
        COMPOSITION,
        /* Class diagrams: a hollow diamond. */
        AGGREGATION,
        /* Class diagrams: an open arrowhead. */
        DEPENDENCY,
        /* Class diagrams: a hollow circle on a short stem. */
        LOLLIPOP,
        /* Entity relationship cardinalities, in crow's foot notation. */
        ER_ONLY_ONE,
        ER_ZERO_OR_ONE,
        ER_ONE_OR_MORE,
        ER_ZERO_OR_MORE
    }

    public enum GroupStyle {
        /* A flowchart subgraph: a box with the title inside its top. */
        BOX,
        /* A composite state: a title band above a lighter body. */
        STATE,
        /* A region of a composite state: a dashed box without a title. */
        DIVIDER
    }

    public enum Curve {
        BASIS,
        LINEAR,
        STEP
    }

    /* A node of a graph diagram. Subclasses can draw it differently. */
    internal class GNode {
        public string id;
        public string? parent;
        public bool is_group;
        public string label = "";
        public ShapeKind shape = ShapeKind.RECT;
        public Paint fill = Paint (Ink.NODE_FILL);
        public Paint stroke = Paint (Ink.NODE_STROKE);
        public Paint color = Paint (Ink.TEXT);
        public double stroke_width = 1;
        public LineStyle line_style = LineStyle.SOLID;
        public TextStyle text_style = TextStyle (FONT_SIZE);
        public double padding = 15;
        /* Wrapping width for the label, or 0. */
        public double wrap_width;

        /* Set by measure (), or fixed beforehand. */
        public double width;
        public double height;
        /* The center, after layout. */
        public double x;
        public double y;

        // Groups.
        public GroupStyle group_style = GroupStyle.BOX;
        public string? dir;
        public Size title_size;
        /* Laid out on its own because no edge crosses its border. */
        public bool extracted;
        public GraphLevel? level;

        public GNode (string id) {
            this.id = id;
        }

        public virtual void measure (TextMeasurer m) {
            var size = Mermaid.measure (m, label, text_style, wrap_width);
            var s = Shapes.size_for (shape, size, padding);
            width = s.width;
            height = s.height;
        }

        /* Where edges point to; the center unless part of the node is an annex. */
        public virtual double anchor_x () {
            return x;
        }

        /* The outline, for where edges end. */
        public virtual Path outline () {
            return Shapes.geometry (shape, x, y, width, height).outline;
        }

        public virtual void draw (Scene scene) {
            var g = Shapes.geometry (shape, x, y, width, height);
            if (g.solid) {
                scene.add_shape (g.outline, Paint (Ink.SOLID), Paint (Ink.NONE));
            } else {
                var s = scene.add_shape (g.outline, g.stroked ? fill : Paint (Ink.NONE),
                                         g.stroked ? stroke : Paint (Ink.NONE), stroke_width);
                s.line_style = line_style;
            }
            if (g.decoration != null) {
                var d = scene.add_shape (g.decoration, Paint (Ink.NONE),
                                         g.solid ? Paint (Ink.SOLID) : stroke, stroke_width);
                if (shape == ShapeKind.FRAMED_CIRCLE) {
                    d.fill = Paint (Ink.SOLID);
                }
            }
            if (label != "") {
                double ly = y + g.label_dy;
                if (Shapes.label_outside (shape)) {
                    ly = y + height / 2 + 4 + text_height (scene);
                }
                var t = scene.add_text (label, x, ly, text_style);
                t.color = color;
                t.wrap_width = wrap_width;
            }
        }

        double text_height (Scene scene) {
            return text_style.size * 0.7;
        }
    }

    internal class GEdge {
        public string start;
        public string end;
        public string label = "";
        public Marker start_marker = Marker.NONE;
        public Marker end_marker = Marker.ARROW;
        public LineStyle line_style = LineStyle.SOLID;
        public double thickness = 1.5;
        public bool invisible;
        public Paint stroke = Paint (Ink.LINE);
        public Paint label_color = Paint (Ink.TEXT);
        public int minlen = 1;
        public Curve curve = Curve.BASIS;
        public TextStyle text_style = TextStyle (FONT_SIZE);
        /* Class diagram cardinalities, near the ends. */
        public string? start_label;
        public string? end_label;

        // Results.
        public Geometry.Pt[] points;
        public double label_x;
        public double label_y;
        public bool has_label_position;
        public Size label_size;
        public string? from_cluster;
        public string? to_cluster;

        public GEdge (string start, string end) {
            this.start = start;
            this.end = end;
        }
    }

    /* One dagre layout: the top level or an extracted cluster. */
    internal class GraphLevel {
        public string rankdir;
        public GenericArray<GNode> nodes = new GenericArray<GNode> ();
        public GenericArray<GEdge> edges = new GenericArray<GEdge> ();
        public double width;
        public double height;
        /* Where this level's (0, 0) is in the scene. */
        public double origin_x;
        public double origin_y;
    }

    internal class GraphRender {
        public string rankdir = "TB";
        public double nodesep = 50;
        public double ranksep = 50;
        public GenericArray<GNode> nodes = new GenericArray<GNode> ();
        public GenericArray<GEdge> edges = new GenericArray<GEdge> ();

        HashTable<string, GNode> by_id = new HashTable<string, GNode> (str_hash, str_equal);
        HashTable<string, GenericArray<GNode>> children = new HashTable<string, GenericArray<GNode>> (str_hash, str_equal);

        /* Space between a cluster's border and its content. */
        const double CLUSTER_PADDING = 8;

        public GNode add_node (GNode node) {
            nodes.add (node);
            by_id[node.id] = node;
            return node;
        }

        public GNode? node (string id) {
            return by_id[id];
        }

        public GEdge add_edge (GEdge edge) {
            edges.add (edge);
            return edge;
        }

        public Scene render (TextMeasurer m) {
            foreach (var n in nodes) {
                if (n.parent != null && by_id[n.parent] == null) {
                    n.parent = null;
                }
                string key = n.parent ?? "";
                if (children[key] == null) {
                    children[key] = new GenericArray<GNode> ();
                }
                children[key].add (n);
            }
            // A group without members is drawn as a plain node.
            foreach (var n in nodes) {
                if (n.is_group && children[n.id] == null) {
                    n.is_group = false;
                }
            }
            foreach (var n in nodes) {
                if (n.is_group) {
                    n.title_size = Mermaid.measure (m, n.label, n.text_style);
                } else if (n.width == 0 && n.height == 0) {
                    n.measure (m);
                }
            }
            foreach (var e in edges) {
                e.label_size = Mermaid.measure (m, e.label, e.text_style);
            }

            mark_extracted_clusters ();
            redirect_cluster_edges ();

            var root = new GraphLevel ();
            root.rankdir = rankdir;
            layout_level (root, null, m, ranksep);

            var scene = new Scene ();
            scene.width = root.width;
            scene.height = root.height;
            draw_level (scene, root, m);
            return scene;
        }

        bool is_descendant (string id, string ancestor) {
            var n = by_id[id];
            while (n != null && n.parent != null) {
                if (n.parent == ancestor) {
                    return true;
                }
                n = by_id[n.parent];
            }
            return false;
        }

        /* Clusters that no edge crosses are laid out on their own. */
        void mark_extracted_clusters () {
            foreach (var n in nodes) {
                if (!n.is_group) {
                    continue;
                }
                bool external = false;
                foreach (var e in edges) {
                    bool d1 = is_descendant (e.start, n.id);
                    bool d2 = is_descendant (e.end, n.id);
                    if (d1 != d2) {
                        external = true;
                        break;
                    }
                }
                n.extracted = !external;
            }
        }

        /* A leaf inside the cluster, to stand in for it as an edge's end. */
        string? anchor_for (string cluster) {
            var kids = children[cluster];
            if (kids == null) {
                return null;
            }
            foreach (var k in kids) {
                if (!k.is_group) {
                    return k.id;
                }
            }
            foreach (var k in kids) {
                if (!k.extracted) {
                    string? a = anchor_for (k.id);
                    if (a != null) {
                        return a;
                    }
                } else {
                    return k.id;
                }
            }
            return null;
        }

        /*
         * Edges to a cluster that is part of the surrounding layout go to a
         * node inside it and are cut at the cluster's border.
         */
        void redirect_cluster_edges () {
            foreach (var e in edges) {
                var s = by_id[e.start];
                if (s != null && s.is_group && !s.extracted) {
                    string? a = anchor_for (s.id);
                    if (a != null) {
                        e.from_cluster = s.id;
                        e.start = a;
                    }
                }
                var t = by_id[e.end];
                if (t != null && t.is_group && !t.extracted) {
                    string? a = anchor_for (t.id);
                    if (a != null) {
                        e.to_cluster = t.id;
                        e.end = a;
                    }
                }
            }
        }

        /* The level whose layout a node belongs to: its nearest extracted ancestor. */
        string? level_of (string id) {
            var n = by_id[id];
            while (n != null && n.parent != null) {
                var p = by_id[n.parent];
                if (p.extracted) {
                    return p.id;
                }
                n = p;
            }
            return null;
        }

        void collect (string? group, GraphLevel level) {
            var kids = children[group ?? ""];
            if (kids == null) {
                return;
            }
            foreach (var k in kids) {
                level.nodes.add (k);
                if (k.is_group && !k.extracted) {
                    collect (k.id, level);
                }
            }
        }

        void layout_level (GraphLevel level, string? group, TextMeasurer m, double rank_sep) {
            collect (group, level);

            // Extracted clusters inside this level are laid out first; they
            // become fixed-size nodes here.
            foreach (var n in level.nodes) {
                if (n.is_group && n.extracted) {
                    var inner = new GraphLevel ();
                    if (n.dir != null) {
                        inner.rankdir = n.dir;
                    } else {
                        inner.rankdir = level.rankdir == "TB" ? "LR" : "TB";
                    }
                    layout_level (inner, n.id, m, rank_sep + 25);
                    n.level = inner;
                    n.width = double.max (inner.width, n.title_size.width + 2 * CLUSTER_PADDING);
                    n.height = inner.height + title_band (n);
                }
            }

            foreach (var e in edges) {
                if (level_of (e.start) == group && level_of (e.end) == group
                    && by_id[e.start] != null && by_id[e.end] != null
                    && in_level (e.start, level) && in_level (e.end, level)) {
                    level.edges.add (e);
                }
            }

            var g = new Dagre.Graph (true, true, true);
            g.label.rankdir = level.rankdir;
            g.label.nodesep = nodesep;
            g.label.ranksep = rank_sep;
            g.label.marginx = 8;
            g.label.marginy = 8;
            foreach (var n in level.nodes) {
                var label = new Dagre.NodeLabel ();
                if (!(n.is_group && !n.extracted)) {
                    label.width = n.width;
                    label.height = n.height;
                } else {
                    label.title_height = title_band (n);
                }
                g.set_node (n.id, label);
            }
            foreach (var n in level.nodes) {
                if (n.parent != null && n.parent != group) {
                    g.set_parent (n.id, n.parent);
                }
            }
            for (int i = 0; i < level.edges.length; i++) {
                var e = level.edges[i];
                var label = new Dagre.EdgeLabel ();
                label.minlen = e.minlen;
                label.width = e.label_size.width;
                label.height = e.label_size.height;
                label.labelpos = "c";
                g.set_edge (e.start, e.end, label, "e%d".printf (i));
            }

            Dagre.layout (g);

            level.width = g.label.width;
            level.height = g.label.height;
            foreach (var n in level.nodes) {
                var l = g.node (n.id);
                n.x = l.x;
                n.y = l.y;
                if (n.is_group && !n.extracted) {
                    n.width = double.max (l.width, n.title_size.width + 2 * CLUSTER_PADDING);
                    n.height = l.height;
                }
            }
            for (int i = 0; i < level.edges.length; i++) {
                var e = level.edges[i];
                var l = g.edge (e.start, e.end, "e%d".printf (i));
                Geometry.Pt[] pts = {};
                foreach (var p in l.points) {
                    pts += Geometry.Pt () { x = p.x, y = p.y };
                }
                e.points = pts;
                e.has_label_position = l.has_xy;
                e.label_x = l.x;
                e.label_y = l.y;
            }
        }

        bool in_level (string id, GraphLevel level) {
            foreach (var n in level.nodes) {
                if (n.id == id) {
                    return true;
                }
            }
            return false;
        }

        /* The height a cluster's title takes at its top. */
        double title_band (GNode n) {
            if (n.group_style == GroupStyle.DIVIDER) {
                return CLUSTER_PADDING;
            }
            return n.label != "" ? n.title_size.height + CLUSTER_PADDING : CLUSTER_PADDING;
        }

        void draw_level (Scene scene, GraphLevel level, TextMeasurer m) {
            double ox = level.origin_x, oy = level.origin_y;

            // Clusters, outermost first.
            foreach (var n in level.nodes) {
                if (n.is_group) {
                    draw_cluster (scene, n, ox, oy);
                }
            }
            // Extracted clusters' contents.
            foreach (var n in level.nodes) {
                if (n.is_group && n.extracted && n.level != null) {
                    var inner = n.level;
                    inner.origin_x = ox + n.x - n.width / 2 + (n.width - inner.width) / 2;
                    inner.origin_y = oy + n.y - n.height / 2 + title_band (n);
                    draw_level (scene, inner, m);
                }
            }
            foreach (var e in level.edges) {
                draw_edge (scene, e, ox, oy);
            }
            foreach (var e in level.edges) {
                draw_edge_labels (scene, e, ox, oy, m);
            }
            foreach (var n in level.nodes) {
                if (!n.is_group) {
                    double x = n.x, y = n.y;
                    n.x += ox;
                    n.y += oy;
                    n.draw (scene);
                    n.x = x;
                    n.y = y;
                }
            }
        }

        void draw_cluster (Scene scene, GNode n, double ox, double oy) {
            double x = ox + n.x - n.width / 2, y = oy + n.y - n.height / 2;
            if (n.group_style == GroupStyle.DIVIDER) {
                var box = new Path ();
                box.rect (x, y, n.width, n.height);
                var d = scene.add_shape (box, Paint (Ink.NONE), Paint (Ink.GROUP_STROKE));
                d.line_style = LineStyle.DASHED;
                return;
            }
            if (n.group_style == GroupStyle.STATE) {
                double band = title_band (n);
                var outer = new Path ();
                outer.rounded_rect (x, y, n.width, n.height, 5);
                scene.add_shape (outer, n.fill, n.stroke, n.stroke_width);
                var inner = new Path ();
                inner.rounded_rect (x + 1, y + band, n.width - 2, n.height - band - 1, 4);
                scene.add_shape (inner, Paint (Ink.BACKGROUND), Paint (Ink.NONE));
                var t = scene.add_text (n.label, x + n.width / 2, y + band / 2, n.text_style);
                t.color = n.color;
                return;
            }
            var path = new Path ();
            path.rounded_rect (x, y, n.width, n.height, 5);
            var fill = n.fill.ink == Ink.NODE_FILL ? Paint (Ink.GROUP_FILL) : n.fill;
            var stroke = n.stroke.ink == Ink.NODE_STROKE ? Paint (Ink.GROUP_STROKE) : n.stroke;
            var s = scene.add_shape (path, fill, stroke, n.stroke_width);
            s.line_style = n.line_style;
            if (n.label != "") {
                var t = scene.add_text (n.label, x + n.width / 2, y + CLUSTER_PADDING / 2 + n.title_size.height / 2,
                                        n.text_style);
                t.color = n.color;
            }
        }

        void draw_edge (Scene scene, GEdge e, double ox, double oy) {
            if (e.invisible || e.points.length < 2) {
                return;
            }
            Geometry.Pt[] pts = {};
            foreach (var p in e.points) {
                pts += Geometry.Pt () { x = p.x + ox, y = p.y + oy };
            }

            // End the edge at the real shape instead of dagre's bounding box.
            var sn = by_id[e.start];
            var en = by_id[e.end];
            if (e.start != e.end || pts.length > 2) {
                if (e.from_cluster == null && sn != null && !sn.is_group) {
                    pts[0] = end_point (sn, ox, oy, pts[1], pts[0]);
                }
                if (e.to_cluster == null && en != null && !en.is_group) {
                    pts[pts.length - 1] = end_point (en, ox, oy, pts[pts.length - 2], pts[pts.length - 1]);
                }
            }
            if (e.from_cluster != null) {
                pts = cut_at_cluster (pts, by_id[e.from_cluster], ox, oy, true);
            }
            if (e.to_cluster != null) {
                pts = cut_at_cluster (pts, by_id[e.to_cluster], ox, oy, false);
            }
            if (pts.length < 2) {
                return;
            }

            // Leave room for the markers.
            Geometry.Pt start_tip = pts[0], end_tip = pts[pts.length - 1];
            double start_len = marker_length (e.start_marker);
            double end_len = marker_length (e.end_marker);
            if (start_len > 0) {
                pts[0] = pull_back (pts[0], pts[1], start_len);
            }
            if (end_len > 0) {
                pts[pts.length - 1] = pull_back (pts[pts.length - 1], pts[pts.length - 2], end_len);
            }

            var path = curve_path (pts, e.curve);
            var s = scene.add_shape (path, Paint (Ink.NONE), e.stroke, e.thickness);
            s.line_style = e.line_style;

            // Markers point along the line; without a gap, along its first segment.
            if (e.start_marker != Marker.NONE) {
                draw_marker (scene, e.start_marker, start_tip, start_len > 0 ? pts[0] : pts[1], e);
            }
            if (e.end_marker != Marker.NONE) {
                draw_marker (scene, e.end_marker, end_tip,
                             end_len > 0 ? pts[pts.length - 1] : pts[pts.length - 2], e);
            }
        }

        /*
         * Where the edge coming from `outside` meets the node's outline; the
         * point dagre gave when it doesn't.
         */
        Geometry.Pt end_point (GNode n, double ox, double oy, Geometry.Pt outside, Geometry.Pt fallback) {
            double x = n.x, y = n.y;
            n.x += ox;
            n.y += oy;
            var outline = n.outline ();
            var c = Geometry.Pt () { x = n.anchor_x (), y = n.y };
            n.x = x;
            n.y = y;
            var hit = Geometry.intersect (outline, c, outside);
            if (hit.x == outside.x && hit.y == outside.y) {
                // No crossing: aim from the dagre point instead.
                var direct = Geometry.intersect (outline, c, fallback);
                return direct.x == fallback.x && direct.y == fallback.y ? fallback : direct;
            }
            return hit;
        }

        /* Cuts the path where it enters (or leaves) the cluster's rectangle. */
        Geometry.Pt[] cut_at_cluster (Geometry.Pt[] pts, GNode? cluster, double ox, double oy, bool at_start) {
            if (cluster == null) {
                return pts;
            }
            double cx = cluster.x + ox, cy = cluster.y + oy;
            var rect = new Path ();
            rect.rect (cx - cluster.width / 2, cy - cluster.height / 2, cluster.width, cluster.height);
            Geometry.Pt[] result = {};
            if (!at_start) {
                for (int i = 0; i < pts.length; i++) {
                    if (Geometry.inside_rect (pts[i], cx, cy, cluster.width, cluster.height) && i > 0) {
                        result += Geometry.intersect (rect, pts[i], pts[i - 1]);
                        return result;
                    }
                    result += pts[i];
                }
                return result;
            }
            int first_out = -1;
            for (int i = 0; i < pts.length; i++) {
                if (!Geometry.inside_rect (pts[i], cx, cy, cluster.width, cluster.height)) {
                    first_out = i;
                    break;
                }
            }
            if (first_out <= 0) {
                return pts;
            }
            result += Geometry.intersect (rect, pts[first_out - 1], pts[first_out]);
            for (int i = first_out; i < pts.length; i++) {
                result += pts[i];
            }
            return result;
        }

        static Geometry.Pt pull_back (Geometry.Pt tip, Geometry.Pt toward, double len) {
            double dx = toward.x - tip.x, dy = toward.y - tip.y;
            double d = Math.sqrt (dx * dx + dy * dy);
            if (d < 1e-6) {
                return tip;
            }
            double k = double.min (len, d * 0.9) / d;
            return Geometry.Pt () { x = tip.x + dx * k, y = tip.y + dy * k };
        }

        static double marker_length (Marker m) {
            switch (m) {
            case Marker.ARROW:
                return 8;
            case Marker.CIRCLE:
                return 9;
            case Marker.CROSS:
                return 6;
            case Marker.EXTENSION:
            case Marker.DEPENDENCY:
                return 14;
            case Marker.COMPOSITION:
            case Marker.AGGREGATION:
                return 20;
            case Marker.LOLLIPOP:
                return 14;
            default:
                return 0;
            }
        }

        /* A marker with its tip at `tip`, pointing away from `from`. */
        void draw_marker (Scene scene, Marker marker, Geometry.Pt tip, Geometry.Pt from, GEdge e) {
            double dx = tip.x - from.x, dy = tip.y - from.y;
            double d = Math.sqrt (dx * dx + dy * dy);
            if (d < 1e-6) {
                return;
            }
            double ux = dx / d, uy = dy / d;   // along the edge
            double nx = -uy, ny = ux;          // across it
            var p = new Path ();
            switch (marker) {
            case Marker.ARROW: {
                double l = 9, w = 4.5;
                p.polygon ({ tip.x, tip.y,
                             tip.x - ux * l + nx * w, tip.y - uy * l + ny * w,
                             tip.x - ux * l - nx * w, tip.y - uy * l - ny * w });
                scene.add_shape (p, e.stroke, e.stroke, 1);
                break;
            }
            case Marker.CIRCLE: {
                double r = 4.5;
                p.ellipse (tip.x - ux * r, tip.y - uy * r, r, r);
                scene.add_shape (p, e.stroke, e.stroke, 1);
                break;
            }
            case Marker.CROSS: {
                double s = 4.5;
                double cx = tip.x - ux * s, cy = tip.y - uy * s;
                p.move_to (cx - ux * s + nx * s, cy - uy * s + ny * s);
                p.line_to (cx + ux * s - nx * s, cy + uy * s - ny * s);
                p.move_to (cx - ux * s - nx * s, cy - uy * s - ny * s);
                p.line_to (cx + ux * s + nx * s, cy + uy * s + ny * s);
                scene.add_shape (p, Paint (Ink.NONE), e.stroke, 2);
                break;
            }
            case Marker.EXTENSION: {
                double l = 14, w = 7;
                p.polygon ({ tip.x, tip.y,
                             tip.x - ux * l + nx * w, tip.y - uy * l + ny * w,
                             tip.x - ux * l - nx * w, tip.y - uy * l - ny * w });
                scene.add_shape (p, Paint (Ink.BACKGROUND), e.stroke, 1);
                break;
            }
            case Marker.DEPENDENCY: {
                double l = 12, w = 6;
                p.polygon ({ tip.x, tip.y,
                             tip.x - ux * l + nx * w, tip.y - uy * l + ny * w,
                             tip.x - ux * l * 0.75, tip.y - uy * l * 0.75,
                             tip.x - ux * l - nx * w, tip.y - uy * l - ny * w });
                scene.add_shape (p, e.stroke, e.stroke, 1);
                break;
            }
            case Marker.COMPOSITION:
            case Marker.AGGREGATION: {
                double l = 20, w = 6;
                p.polygon ({ tip.x, tip.y,
                             tip.x - ux * l / 2 + nx * w, tip.y - uy * l / 2 + ny * w,
                             tip.x - ux * l, tip.y - uy * l,
                             tip.x - ux * l / 2 - nx * w, tip.y - uy * l / 2 - ny * w });
                scene.add_shape (p, marker == Marker.COMPOSITION ? e.stroke : Paint (Ink.BACKGROUND), e.stroke, 1);
                break;
            }
            case Marker.ER_ONLY_ONE:
            case Marker.ER_ZERO_OR_ONE:
            case Marker.ER_ONE_OR_MORE:
            case Marker.ER_ZERO_OR_MORE: {
                // Measured from the tip, along the edge.
                bool many = marker == Marker.ER_ONE_OR_MORE || marker == Marker.ER_ZERO_OR_MORE;
                bool zero = marker == Marker.ER_ZERO_OR_ONE || marker == Marker.ER_ZERO_OR_MORE;
                double w = 8;
                if (many) {
                    double fx = tip.x - ux * 16, fy = tip.y - uy * 16;
                    p.move_to (tip.x + nx * w, tip.y + ny * w);
                    p.line_to (fx, fy);
                    p.line_to (tip.x - nx * w, tip.y - ny * w);
                }
                double bar = many ? 20 : 8;
                p.move_to (tip.x - ux * bar + nx * w, tip.y - uy * bar + ny * w);
                p.line_to (tip.x - ux * bar - nx * w, tip.y - uy * bar - ny * w);
                if (marker == Marker.ER_ONLY_ONE) {
                    p.move_to (tip.x - ux * 14 + nx * w, tip.y - uy * 14 + ny * w);
                    p.line_to (tip.x - ux * 14 - nx * w, tip.y - uy * 14 - ny * w);
                }
                scene.add_shape (p, Paint (Ink.NONE), e.stroke, 1.5);
                if (zero) {
                    double d0 = many ? 20 : 8;
                    var c = new Path ();
                    c.ellipse (tip.x - ux * (d0 + 9), tip.y - uy * (d0 + 9), 5, 5);
                    scene.add_shape (c, Paint (Ink.BACKGROUND), e.stroke, 1.5);
                }
                break;
            }
            case Marker.LOLLIPOP: {
                double r = 5;
                p.ellipse (tip.x - ux * r, tip.y - uy * r, r, r);
                scene.add_shape (p, Paint (Ink.BACKGROUND), e.stroke, 1);
                var stem = new Path ();
                stem.move_to (tip.x - ux * 2 * r, tip.y - uy * 2 * r);
                stem.line_to (from.x, from.y);
                scene.add_shape (stem, Paint (Ink.NONE), e.stroke, e.thickness);
                break;
            }
            default:
                break;
            }
        }

        void draw_edge_labels (Scene scene, GEdge e, double ox, double oy, TextMeasurer m) {
            if (e.invisible) {
                return;
            }
            if (e.label != "" && e.has_label_position) {
                double x = e.label_x + ox, y = e.label_y + oy;
                var bg = new Path ();
                bg.rect (x - e.label_size.width / 2 - 2, y - e.label_size.height / 2,
                         e.label_size.width + 4, e.label_size.height);
                scene.add_shape (bg, Paint (Ink.BACKGROUND), Paint (Ink.NONE));
                var t = scene.add_text (e.label, x, y, e.text_style);
                t.color = e.label_color;
            }
            if (e.points == null || e.points.length < 2) {
                return;
            }
            // Cardinalities, a little away from the ends.
            if (e.start_label != null && e.start_label != "") {
                place_end_label (scene, e, e.start_label, e.points[0], e.points[1], ox, oy, m);
            }
            if (e.end_label != null && e.end_label != "") {
                int n = e.points.length;
                place_end_label (scene, e, e.end_label, e.points[n - 1], e.points[n - 2], ox, oy, m);
            }
        }

        void place_end_label (Scene scene, GEdge e, string text, Geometry.Pt end, Geometry.Pt toward,
                              double ox, double oy, TextMeasurer m) {
            double dx = toward.x - end.x, dy = toward.y - end.y;
            double d = Math.sqrt (dx * dx + dy * dy);
            if (d < 1e-6) {
                return;
            }
            var style = TextStyle (FONT_SIZE * 0.85);
            var size = Mermaid.measure (m, text, style);
            double along = 18, across = size.width / 2 + 6;
            double x = end.x + ox + dx / d * along - dy / d * across;
            double y = end.y + oy + dy / d * along + dx / d * (size.height / 2 + 4);
            scene.add_text (text, x, y, style);
        }

        /* The path through the points with the given curve (d3's curveBasis by default). */
        internal static Path curve_path (Geometry.Pt[] pts, Curve curve) {
            var path = new Path ();
            if (curve == Curve.LINEAR || pts.length < 3) {
                path.move_to (pts[0].x, pts[0].y);
                for (int i = 1; i < pts.length; i++) {
                    path.line_to (pts[i].x, pts[i].y);
                }
                return path;
            }
            if (curve == Curve.STEP) {
                path.move_to (pts[0].x, pts[0].y);
                for (int i = 1; i < pts.length; i++) {
                    double mx = (pts[i - 1].x + pts[i].x) / 2;
                    path.line_to (mx, pts[i - 1].y);
                    path.line_to (mx, pts[i].y);
                    path.line_to (pts[i].x, pts[i].y);
                }
                return path;
            }
            // d3-shape's basis spline.
            double x0 = 0, y0 = 0, x1 = 0, y1 = 0;
            int state = 0;
            foreach (var p in pts) {
                double x = p.x, y = p.y;
                switch (state) {
                case 0:
                    state = 1;
                    path.move_to (x, y);
                    break;
                case 1:
                    state = 2;
                    break;
                case 2:
                    state = 3;
                    path.line_to ((5 * x0 + x1) / 6, (5 * y0 + y1) / 6);
                    basis_point (path, x0, y0, x1, y1, x, y);
                    break;
                default:
                    basis_point (path, x0, y0, x1, y1, x, y);
                    break;
                }
                x0 = x1;
                x1 = x;
                y0 = y1;
                y1 = y;
            }
            if (state == 3) {
                basis_point (path, x0, y0, x1, y1, x1, y1);
            }
            path.line_to (x1, y1);
            return path;
        }

        static void basis_point (Path path, double x0, double y0, double x1, double y1, double x, double y) {
            path.curve_to ((2 * x0 + x1) / 3, (2 * y0 + y1) / 3,
                           (x0 + 2 * x1) / 3, (y0 + 2 * y1) / 3,
                           (x0 + 4 * x1 + x) / 6, (y0 + 4 * y1 + y) / 6);
        }
    }
}
