/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ported from dagre-d3-es 7.0.14, src/dagre/rank/index.js, util.js,
 * feasible-tree.js and network-simplex.js.
 * Copyright (c) 2012-2014 Chris Pettitt, (c) 2022-2024 dagre-es contributors. MIT License.
 *
 * Assigns a rank to each node so that edges respect their "minlen". The
 * structure follows Gansner et al., "A Technique for Drawing Directed Graphs".
 * Ranks can start at any number, including negative ones; they are
 * normalized later.
 */

namespace Mermaid.Dagre.Rank {

    internal void run (Graph g) {
        switch (g.label.ranker) {
        case "tight-tree":
            longest_path (g);
            feasible_tree (g);
            break;
        case "longest-path":
            longest_path (g);
            break;
        default:
            network_simplex (g);
            break;
        }
    }

    /*
     * Pushes each node to the lowest rank its outgoing edges allow. Fast, but
     * leaves edges longer than needed; it is the starting point for the other
     * rankers.
     */
    internal void longest_path (Graph g) {
        var visited = new HashTable<string, bool> (str_hash, str_equal);
        foreach (unowned string v in g.sources ()) {
            longest_path_dfs (g, v, visited);
        }
    }

    int longest_path_dfs (Graph g, string v, HashTable<string, bool> visited) {
        var label = g.node (v);
        if (visited.contains (v)) {
            return label.rank;
        }
        visited.insert (v, true);

        int rank = int.MAX;
        foreach (var e in g.out_edges (v)) {
            rank = int.min (rank, longest_path_dfs (g, e.w, visited) - g.edge_of (e).minlen);
        }
        if (rank == int.MAX) {
            rank = 0;
        }
        label.rank = rank;
        label.has_rank = true;
        return rank;
    }

    /* How much longer the edge is than its minimum length. */
    internal int slack (Graph g, EdgeKey e) {
        return g.node (e.w).rank - g.node (e.v).rank - g.edge_of (e).minlen;
    }

    /*
     * Builds a spanning tree of tight edges (edges with no slack), shifting
     * ranks until every node is in the tree. Returns the tree as an
     * undirected graph.
     */
    internal Graph feasible_tree (Graph g) {
        var t = new Graph (false);

        // Start from an arbitrary node.
        string start = g.nodes ()[0];
        int size = g.node_count ();
        t.set_node (start, new NodeLabel ());

        while (tight_tree (t, g) < size) {
            var edge = find_min_slack_edge (t, g);
            int delta = t.has_node (edge.v) ? slack (g, edge) : -slack (g, edge);
            foreach (unowned string v in t.nodes ()) {
                g.node (v).rank += delta;
            }
        }
        return t;
    }

    /* Grows the tree with tight edges and returns its node count. */
    int tight_tree (Graph t, Graph g) {
        foreach (unowned string v in t.nodes ()) {
            tight_tree_dfs (t, g, v);
        }
        return t.node_count ();
    }

    void tight_tree_dfs (Graph t, Graph g, string v) {
        foreach (var e in g.node_edges (v)) {
            string w = v == e.v ? e.w : e.v;
            if (!t.has_node (w) && slack (g, e) == 0) {
                t.set_node (w, new NodeLabel ());
                t.set_edge (v, w, new EdgeLabel ());
                tight_tree_dfs (t, g, w);
            }
        }
    }

    /* The edge with the smallest slack that has one end in the tree. */
    EdgeKey? find_min_slack_edge (Graph t, Graph g) {
        EdgeKey? best = null;
        int best_slack = int.MAX;
        foreach (var e in g.edges ()) {
            if (t.has_node (e.v) != t.has_node (e.w)) {
                int s = slack (g, e);
                if (s < best_slack) {
                    best_slack = s;
                    best = e;
                }
            }
        }
        return best;
    }

    /*
     * The network simplex ranker: starts from a feasible tight tree and
     * repeatedly swaps tree edges with a negative cut value for better ones,
     * shortening the edges overall.
     */
    internal void network_simplex (Graph input) {
        var g = Util.simplify (input);
        longest_path (g);
        var t = feasible_tree (g);
        init_low_lim_values (t);
        init_cut_values (t, g);

        EdgeKey? e;
        while ((e = leave_edge (t)) != null) {
            var f = enter_edge (t, g, e);
            exchange_edges (t, g, e, f);
        }
    }

    void init_cut_values (Graph t, Graph g) {
        var vs = Util.dfs (t, t.nodes (), true);
        for (int i = 0; i < vs.length - 1; i++) {
            string child = vs[i];
            string parent = t.node (child).parent;
            t.edge (child, parent).cutvalue = calc_cut_value (t, g, child);
        }
    }

    /* The cut value of the tree edge between `child` and its parent. */
    double calc_cut_value (Graph t, Graph g, string child) {
        string parent = t.node (child).parent;
        // Whether the child is the tail of the edge in the directed graph.
        bool child_is_tail = true;
        var graph_edge = g.edge (child, parent);
        if (graph_edge == null) {
            child_is_tail = false;
            graph_edge = g.edge (parent, child);
        }

        double cut_value = graph_edge.weight;
        foreach (var e in g.node_edges (child)) {
            bool is_out_edge = e.v == child;
            string other = is_out_edge ? e.w : e.v;
            if (other != parent) {
                bool points_to_head = is_out_edge == child_is_tail;
                double other_weight = g.edge_of (e).weight;
                cut_value += points_to_head ? other_weight : -other_weight;
                if (t.has_edge (child, other)) {
                    double other_cut_value = t.edge (child, other).cutvalue;
                    cut_value += points_to_head ? -other_cut_value : other_cut_value;
                }
            }
        }
        return cut_value;
    }

    internal void init_low_lim_values (Graph tree, string? root = null) {
        var visited = new HashTable<string, bool> (str_hash, str_equal);
        // Not `root ?? tree.nodes ()[0]`: valac frees the array too early there.
        string[] nodes = tree.nodes ();
        string start = root != null ? root : nodes[0];
        dfs_assign_low_lim (tree, visited, 1, start, null);
    }

    int dfs_assign_low_lim (Graph tree, HashTable<string, bool> visited, int next_lim,
                            string v, string? parent) {
        int low = next_lim;
        var label = tree.node (v);

        visited.insert (v, true);
        foreach (unowned string w in tree.neighbors (v)) {
            if (!visited.contains (w)) {
                next_lim = dfs_assign_low_lim (tree, visited, next_lim, w, v);
            }
        }

        label.low = low;
        label.lim = next_lim++;
        label.parent = parent;
        return next_lim;
    }

    EdgeKey? leave_edge (Graph tree) {
        foreach (var e in tree.edges ()) {
            if (tree.edge_of (e).cutvalue < 0) {
                return e;
            }
        }
        return null;
    }

    EdgeKey? enter_edge (Graph t, Graph g, EdgeKey edge) {
        string v = edge.v;
        string w = edge.w;

        // Treat v as the tail and w as the head; flip the edge to match the graph.
        if (!g.has_edge (v, w)) {
            v = edge.w;
            w = edge.v;
        }

        var v_label = t.node (v);
        var w_label = t.node (w);
        var tail_label = v_label;
        bool flip = false;

        // If the root is in the tail of the edge, flip the head and tail checks.
        if (v_label.lim > w_label.lim) {
            tail_label = w_label;
            flip = true;
        }

        EdgeKey? best = null;
        int best_slack = int.MAX;
        foreach (var e in g.edges ()) {
            if (flip == is_descendant (t.node (e.v), tail_label)
                && flip != is_descendant (t.node (e.w), tail_label)) {
                int s = slack (g, e);
                if (s < best_slack) {
                    best_slack = s;
                    best = e;
                }
            }
        }
        return best;
    }

    void exchange_edges (Graph t, Graph g, EdgeKey e, EdgeKey f) {
        t.remove_edge (e.v, e.w);
        t.set_edge (f.v, f.w, new EdgeLabel ());
        init_low_lim_values (t);
        init_cut_values (t, g);
        update_ranks (t, g);
    }

    void update_ranks (Graph t, Graph g) {
        // dagre looks for a node without a "parent" in the layout graph's
        // labels, which never have one, so the root is the tree's first node.
        string root = t.nodes ()[0];
        var vs = Util.dfs (t, { root }, false);
        for (int i = 1; i < vs.length; i++) {
            string v = vs[i];
            string parent = t.node (v).parent;
            var edge = g.edge (v, parent);
            bool flipped = false;
            if (edge == null) {
                edge = g.edge (parent, v);
                flipped = true;
            }
            g.node (v).rank = g.node (parent).rank + (flipped ? edge.minlen : -edge.minlen);
        }
    }

    /* Whether v is a descendant of root, by their low and lim values. */
    bool is_descendant (NodeLabel v_label, NodeLabel root_label) {
        return root_label.low <= v_label.lim && v_label.lim <= root_label.lim;
    }
}
