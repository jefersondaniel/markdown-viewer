/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ported from dagre-d3-es 7.0.14, src/dagre/nesting-graph.js.
 * Copyright (c) 2012-2014 Chris Pettitt, (c) 2022-2024 dagre-es contributors. MIT License.
 *
 * A nesting graph creates dummy nodes for the tops and bottoms of subgraphs,
 * adds edges that keep each subgraph's nodes between these borders, and makes
 * the graph connected. The idea comes from Sander, "Layout of Compound
 * Directed Graphs".
 */

namespace Mermaid.Dagre.NestingGraph {

    internal void run (Graph g) {
        string root = Util.add_dummy_node (g, "root", new NodeLabel (), "_root");
        var depths = tree_depths (g);
        int max_depth = 0;
        foreach (var d in depths.get_values ()) {
            max_depth = int.max (max_depth, d);
        }
        int height = max_depth - 1;
        int node_sep = 2 * height + 1;

        g.label.nesting_root = root;

        // Multiply minlen by node_sep to align nodes on non-border ranks.
        foreach (var e in g.edges ()) {
            g.edge_of (e).minlen *= node_sep;
        }

        // A weight that is sufficient to keep subgraphs vertically compact.
        double weight = sum_weights (g) + 1;

        foreach (unowned string child in g.children ()) {
            dfs (g, root, node_sep, weight, height, depths, child);
        }

        // Saved for removing empty border layers later.
        g.label.node_rank_factor = node_sep;
    }

    void dfs (Graph g, string root, int node_sep, double weight, int height,
              HashTable<string, int> depths, string v) {
        string[] children = g.children (v);
        if (children.length == 0) {
            if (v != root) {
                var label = new EdgeLabel ();
                label.weight = 0;
                label.minlen = node_sep;
                g.set_edge (root, v, label);
            }
            return;
        }

        string top = Util.add_border_node (g, "_bt");
        string bottom = Util.add_border_node (g, "_bb");
        var label = g.node (v);

        g.set_parent (top, v);
        label.border_top = top;
        g.set_parent (bottom, v);
        label.border_bottom = bottom;
        // The title goes on the side that ends up on top.
        string dir = g.label.rankdir.down ();
        if (dir == "tb") {
            g.node (top).height = label.title_height;
        } else if (dir == "bt") {
            g.node (bottom).height = label.title_height;
        }

        foreach (unowned string child in children) {
            dfs (g, root, node_sep, weight, height, depths, child);

            var child_node = g.node (child);
            string child_top = child_node.border_top ?? child;
            string child_bottom = child_node.border_bottom ?? child;
            double this_weight = child_node.border_top != null ? weight : 2 * weight;
            int minlen = child_top != child_bottom ? 1 : height - depths[v] + 1;

            var top_edge = new EdgeLabel ();
            top_edge.weight = this_weight;
            top_edge.minlen = minlen;
            top_edge.nesting_edge = true;
            g.set_edge (top, child_top, top_edge);

            var bottom_edge = new EdgeLabel ();
            bottom_edge.weight = this_weight;
            bottom_edge.minlen = minlen;
            bottom_edge.nesting_edge = true;
            g.set_edge (child_bottom, bottom, bottom_edge);
        }

        if (g.parent (v) == null) {
            var root_edge = new EdgeLabel ();
            root_edge.weight = 0;
            root_edge.minlen = height + depths[v];
            g.set_edge (root, top, root_edge);
        }
    }

    HashTable<string, int> tree_depths (Graph g) {
        var depths = new HashTable<string, int> (str_hash, str_equal);
        foreach (unowned string v in g.children ()) {
            depth_dfs (g, v, 1, depths);
        }
        return depths;
    }

    void depth_dfs (Graph g, string v, int depth, HashTable<string, int> depths) {
        foreach (unowned string child in g.children (v)) {
            depth_dfs (g, child, depth + 1, depths);
        }
        depths.insert (v, depth);
    }

    double sum_weights (Graph g) {
        double sum = 0;
        foreach (var e in g.edges ()) {
            sum += g.edge_of (e).weight;
        }
        return sum;
    }

    internal void cleanup (Graph g) {
        g.remove_node (g.label.nesting_root);
        g.label.nesting_root = null;
        foreach (var e in g.edges ()) {
            if (g.edge_of (e).nesting_edge) {
                g.remove_edge_key (e);
            }
        }
    }
}
