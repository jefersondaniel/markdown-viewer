/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ported from dagre-d3-es 7.0.14, src/dagre/normalize.js.
 * Copyright (c) 2012-2014 Chris Pettitt, (c) 2022-2024 dagre-es contributors. MIT License.
 *
 * Breaks long edges into segments that span one rank each, with dummy nodes
 * in between, and puts them back together after positioning.
 */

namespace Mermaid.Dagre.Normalize {

    internal void run (Graph g) {
        g.label.dummy_chains = new GenericArray<string> ();
        foreach (var e in g.edges ()) {
            normalize_edge (g, e);
        }
    }

    void normalize_edge (Graph g, EdgeKey e) {
        string v = e.v;
        int v_rank = g.node (v).rank;
        string w = e.w;
        int w_rank = g.node (w).rank;
        string? name = e.name;
        var edge_label = g.edge_of (e);

        if (w_rank == v_rank + 1) {
            return;
        }

        g.remove_edge_key (e);

        int i = 0;
        for (++v_rank; v_rank < w_rank; ++i, ++v_rank) {
            edge_label.points = new GenericArray<Point?> ();
            var attrs = new NodeLabel ();
            attrs.edge_label = edge_label;
            attrs.edge_obj = e;
            attrs.rank = v_rank;
            attrs.has_rank = true;
            string dummy = Util.add_dummy_node (g, "edge", attrs, "_d");
            if (edge_label.has_label_rank && v_rank == edge_label.label_rank) {
                attrs.width = edge_label.width;
                attrs.height = edge_label.height;
                attrs.dummy = "edge-label";
                attrs.labelpos = edge_label.labelpos;
            }
            var segment = new EdgeLabel ();
            segment.weight = edge_label.weight;
            g.set_edge (v, dummy, segment, name);
            if (i == 0) {
                g.label.dummy_chains.add (dummy);
            }
            v = dummy;
        }

        var last = new EdgeLabel ();
        last.weight = edge_label.weight;
        g.set_edge (v, w, last, name);
    }

    internal void undo (Graph g) {
        foreach (unowned string chain in g.label.dummy_chains) {
            string v = chain;
            var node = g.node (v);
            var orig_label = node.edge_label;
            g.set_edge_key (node.edge_obj, orig_label);
            while (node.dummy != null) {
                string w = g.successors (v)[0];
                g.remove_node (v);
                orig_label.points.add (Point () { x = node.x, y = node.y });
                if (node.dummy == "edge-label") {
                    orig_label.x = node.x;
                    orig_label.y = node.y;
                    orig_label.has_xy = true;
                    orig_label.width = node.width;
                    orig_label.height = node.height;
                }
                v = w;
                node = g.node (v);
            }
        }
    }
}
