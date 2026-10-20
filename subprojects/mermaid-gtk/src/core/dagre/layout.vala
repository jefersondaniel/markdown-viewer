/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ported from dagre-d3-es 7.0.14, src/dagre/layout.js.
 * Copyright (c) 2012-2014 Chris Pettitt, (c) 2022-2024 dagre-es contributors. MIT License.
 *
 * Lays out a directed graph in ranks. The input graph is a compound
 * multigraph whose node labels carry width and height and whose edge labels
 * carry minlen, weight and the size of their label. Afterwards nodes have x
 * and y (their center), subgraphs also width and height, and edges have
 * points and, when they have a label, x and y.
 */

namespace Mermaid.Dagre {

    internal void layout (Graph g) {
        Util.reset_ids ();
        var layout_graph = build_layout_graph (g);
        run_layout (layout_graph);
        update_input_graph (g, layout_graph);
    }

    void run_layout (Graph g) {
        make_space_for_edge_labels (g);
        remove_self_edges (g);
        Acyclic.run (g);
        NestingGraph.run (g);
        Rank.run (Util.as_non_compound_graph (g));
        inject_edge_label_proxies (g);
        Util.remove_empty_ranks (g);
        NestingGraph.cleanup (g);
        Util.normalize_ranks (g);
        assign_rank_min_max (g);
        remove_edge_label_proxies (g);
        Normalize.run (g);
        parent_dummy_chains (g);
        add_border_segments (g);
        Order.run (g);
        insert_self_edges (g);
        CoordinateSystem.adjust (g);
        Position.run (g);
        position_self_edges (g);
        remove_border_nodes (g);
        Normalize.undo (g);
        fixup_edge_label_coords (g);
        CoordinateSystem.undo (g);
        translate_graph (g);
        assign_node_intersects (g);
        reverse_points_for_reversed_edges (g);
        Acyclic.undo (g);
    }

    /* Copies the results back to the input graph. */
    void update_input_graph (Graph input, Graph layout_graph) {
        foreach (unowned string v in input.nodes ()) {
            var input_label = input.node (v);
            var layout_label = layout_graph.node (v);
            if (input_label != null) {
                input_label.x = layout_label.x;
                input_label.y = layout_label.y;
                if (layout_graph.has_children (v)) {
                    input_label.width = layout_label.width;
                    input_label.height = layout_label.height;
                }
            }
        }

        foreach (var e in input.edges ()) {
            var input_label = input.edge_of (e);
            var layout_label = layout_graph.edge_of (e);
            input_label.points = layout_label.points;
            if (layout_label.has_xy) {
                input_label.x = layout_label.x;
                input_label.y = layout_label.y;
                input_label.has_xy = true;
            }
        }

        input.label.width = layout_graph.label.width;
        input.label.height = layout_graph.label.height;
    }

    /* A copy of the input with only the attributes that influence the layout. */
    Graph build_layout_graph (Graph input) {
        var g = new Graph (true, true, true);
        var graph = new GraphLabel ();
        var src = input.label;
        graph.rankdir = src.rankdir;
        graph.nodesep = src.nodesep;
        graph.edgesep = src.edgesep;
        graph.ranksep = src.ranksep;
        graph.marginx = src.marginx;
        graph.marginy = src.marginy;
        graph.acyclicer = src.acyclicer;
        graph.ranker = src.ranker;
        graph.align = src.align;
        g.label = graph;

        foreach (unowned string v in input.nodes ()) {
            var node = input.node (v);
            var label = new NodeLabel ();
            if (node != null) {
                label.width = node.width;
                label.height = node.height;
                label.title_height = node.title_height;
            }
            g.set_node (v, label);
            g.set_parent (v, input.parent (v));
        }

        foreach (var e in input.edges ()) {
            var edge = input.edge_of (e);
            var label = new EdgeLabel ();
            label.minlen = edge.minlen;
            label.weight = edge.weight;
            label.width = edge.width;
            label.height = edge.height;
            label.labeloffset = edge.labeloffset;
            label.labelpos = edge.labelpos;
            g.set_edge_key (e, label);
        }
        return g;
    }

    /*
     * From the Gansner paper: to make room for edge labels, each rank is
     * split in half by doubling minlen and halving ranksep, and labels go on
     * the midpoints. Labels beside the edge also get some padding.
     */
    void make_space_for_edge_labels (Graph g) {
        var graph = g.label;
        graph.ranksep /= 2;
        foreach (var e in g.edges ()) {
            var edge = g.edge_of (e);
            edge.minlen *= 2;
            if (edge.labelpos.down () != "c") {
                if (graph.rankdir == "TB" || graph.rankdir == "BT") {
                    edge.width += edge.labeloffset;
                } else {
                    edge.height += edge.labeloffset;
                }
            }
        }
    }

    /*
     * Temporary dummy nodes that hold the rank of each edge label, so that
     * removing empty ranks keeps the label's position balanced.
     */
    void inject_edge_label_proxies (Graph g) {
        foreach (var e in g.edges ()) {
            var edge = g.edge_of (e);
            if (edge.width != 0 && edge.height != 0) {
                var v = g.node (e.v);
                var w = g.node (e.w);
                var label = new NodeLabel ();
                label.rank = (w.rank - v.rank) / 2 + v.rank;
                label.has_rank = true;
                label.e = e;
                Util.add_dummy_node (g, "edge-proxy", label, "_ep");
            }
        }
    }

    void assign_rank_min_max (Graph g) {
        int max_rank = 0;
        foreach (unowned string v in g.nodes ()) {
            var node = g.node (v);
            if (node.border_top != null) {
                node.min_rank = g.node (node.border_top).rank;
                node.max_rank = g.node (node.border_bottom).rank;
                node.has_min_rank = true;
                max_rank = int.max (max_rank, node.max_rank);
            }
        }
        g.label.max_rank = max_rank;
    }

    void remove_edge_label_proxies (Graph g) {
        foreach (unowned string v in g.nodes ()) {
            var node = g.node (v);
            if (node.dummy == "edge-proxy") {
                var edge = g.edge_of (node.e);
                edge.label_rank = node.rank;
                edge.has_label_rank = true;
                g.remove_node (v);
            }
        }
    }

    void translate_graph (Graph g) {
        double min_x = double.INFINITY;
        double max_x = 0;
        double min_y = double.INFINITY;
        double max_y = 0;
        var graph_label = g.label;
        double margin_x = graph_label.marginx;
        double margin_y = graph_label.marginy;

        foreach (unowned string v in g.nodes ()) {
            var n = g.node (v);
            min_x = double.min (min_x, n.x - n.width / 2);
            max_x = double.max (max_x, n.x + n.width / 2);
            min_y = double.min (min_y, n.y - n.height / 2);
            max_y = double.max (max_y, n.y + n.height / 2);
        }
        foreach (var e in g.edges ()) {
            var edge = g.edge_of (e);
            if (edge.has_xy) {
                min_x = double.min (min_x, edge.x - edge.width / 2);
                max_x = double.max (max_x, edge.x + edge.width / 2);
                min_y = double.min (min_y, edge.y - edge.height / 2);
                max_y = double.max (max_y, edge.y + edge.height / 2);
            }
        }

        min_x -= margin_x;
        min_y -= margin_y;

        foreach (unowned string v in g.nodes ()) {
            var node = g.node (v);
            node.x -= min_x;
            node.y -= min_y;
        }

        foreach (var e in g.edges ()) {
            var edge = g.edge_of (e);
            if (edge.points != null) {
                for (int i = 0; i < edge.points.length; i++) {
                    var p = edge.points[i];
                    edge.points[i] = Point () { x = p.x - min_x, y = p.y - min_y };
                }
            }
            if (edge.has_xy) {
                edge.x -= min_x;
                edge.y -= min_y;
            }
        }

        graph_label.width = max_x - min_x + margin_x;
        graph_label.height = max_y - min_y + margin_y;
    }

    void assign_node_intersects (Graph g) {
        foreach (var e in g.edges ()) {
            var edge = g.edge_of (e);
            var node_v = g.node (e.v);
            var node_w = g.node (e.w);
            Point p1, p2;
            if (edge.points == null) {
                edge.points = new GenericArray<Point?> ();
                p1 = Point () { x = node_w.x, y = node_w.y };
                p2 = Point () { x = node_v.x, y = node_v.y };
            } else {
                p1 = edge.points[0];
                p2 = edge.points[edge.points.length - 1];
            }
            edge.points.insert (0, Util.intersect_rect (node_v, p1));
            edge.points.add (Util.intersect_rect (node_w, p2));
        }
    }

    void fixup_edge_label_coords (Graph g) {
        foreach (var e in g.edges ()) {
            var edge = g.edge_of (e);
            if (edge.has_xy) {
                if (edge.labelpos == "l" || edge.labelpos == "r") {
                    edge.width -= edge.labeloffset;
                }
                switch (edge.labelpos) {
                case "l":
                    edge.x -= edge.width / 2 + edge.labeloffset;
                    break;
                case "r":
                    edge.x += edge.width / 2 + edge.labeloffset;
                    break;
                }
            }
        }
    }

    void reverse_points_for_reversed_edges (Graph g) {
        foreach (var e in g.edges ()) {
            var edge = g.edge_of (e);
            if (edge.reversed) {
                var points = new GenericArray<Point?> ();
                for (int i = edge.points.length - 1; i >= 0; i--) {
                    points.add (edge.points[i]);
                }
                edge.points = points;
            }
        }
    }

    void remove_border_nodes (Graph g) {
        foreach (unowned string v in g.nodes ()) {
            if (g.has_children (v)) {
                var node = g.node (v);
                var t = g.node (node.border_top);
                var b = g.node (node.border_bottom);
                var l = g.node (node.last_border (true));
                var r = g.node (node.last_border (false));

                // Border nodes only have a size when they hold a title.
                double left = l.x - l.width / 2, right = r.x + r.width / 2;
                double top = t.y - t.height / 2, bottom = b.y + b.height / 2;
                node.width = Math.fabs (right - left);
                node.height = Math.fabs (bottom - top);
                node.x = left + node.width / 2;
                node.y = top + node.height / 2;
            }
        }
        foreach (unowned string v in g.nodes ()) {
            if (g.node (v).dummy == "border") {
                g.remove_node (v);
            }
        }
    }

    void remove_self_edges (Graph g) {
        foreach (var e in g.edges ()) {
            if (e.v == e.w) {
                var node = g.node (e.v);
                if (node.self_edges == null) {
                    node.self_edges = new GenericArray<SelfEdge> ();
                }
                var self_edge = new SelfEdge ();
                self_edge.e = e;
                self_edge.label = g.edge_of (e);
                node.self_edges.add (self_edge);
                g.remove_edge_key (e);
            }
        }
    }

    void insert_self_edges (Graph g) {
        var layers = Util.build_layer_matrix (g);
        foreach (var layer in layers) {
            int order_shift = 0;
            for (int i = 0; i < layer.length; i++) {
                var node = g.node (layer[i]);
                node.order = i + order_shift;
                if (node.self_edges == null) {
                    continue;
                }
                foreach (var self_edge in node.self_edges) {
                    var label = new NodeLabel ();
                    label.width = self_edge.label.width;
                    label.height = self_edge.label.height;
                    label.rank = node.rank;
                    label.has_rank = true;
                    label.order = i + ++order_shift;
                    label.e = self_edge.e;
                    label.label = self_edge.label;
                    Util.add_dummy_node (g, "selfedge", label, "_se");
                }
                node.self_edges = null;
            }
        }
    }

    void position_self_edges (Graph g) {
        foreach (unowned string v in g.nodes ()) {
            var node = g.node (v);
            if (node.dummy == "selfedge") {
                var self_node = g.node (node.e.v);
                double x = self_node.x + self_node.width / 2;
                double y = self_node.y;
                double dx = node.x - x;
                double dy = self_node.height / 2;
                g.set_edge_key (node.e, node.label);
                g.remove_node (v);
                var points = new GenericArray<Point?> ();
                points.add (Point () { x = x + 2 * dx / 3, y = y - dy });
                points.add (Point () { x = x + 5 * dx / 6, y = y - dy });
                points.add (Point () { x = x + dx, y = y });
                points.add (Point () { x = x + 5 * dx / 6, y = y + dy });
                points.add (Point () { x = x + 2 * dx / 3, y = y + dy });
                node.label.points = points;
                node.label.x = node.x;
                node.label.y = node.y;
                node.label.has_xy = true;
            }
        }
    }
}
