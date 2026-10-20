/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ported from dagre-d3-es 7.0.14, src/dagre/parent-dummy-chains.js,
 * add-border-segments.js and coordinate-system.js.
 * Copyright (c) 2012-2014 Chris Pettitt, (c) 2022-2024 dagre-es contributors. MIT License.
 */

namespace Mermaid.Dagre {

    struct LowLim {
        public int low;
        public int lim;
    }

    /* Puts the dummy nodes of each long edge into the subgraphs it passes through. */
    internal void parent_dummy_chains (Graph g) {
        var postorder_nums = postorder_numbers (g);

        foreach (unowned string chain in g.label.dummy_chains) {
            string v = chain;
            var node = g.node (v);
            var edge_obj = node.edge_obj;
            string?[] path;
            string? lca;
            find_path (g, postorder_nums, edge_obj.v, edge_obj.w, out path, out lca);
            int path_idx = 0;
            string? path_v = path[path_idx];
            bool ascending = true;

            while (v != edge_obj.w) {
                node = g.node (v);

                if (ascending) {
                    while ((path_v = path[path_idx]) != lca && g.node (path_v).max_rank < node.rank) {
                        path_idx++;
                    }
                    if (path_v == lca) {
                        ascending = false;
                    }
                }

                if (!ascending) {
                    while (path_idx < path.length - 1
                           && g.node ((path_v = path[path_idx + 1])).min_rank <= node.rank) {
                        path_idx++;
                    }
                    path_v = path[path_idx];
                }

                g.set_parent (v, path_v);
                v = g.successors (v)[0];
            }
        }
    }

    /* The path from v to w through their lowest common ancestor. */
    void find_path (Graph g, HashTable<string, LowLim?> nums, string v, string w,
                    out string?[] path, out string? lca) {
        string?[] v_path = {};
        string?[] w_path = {};
        int low = int.min (nums[v].low, nums[w].low);
        int lim = int.max (nums[v].lim, nums[w].lim);

        // Traverse up from v to find the LCA.
        string? parent = v;
        do {
            parent = g.parent (parent);
            v_path += parent;
        } while (parent != null && (nums[parent].low > low || lim > nums[parent].lim));
        lca = parent;

        // Traverse from w to the LCA.
        parent = w;
        while ((parent = g.parent (parent)) != lca) {
            w_path += parent;
        }

        for (int i = w_path.length - 1; i >= 0; i--) {
            v_path += w_path[i];
        }
        path = v_path;
    }

    HashTable<string, LowLim?> postorder_numbers (Graph g) {
        var result = new HashTable<string, LowLim?> (str_hash, str_equal);
        int lim = 0;
        foreach (unowned string v in g.children ()) {
            postorder_visit (g, v, result, ref lim);
        }
        return result;
    }

    void postorder_visit (Graph g, string v, HashTable<string, LowLim?> result, ref int lim) {
        int low = lim;
        foreach (unowned string child in g.children (v)) {
            postorder_visit (g, child, result, ref lim);
        }
        result.insert (v, LowLim () { low = low, lim = lim++ });
    }

    /* Adds left and right border nodes for each rank that a subgraph spans. */
    internal void add_border_segments (Graph g) {
        foreach (unowned string v in g.children ()) {
            border_segments_dfs (g, v);
        }
    }

    void border_segments_dfs (Graph g, string v) {
        foreach (unowned string child in g.children (v)) {
            border_segments_dfs (g, child);
        }
        var node = g.node (v);
        if (node.has_min_rank) {
            node.border_left = new HashTable<int, string> (direct_hash, direct_equal);
            node.border_right = new HashTable<int, string> (direct_hash, direct_equal);
            for (int rank = node.min_rank; rank < node.max_rank + 1; ++rank) {
                add_segment_node (g, true, "_bl", v, node, rank);
                add_segment_node (g, false, "_br", v, node, rank);
            }
        }
    }

    void add_segment_node (Graph g, bool left, string prefix, string sg, NodeLabel sg_node, int rank) {
        var label = new NodeLabel ();
        label.rank = rank;
        label.has_rank = true;
        label.border_type = left ? "borderLeft" : "borderRight";
        // For left-right layouts the left border ends up on top; see
        // NodeLabel.title_height. Heights become widths before positioning.
        string dir = g.label.rankdir.down ();
        if (left && (dir == "lr" || dir == "rl")) {
            label.height = sg_node.title_height;
        }
        var borders = left ? sg_node.border_left : sg_node.border_right;
        string? prev = borders.lookup (rank - 1);
        string curr = Util.add_dummy_node (g, "border", label, prefix);
        borders.insert (rank, curr);
        g.set_parent (curr, sg);
        if (prev != null) {
            var edge = new EdgeLabel ();
            edge.weight = 1;
            g.set_edge (prev, curr, edge);
        }
    }

    namespace CoordinateSystem {

        internal void adjust (Graph g) {
            string dir = g.label.rankdir.down ();
            if (dir == "lr" || dir == "rl") {
                swap_width_height (g);
            }
        }

        internal void undo (Graph g) {
            string dir = g.label.rankdir.down ();
            if (dir == "bt" || dir == "rl") {
                reverse_y (g);
            }
            if (dir == "lr" || dir == "rl") {
                swap_xy (g);
                swap_width_height (g);
            }
        }

        void swap_width_height (Graph g) {
            foreach (unowned string v in g.nodes ()) {
                var n = g.node (v);
                double w = n.width;
                n.width = n.height;
                n.height = w;
            }
            foreach (var e in g.edges ()) {
                var l = g.edge_of (e);
                double w = l.width;
                l.width = l.height;
                l.height = w;
            }
        }

        void reverse_y (Graph g) {
            foreach (unowned string v in g.nodes ()) {
                var n = g.node (v);
                n.y = -n.y;
            }
            foreach (var e in g.edges ()) {
                var l = g.edge_of (e);
                if (l.points != null) {
                    for (int i = 0; i < l.points.length; i++) {
                        l.points[i] = Point () { x = l.points[i].x, y = -l.points[i].y };
                    }
                }
                if (l.has_xy) {
                    l.y = -l.y;
                }
            }
        }

        void swap_xy (Graph g) {
            foreach (unowned string v in g.nodes ()) {
                var n = g.node (v);
                double x = n.x;
                n.x = n.y;
                n.y = x;
            }
            foreach (var e in g.edges ()) {
                var l = g.edge_of (e);
                if (l.points != null) {
                    for (int i = 0; i < l.points.length; i++) {
                        l.points[i] = Point () { x = l.points[i].y, y = l.points[i].x };
                    }
                }
                if (l.has_xy) {
                    double x = l.x;
                    l.x = l.y;
                    l.y = x;
                }
            }
        }
    }
}
