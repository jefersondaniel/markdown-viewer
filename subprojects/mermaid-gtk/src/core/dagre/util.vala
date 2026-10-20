/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ported from dagre-d3-es 7.0.14, src/dagre/util.js and src/graphlib/alg/dfs.js.
 * Copyright (c) 2012-2014 Chris Pettitt, (c) 2022-2024 dagre-es contributors. MIT License.
 */

namespace Mermaid.Dagre.Util {

    /* lodash's uniqueId; reset for every layout so results are reproducible. */
    int id_counter = 0;

    internal void reset_ids () {
        id_counter = 0;
    }

    internal string unique_id (string prefix) {
        return "%s%d".printf (prefix, ++id_counter);
    }

    internal string add_dummy_node (Graph g, string type, NodeLabel attrs, string name) {
        string v = unique_id (name);
        while (g.has_node (v)) {
            v = unique_id (name);
        }
        attrs.dummy = type;
        g.set_node (v, attrs);
        return v;
    }

    /* A copy with simple edges: multi-edges have their weights summed. */
    internal Graph simplify (Graph g) {
        var simplified = new Graph ();
        simplified.label = g.label;
        foreach (unowned string v in g.nodes ()) {
            simplified.set_node (v, g.node (v));
        }
        foreach (var e in g.edges ()) {
            var simple = simplified.edge (e.v, e.w);
            double weight = simple != null ? simple.weight : 0;
            int minlen = simple != null ? simple.minlen : 1;
            var label = g.edge_of (e);
            var result = new EdgeLabel ();
            result.weight = weight + label.weight;
            result.minlen = int.max (minlen, label.minlen);
            simplified.set_edge (e.v, e.w, result);
        }
        return simplified;
    }

    internal Graph as_non_compound_graph (Graph g) {
        var simplified = new Graph (true, g.multigraph);
        simplified.label = g.label;
        foreach (unowned string v in g.nodes ()) {
            if (!g.has_children (v)) {
                simplified.set_node (v, g.node (v));
            }
        }
        foreach (var e in g.edges ()) {
            simplified.set_edge_key (e, g.edge_of (e));
        }
        return simplified;
    }

    /*
     * Where a line from `point` towards the center of `rect` crosses the
     * rectangle's border.
     */
    internal Point intersect_rect (NodeLabel rect, Point point) {
        double x = rect.x;
        double y = rect.y;
        double dx = point.x - x;
        double dy = point.y - y;
        double w = rect.width / 2;
        double h = rect.height / 2;

        if (dx == 0 && dy == 0) {
            // dagre throws here; a point inside the node has no border crossing.
            return Point () { x = x, y = y };
        }

        double sx, sy;
        if (Math.fabs (dy) * w > Math.fabs (dx) * h) {
            if (dy < 0) {
                h = -h;
            }
            sx = h * dx / dy;
            sy = h;
        } else {
            if (dx < 0) {
                w = -w;
            }
            sx = w;
            sy = w * dy / dx;
        }
        return Point () { x = x + sx, y = y + sy };
    }

    /* The node ids of each rank, ordered by their "order". */
    internal GenericArray<GenericArray<string?>> build_layer_matrix (Graph g) {
        var layering = new GenericArray<GenericArray<string?>> ();
        int max = max_rank (g);
        for (int i = 0; i <= max; i++) {
            layering.add (new GenericArray<string?> ());
        }
        foreach (unowned string v in g.nodes ()) {
            var node = g.node (v);
            if (node.has_rank) {
                var layer = layering[node.rank];
                while (layer.length <= node.order) {
                    layer.add (null);
                }
                layer[node.order] = v;
            }
        }
        return layering;
    }

    /* Shifts ranks so that the smallest one is 0. */
    internal void normalize_ranks (Graph g) {
        int min = int.MAX;
        foreach (unowned string v in g.nodes ()) {
            var node = g.node (v);
            if (node.has_rank) {
                min = int.min (min, node.rank);
            }
        }
        foreach (unowned string v in g.nodes ()) {
            var node = g.node (v);
            if (node.has_rank) {
                node.rank -= min;
            }
        }
    }

    internal void remove_empty_ranks (Graph g) {
        // Ranks may not start at 0, so we need to offset them.
        int offset = int.MAX;
        int max = int.MIN;
        foreach (unowned string v in g.nodes ()) {
            var node = g.node (v);
            if (node.has_rank) {
                offset = int.min (offset, node.rank);
                max = int.max (max, node.rank);
            }
        }
        if (offset == int.MAX) {
            return;
        }

        var layers = new GenericArray<GenericArray<string>?> ();
        for (int i = 0; i <= max - offset; i++) {
            layers.add (null);
        }
        foreach (unowned string v in g.nodes ()) {
            var node = g.node (v);
            if (!node.has_rank) {
                continue;
            }
            int rank = node.rank - offset;
            if (layers[rank] == null) {
                layers[rank] = new GenericArray<string> ();
            }
            layers[rank].add (v);
        }

        int delta = 0;
        int factor = g.label.node_rank_factor;
        for (int i = 0; i < layers.length; i++) {
            var vs = layers[i];
            if (vs == null && (factor == 0 || i % factor != 0)) {
                --delta;
            } else if (delta != 0 && vs != null) {
                foreach (unowned string v in vs) {
                    g.node (v).rank += delta;
                }
            }
        }
    }

    internal string add_border_node (Graph g, string prefix) {
        return add_dummy_node (g, "border", new NodeLabel (), prefix);
    }

    internal int max_rank (Graph g) {
        int max = -1;
        foreach (unowned string v in g.nodes ()) {
            var node = g.node (v);
            if (node != null && node.has_rank) {
                max = int.max (max, node.rank);
            }
        }
        return max;
    }

    /* graphlib's alg.preorder and alg.postorder. */
    internal GenericArray<string> dfs (Graph g, string[] vs, bool postorder) {
        var acc = new GenericArray<string> ();
        var visited = new HashTable<string, bool> (str_hash, str_equal);
        foreach (unowned string v in vs) {
            do_dfs (g, v, postorder, visited, acc);
        }
        return acc;
    }

    void do_dfs (Graph g, string v, bool postorder, HashTable<string, bool> visited, GenericArray<string> acc) {
        if (visited.contains (v)) {
            return;
        }
        visited.insert (v, true);
        if (!postorder) {
            acc.add (v);
        }
        string[] next = g.directed ? g.successors (v) : g.neighbors (v);
        foreach (unowned string w in next) {
            do_dfs (g, w, postorder, visited, acc);
        }
        if (postorder) {
            acc.add (v);
        }
    }
}
