/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ported from dagre-d3-es 7.0.14, src/dagre/position/index.js and bk.js.
 * Copyright (c) 2012-2014 Chris Pettitt, (c) 2022-2024 dagre-es contributors. MIT License.
 *
 * Assigns coordinates: y by rank, x with Brandes and Köpf, "Fast and Simple
 * Horizontal Coordinate Assignment".
 */

namespace Mermaid.Dagre.Position {

    internal void run (Graph input) {
        var g = Util.as_non_compound_graph (input);
        position_y (g);
        var xs = position_x (g);
        xs.foreach ((v, x) => {
            g.node (v).x = x;
        });
    }

    void position_y (Graph g) {
        var layering = Util.build_layer_matrix (g);
        double rank_sep = g.label.ranksep;
        double prev_y = 0;
        foreach (var layer in layering) {
            double max_height = 0;
            foreach (unowned string? v in layer) {
                max_height = double.max (max_height, g.node (v).height);
            }
            foreach (unowned string? v in layer) {
                g.node (v).y = prev_y + max_height / 2;
            }
            prev_y += max_height + rank_sep;
        }
    }

    // Conflicts are stored as "v\x01w" keys with v < w.

    string conflict_key (string v, string w) {
        return strcmp (v, w) > 0 ? w + "\x01" + v : v + "\x01" + w;
    }

    void add_conflict (HashTable<string, bool> conflicts, string v, string w) {
        conflicts.insert (conflict_key (v, w), true);
    }

    bool has_conflict (HashTable<string, bool> conflicts, string v, string w) {
        return conflicts.contains (conflict_key (v, w));
    }

    /*
     * Marks type-1 conflicts: a non-inner segment that crosses an inner
     * segment (an edge between two dummy nodes).
     */
    void find_type1_conflicts (Graph g, GenericArray<GenericArray<string?>> layering,
                               HashTable<string, bool> conflicts) {
        for (int l = 1; l < layering.length; l++) {
            var prev_layer = layering[l - 1];
            var layer = layering[l];
            // The last node in the previous layer that is on an inner segment.
            int k0 = 0;
            // The last node in this layer scanned for crossings.
            int scan_pos = 0;
            int prev_layer_length = prev_layer.length;
            string? last_node = layer.length > 0 ? layer[layer.length - 1] : null;

            for (int i = 0; i < layer.length; i++) {
                string v = layer[i];
                string? w = find_other_inner_segment_node (g, v);
                int k1 = w != null ? g.node (w).order : prev_layer_length;

                if (w != null || v == last_node) {
                    for (int s = scan_pos; s < i + 1; s++) {
                        string scan_node = layer[s];
                        foreach (unowned string u in g.predecessors (scan_node)) {
                            var u_label = g.node (u);
                            int u_pos = u_label.order;
                            if ((u_pos < k0 || k1 < u_pos)
                                && !(u_label.dummy != null && g.node (scan_node).dummy != null)) {
                                add_conflict (conflicts, u, scan_node);
                            }
                        }
                    }
                    scan_pos = i + 1;
                    k0 = k1;
                }
            }
        }
    }

    void find_type2_conflicts (Graph g, GenericArray<GenericArray<string?>> layering,
                               HashTable<string, bool> conflicts) {
        for (int l = 1; l < layering.length; l++) {
            var north = layering[l - 1];
            var south = layering[l];
            int prev_north_pos = -1;
            // dagre leaves this undefined until the first border node, and
            // comparisons with undefined are false.
            int next_north_pos = 0;
            bool has_next_north_pos = false;
            int south_pos = 0;

            for (int south_lookahead = 0; south_lookahead < south.length; south_lookahead++) {
                string v = south[south_lookahead];
                if (g.node (v).dummy == "border") {
                    string[] predecessors = g.predecessors (v);
                    if (predecessors.length > 0) {
                        next_north_pos = g.node (predecessors[0]).order;
                        has_next_north_pos = true;
                        scan (g, south, south_pos, south_lookahead, prev_north_pos, true,
                              next_north_pos, true, conflicts);
                        south_pos = south_lookahead;
                        prev_north_pos = next_north_pos;
                    }
                }
                scan (g, south, south_pos, south.length, next_north_pos, has_next_north_pos,
                      north.length, true, conflicts);
            }
        }
    }

    void scan (Graph g, GenericArray<string?> south, int south_pos, int south_end,
               int prev_north_border, bool has_prev, int next_north_border, bool has_next,
               HashTable<string, bool> conflicts) {
        for (int i = south_pos; i < south_end; i++) {
            string v = south[i];
            if (g.node (v).dummy == null) {
                continue;
            }
            foreach (unowned string u in g.predecessors (v)) {
                var u_node = g.node (u);
                if (u_node.dummy != null
                    && ((has_prev && u_node.order < prev_north_border)
                        || (has_next && u_node.order > next_north_border))) {
                    add_conflict (conflicts, u, v);
                }
            }
        }
    }

    string? find_other_inner_segment_node (Graph g, string v) {
        if (g.node (v).dummy != null) {
            foreach (unowned string u in g.predecessors (v)) {
                if (g.node (u).dummy != null) {
                    return u;
                }
            }
        }
        return null;
    }

    /*
     * Aligns nodes into vertical blocks with one of their median neighbors,
     * skipping neighbors across a type-1 conflict and ones that would split
     * an existing block.
     */
    void vertical_alignment (GenericArray<GenericArray<string?>> layering,
                             HashTable<string, bool> conflicts, bool up, Graph g,
                             out HashTable<string, string> root, out HashTable<string, string> align) {
        root = new HashTable<string, string> (str_hash, str_equal);
        align = new HashTable<string, string> (str_hash, str_equal);
        var pos = new HashTable<string, int> (str_hash, str_equal);

        // Positions come from the layering, which is reordered for the
        // different alignments and so differs from the graph's "order".
        foreach (var layer in layering) {
            for (int order = 0; order < layer.length; order++) {
                string v = layer[order];
                root[v] = v;
                align[v] = v;
                pos[v] = order;
            }
        }

        foreach (var layer in layering) {
            int prev_idx = -1;
            foreach (unowned string? v in layer) {
                var ws = new GenericArray<string> ();
                foreach (unowned string w in up ? g.predecessors (v) : g.successors (v)) {
                    ws.add (w);
                }
                if (ws.length == 0) {
                    continue;
                }
                ws.sort_with_data ((a, b) => pos[a] - pos[b]);
                double mp = (ws.length - 1) / 2.0;
                for (int i = (int) Math.floor (mp), il = (int) Math.ceil (mp); i <= il; ++i) {
                    string w = ws[i];
                    if (align[v] == v && prev_idx < pos[w] && !has_conflict (conflicts, v, w)) {
                        align[w] = v;
                        string r = root[w];
                        align[v] = r;
                        root[v] = r;
                        prev_idx = pos[w];
                    }
                }
            }
        }
    }

    /*
     * Unlike Brandes and Köpf, this builds a graph of the blocks and sweeps
     * it twice: first placing blocks at the smallest coordinates, then
     * moving them to the greatest ones that keep the separation.
     */
    HashTable<string, double?> horizontal_compaction (Graph g, GenericArray<GenericArray<string?>> layering,
                                                      HashTable<string, string> root,
                                                      HashTable<string, string> align, bool reverse_sep) {
        var xs = new HashTable<string, double?> (str_hash, str_equal);
        var block_g = build_block_graph (g, layering, root, reverse_sep);
        string border_type = reverse_sep ? "borderLeft" : "borderRight";

        // First pass: the smallest coordinates.
        iterate (block_g, true, (elem) => {
            double x = 0;
            foreach (var e in block_g.in_edges (elem)) {
                x = double.max (x, xs[e.v] + block_g.edge_of (e).weight);
            }
            xs[elem] = x;
        });

        // Second pass: the greatest coordinates.
        iterate (block_g, false, (elem) => {
            double min = double.INFINITY;
            foreach (var e in block_g.out_edges (elem)) {
                min = double.min (min, xs[e.w] - block_g.edge_of (e).weight);
            }
            var node = g.node (elem);
            if (min != double.INFINITY && node.border_type != border_type) {
                xs[elem] = double.max (xs[elem], min);
            }
        });

        // Every node takes the coordinate of its block's root.
        foreach (unowned string v in align.get_values ()) {
            xs[v] = xs[root[v]];
        }
        return xs;
    }

    delegate void SetXs (string elem);

    void iterate (Graph block_g, bool predecessors, SetXs set_xs) {
        string[] nodes = block_g.nodes ();
        var stack = new GenericArray<string> ();
        foreach (unowned string v in nodes) {
            stack.add (v);
        }
        var visited = new HashTable<string, bool> (str_hash, str_equal);
        while (stack.length > 0) {
            string elem = stack[stack.length - 1];
            stack.remove_index (stack.length - 1);
            if (visited.contains (elem)) {
                set_xs (elem);
            } else {
                visited.insert (elem, true);
                stack.add (elem);
                foreach (unowned string next in predecessors ? block_g.predecessors (elem)
                                                               : block_g.successors (elem)) {
                    stack.add (next);
                }
            }
        }
    }

    Graph build_block_graph (Graph g, GenericArray<GenericArray<string?>> layering,
                             HashTable<string, string> root, bool reverse_sep) {
        var block_graph = new Graph ();
        double node_sep = g.label.nodesep;
        double edge_sep = g.label.edgesep;

        foreach (var layer in layering) {
            string? u = null;
            foreach (unowned string? v in layer) {
                string v_root = root[v];
                block_graph.set_node (v_root);
                if (u != null) {
                    string u_root = root[u];
                    var prev = block_graph.edge (u_root, v_root);
                    var label = new EdgeLabel ();
                    label.weight = double.max (sep (g, node_sep, edge_sep, reverse_sep, v, u),
                                               prev != null ? prev.weight : 0);
                    block_graph.set_edge (u_root, v_root, label);
                }
                u = v;
            }
        }
        return block_graph;
    }

    double sep (Graph g, double node_sep, double edge_sep, bool reverse_sep, string v, string w) {
        var v_label = g.node (v);
        var w_label = g.node (w);
        double sum = 0;
        double delta = 0;

        sum += v_label.width / 2;
        if (v_label.labelpos != null) {
            switch (v_label.labelpos.down ()) {
            case "l":
                delta = -v_label.width / 2;
                break;
            case "r":
                delta = v_label.width / 2;
                break;
            }
        }
        if (delta != 0) {
            sum += reverse_sep ? delta : -delta;
        }
        delta = 0;

        sum += (v_label.dummy != null ? edge_sep : node_sep) / 2;
        sum += (w_label.dummy != null ? edge_sep : node_sep) / 2;

        sum += w_label.width / 2;
        if (w_label.labelpos != null) {
            switch (w_label.labelpos.down ()) {
            case "l":
                delta = w_label.width / 2;
                break;
            case "r":
                delta = -w_label.width / 2;
                break;
            }
        }
        if (delta != 0) {
            sum += reverse_sep ? delta : -delta;
        }
        return sum;
    }

    GenericArray<GenericArray<string?>> reversed_layers (GenericArray<GenericArray<string?>> layering) {
        var result = new GenericArray<GenericArray<string?>> ();
        for (int i = layering.length - 1; i >= 0; i--) {
            result.add (layering[i]);
        }
        return result;
    }

    GenericArray<GenericArray<string?>> reversed_within (GenericArray<GenericArray<string?>> layering) {
        var result = new GenericArray<GenericArray<string?>> ();
        foreach (var layer in layering) {
            var r = new GenericArray<string?> ();
            for (int i = layer.length - 1; i >= 0; i--) {
                r.add (layer[i]);
            }
            result.add (r);
        }
        return result;
    }

    HashTable<string, double?> position_x (Graph g) {
        var layering = Util.build_layer_matrix (g);
        var conflicts = new HashTable<string, bool> (str_hash, str_equal);
        find_type1_conflicts (g, layering, conflicts);
        find_type2_conflicts (g, layering, conflicts);

        // The four alignments: up-left, up-right, down-left, down-right.
        HashTable<string, double?>[] xss = new HashTable<string, double?>[4];
        int k = 0;
        foreach (bool up in new bool[] { true, false }) {
            var adjusted = up ? layering : reversed_layers (layering);
            foreach (bool right in new bool[] { false, true }) {
                if (right) {
                    adjusted = reversed_within (adjusted);
                }
                HashTable<string, string> root, align;
                vertical_alignment (adjusted, conflicts, up, g, out root, out align);
                var xs = horizontal_compaction (g, adjusted, root, align, right);
                if (right) {
                    var negated = new HashTable<string, double?> (str_hash, str_equal);
                    xs.foreach ((v, x) => {
                        negated[v] = -(double) x;
                    });
                    xs = negated;
                }
                xss[k++] = xs;
            }
        }

        var smallest = find_smallest_width_alignment (g, xss);
        align_coordinates (xss, smallest);
        return balance (g, xss, g.label.align);
    }

    HashTable<string, double?> find_smallest_width_alignment (Graph g, HashTable<string, double?>[] xss) {
        HashTable<string, double?>? best = null;
        double best_width = double.INFINITY;
        foreach (var xs in xss) {
            double max = -double.INFINITY;
            double min = double.INFINITY;
            xs.foreach ((v, x) => {
                double half_width = g.node (v).width / 2;
                max = double.max (x + half_width, max);
                min = double.min (x - half_width, min);
            });
            double width = max - min;
            if (width < best_width) {
                best_width = width;
                best = xs;
            }
        }
        return best;
    }

    /*
     * Shifts the left-biased alignments so that their smallest coordinate
     * matches the smallest-width alignment's, and the right-biased ones so
     * that their largest one does.
     */
    void align_coordinates (HashTable<string, double?>[] xss, HashTable<string, double?> align_to) {
        double align_to_min = double.INFINITY, align_to_max = -double.INFINITY;
        align_to.foreach ((v, x) => {
            align_to_min = double.min (align_to_min, x);
            align_to_max = double.max (align_to_max, x);
        });

        for (int k = 0; k < 4; k++) {
            var xs = xss[k];
            if (xs == align_to) {
                continue;
            }
            bool left = k % 2 == 0;
            double min = double.INFINITY, max = -double.INFINITY;
            xs.foreach ((v, x) => {
                min = double.min (min, x);
                max = double.max (max, x);
            });
            double delta = left ? align_to_min - min : align_to_max - max;
            if (delta != 0) {
                var shifted = new HashTable<string, double?> (str_hash, str_equal);
                xs.foreach ((v, x) => {
                    shifted[v] = x + delta;
                });
                xss[k] = shifted;
            }
        }
    }

    HashTable<string, double?> balance (Graph g, HashTable<string, double?>[] xss, string? align) {
        var result = new HashTable<string, double?> (str_hash, str_equal);
        // Iterate in the graph's node order, like the JavaScript object.
        foreach (unowned string v in g.nodes ()) {
            if (!xss[0].contains (v)) {
                continue;
            }
            if (align != null) {
                int k;
                switch (align.down ()) {
                case "ul": k = 0; break;
                case "ur": k = 1; break;
                case "dl": k = 2; break;
                default: k = 3; break;
                }
                result[v] = xss[k][v];
            } else {
                double[] xs = { xss[0][v], xss[1][v], xss[2][v], xss[3][v] };
                // Insertion sort of the four candidates.
                for (int i = 1; i < 4; i++) {
                    for (int j = i; j > 0 && xs[j - 1] > xs[j]; j--) {
                        double t = xs[j];
                        xs[j] = xs[j - 1];
                        xs[j - 1] = t;
                    }
                }
                result[v] = (xs[1] + xs[2]) / 2;
            }
        }
        return result;
    }
}
