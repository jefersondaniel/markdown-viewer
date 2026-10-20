/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ported from dagre-d3-es 7.0.14, src/dagre/order/*.js.
 * Copyright (c) 2012-2014 Chris Pettitt, (c) 2022-2024 dagre-es contributors. MIT License.
 *
 * Orders the nodes within each rank to reduce edge crossings, sweeping up and
 * down the ranks with the barycenter heuristic and keeping the best result.
 */

namespace Mermaid.Dagre.Order {

    internal void run (Graph g) {
        int max_rank = Util.max_rank (g);
        var down_layer_graphs = new GenericArray<Graph> ();
        for (int rank = 1; rank < max_rank + 1; rank++) {
            down_layer_graphs.add (build_layer_graph (g, rank, true));
        }
        var up_layer_graphs = new GenericArray<Graph> ();
        for (int rank = max_rank - 1; rank > -1; rank--) {
            up_layer_graphs.add (build_layer_graph (g, rank, false));
        }

        var layering = init_order (g);
        assign_order (g, layering);

        double best_cc = double.INFINITY;
        GenericArray<GenericArray<string?>>? best = null;

        for (int i = 0, last_best = 0; last_best < 4; ++i, ++last_best) {
            sweep_layer_graphs (i % 2 != 0 ? down_layer_graphs : up_layer_graphs, i % 4 >= 2);

            layering = Util.build_layer_matrix (g);
            double cc = cross_count (g, layering);
            if (cc < best_cc) {
                last_best = 0;
                best = copy_layering (layering);
                best_cc = cc;
            }
        }

        assign_order (g, best);
    }

    GenericArray<GenericArray<string?>> copy_layering (GenericArray<GenericArray<string?>> layering) {
        var copy = new GenericArray<GenericArray<string?>> ();
        foreach (var layer in layering) {
            var l = new GenericArray<string?> ();
            foreach (unowned string? v in layer) {
                l.add (v);
            }
            copy.add (l);
        }
        return copy;
    }

    void sweep_layer_graphs (GenericArray<Graph> layer_graphs, bool bias_right) {
        var cg = new Graph ();
        foreach (var lg in layer_graphs) {
            string root = lg.label.root;
            var sorted = sort_subgraph (lg, root, cg, bias_right);
            for (int i = 0; i < sorted.vs.length; i++) {
                lg.node (sorted.vs[i]).order = i;
            }
            add_subgraph_constraints (lg, cg, sorted.vs);
        }
    }

    void assign_order (Graph g, GenericArray<GenericArray<string?>> layering) {
        foreach (var layer in layering) {
            for (int i = 0; i < layer.length; i++) {
                g.node (layer[i]).order = i;
            }
        }
    }

    /*
     * The initial order: a depth-first search from the nodes of the first
     * rank, placing each node in its rank as it is first visited.
     */
    GenericArray<GenericArray<string?>> init_order (Graph g) {
        var visited = new HashTable<string, bool> (str_hash, str_equal);
        var simple_nodes = new GenericArray<string> ();
        int max_rank = -1;
        foreach (unowned string v in g.nodes ()) {
            if (!g.has_children (v)) {
                simple_nodes.add (v);
                max_rank = int.max (max_rank, g.node (v).rank);
            }
        }
        var layers = new GenericArray<GenericArray<string?>> ();
        for (int i = 0; i <= max_rank; i++) {
            layers.add (new GenericArray<string?> ());
        }

        // A stable sort by rank.
        simple_nodes.sort_with_data ((a, b) => g.node (a).rank - g.node (b).rank);
        foreach (unowned string v in simple_nodes) {
            init_order_dfs (g, v, visited, layers);
        }
        return layers;
    }

    void init_order_dfs (Graph g, string v, HashTable<string, bool> visited,
                         GenericArray<GenericArray<string?>> layers) {
        if (visited.contains (v)) {
            return;
        }
        visited.insert (v, true);
        layers[g.node (v).rank].add (v);
        foreach (unowned string w in g.successors (v)) {
            init_order_dfs (g, w, visited, layers);
        }
    }

    /*
     * A graph for sorting one rank: its nodes with their subgraph hierarchy,
     * under a new root, plus the edges to the neighboring rank (incoming ones
     * when `down`, outgoing ones otherwise) with summed weights.
     */
    Graph build_layer_graph (Graph g, int rank, bool down) {
        string root = Util.unique_id ("_root");
        while (g.has_node (root)) {
            root = Util.unique_id ("_root");
        }
        var result = new Graph (true, false, true);
        result.label.root = root;
        result.set_default_node_label ((v) => g.node (v));

        foreach (unowned string v in g.nodes ()) {
            var node = g.node (v);
            string? parent = g.parent (v);

            if ((node.has_rank && node.rank == rank)
                || (node.has_min_rank && node.min_rank <= rank && rank <= node.max_rank)) {
                result.set_node (v);
                result.set_parent (v, parent ?? root);

                // This assumes there are only short edges.
                foreach (var e in down ? g.in_edges (v) : g.out_edges (v)) {
                    string u = e.v == v ? e.w : e.v;
                    var edge = result.edge (u, v);
                    double weight = edge != null ? edge.weight : 0;
                    var label = new EdgeLabel ();
                    label.weight = g.edge_of (e).weight + weight;
                    result.set_edge (u, v, label);
                }

                if (node.has_min_rank) {
                    var borders = new NodeLabel ();
                    borders.layer_border_left = node.border_left.lookup (rank);
                    borders.layer_border_right = node.border_right.lookup (rank);
                    result.set_node (v, borders);
                }
            }
        }
        return result;
    }

    /* The weighted number of crossings, from Barth et al., "Bilayer Cross Counting". */
    double cross_count (Graph g, GenericArray<GenericArray<string?>> layering) {
        double cc = 0;
        for (int i = 1; i < layering.length; ++i) {
            cc += two_layer_cross_count (g, layering[i - 1], layering[i]);
        }
        return cc;
    }

    struct SouthEntry {
        public int pos;
        public double weight;
    }

    double two_layer_cross_count (Graph g, GenericArray<string?> north, GenericArray<string?> south) {
        // Sort the edges between the layers by their position in the north
        // layer and then the south, mapped to their head's position.
        var south_pos = new HashTable<string, int> (str_hash, str_equal);
        for (int i = 0; i < south.length; i++) {
            south_pos.insert (south[i], i);
        }
        var entries = new Array<SouthEntry?> ();
        foreach (unowned string? v in north) {
            var row = new GenericArray<SouthEntry?> ();
            foreach (var e in g.out_edges (v)) {
                row.add (SouthEntry () { pos = south_pos[e.w], weight = g.edge_of (e).weight });
            }
            row.sort_with_data ((a, b) => a.pos - b.pos);
            foreach (var entry in row) {
                entries.append_val (entry);
            }
        }

        // Build the accumulator tree.
        int first_index = 1;
        while (first_index < south.length) {
            first_index <<= 1;
        }
        int tree_size = 2 * first_index - 1;
        first_index -= 1;
        var tree = new double[tree_size];

        double cc = 0;
        for (uint k = 0; k < entries.length; k++) {
            var entry = entries.index (k);
            int index = entry.pos + first_index;
            tree[index] += entry.weight;
            double weight_sum = 0;
            while (index > 0) {
                if (index % 2 != 0) {
                    weight_sum += tree[index + 1];
                }
                index = (index - 1) >> 1;
                tree[index] += entry.weight;
            }
            cc += entry.weight * weight_sum;
        }
        return cc;
    }

    // Sorting a subgraph.

    class Entry {
        public string v;
        public bool has_barycenter;
        public double barycenter;
        public double weight;
    }

    class SortResult {
        public GenericArray<string> vs = new GenericArray<string> ();
        public bool has_barycenter;
        public double barycenter;
        public double weight;
    }

    class ConflictEntry {
        public int indegree;
        public GenericArray<ConflictEntry> in_ = new GenericArray<ConflictEntry> ();
        public GenericArray<ConflictEntry> out_ = new GenericArray<ConflictEntry> ();
        public GenericArray<string> vs = new GenericArray<string> ();
        public int i;
        public bool has_barycenter;
        public double barycenter;
        public double weight;
        public bool merged;
    }

    GenericArray<Entry> barycenter (Graph g, string[] movable) {
        var result = new GenericArray<Entry> ();
        foreach (unowned string v in movable) {
            var entry = new Entry ();
            entry.v = v;
            var in_v = g.in_edges (v);
            if (in_v.length > 0) {
                double sum = 0, weight = 0;
                foreach (var e in in_v) {
                    var edge = g.edge_of (e);
                    sum += edge.weight * g.node (e.v).order;
                    weight += edge.weight;
                }
                entry.has_barycenter = true;
                entry.barycenter = sum / weight;
                entry.weight = weight;
            }
            result.add (entry);
        }
        return result;
    }

    SortResult sort_subgraph (Graph g, string v, Graph cg, bool bias_right) {
        string[] movable = g.children (v);
        var node = g.node (v);
        string? bl = node != null ? node.layer_border_left : null;
        string? br = node != null ? node.layer_border_right : null;
        var subgraphs = new HashTable<string, SortResult> (str_hash, str_equal);

        if (bl != null) {
            string[] filtered = {};
            foreach (unowned string w in movable) {
                if (w != bl && w != br) {
                    filtered += w;
                }
            }
            movable = filtered;
        }

        var barycenters = barycenter (g, movable);
        foreach (var entry in barycenters) {
            if (g.has_children (entry.v)) {
                var subgraph_result = sort_subgraph (g, entry.v, cg, bias_right);
                subgraphs.insert (entry.v, subgraph_result);
                if (subgraph_result.has_barycenter) {
                    merge_barycenters (entry, subgraph_result);
                }
            }
        }

        var entries = resolve_conflicts (barycenters, cg);
        expand_subgraphs (entries, subgraphs);

        var result = sort (entries, bias_right);

        if (bl != null) {
            var vs = new GenericArray<string> ();
            vs.add (bl);
            foreach (unowned string w in result.vs) {
                vs.add (w);
            }
            vs.add (br);
            result.vs = vs;
            string[] bl_preds = g.predecessors (bl);
            if (bl_preds.length > 0) {
                var bl_pred = g.node (bl_preds[0]);
                var br_pred = g.node (g.predecessors (br)[0]);
                if (!result.has_barycenter) {
                    result.barycenter = 0;
                    result.weight = 0;
                    result.has_barycenter = true;
                }
                result.barycenter = (result.barycenter * result.weight + bl_pred.order + br_pred.order)
                    / (result.weight + 2);
                result.weight += 2;
            }
        }
        return result;
    }

    void expand_subgraphs (GenericArray<ConflictEntry> entries, HashTable<string, SortResult> subgraphs) {
        foreach (var entry in entries) {
            var vs = new GenericArray<string> ();
            foreach (unowned string v in entry.vs) {
                var sub = subgraphs[v];
                if (sub != null) {
                    foreach (unowned string w in sub.vs) {
                        vs.add (w);
                    }
                } else {
                    vs.add (v);
                }
            }
            entry.vs = vs;
        }
    }

    void merge_barycenters (Entry target, SortResult other) {
        if (target.has_barycenter) {
            target.barycenter = (target.barycenter * target.weight + other.barycenter * other.weight)
                / (target.weight + other.weight);
            target.weight += other.weight;
        } else {
            target.barycenter = other.barycenter;
            target.weight = other.weight;
            target.has_barycenter = true;
        }
    }

    /*
     * Coalesces entries whose barycenters would violate the constraint graph,
     * after Forster, "A Fast and Simple Heuristic for Constrained Two-Level
     * Crossing Reduction".
     */
    GenericArray<ConflictEntry> resolve_conflicts (GenericArray<Entry> entries, Graph cg) {
        var mapped = new HashTable<string, ConflictEntry> (str_hash, str_equal);
        var ordered = new GenericArray<ConflictEntry> ();
        for (int i = 0; i < entries.length; i++) {
            var entry = entries[i];
            var tmp = new ConflictEntry ();
            tmp.vs.add (entry.v);
            tmp.i = i;
            if (entry.has_barycenter) {
                tmp.has_barycenter = true;
                tmp.barycenter = entry.barycenter;
                tmp.weight = entry.weight;
            }
            mapped.insert (entry.v, tmp);
            ordered.add (tmp);
        }

        foreach (var e in cg.edges ()) {
            var entry_v = mapped[e.v];
            var entry_w = mapped[e.w];
            if (entry_v != null && entry_w != null) {
                entry_w.indegree++;
                entry_v.out_.add (entry_w);
            }
        }

        var source_set = new GenericArray<ConflictEntry> ();
        foreach (var entry in ordered) {
            if (entry.indegree == 0) {
                source_set.add (entry);
            }
        }
        var result = do_resolve_conflicts (source_set);
        // Break the reference cycles between the entries.
        foreach (var entry in ordered) {
            entry.in_ = new GenericArray<ConflictEntry> ();
            entry.out_ = new GenericArray<ConflictEntry> ();
        }
        return result;
    }

    GenericArray<ConflictEntry> do_resolve_conflicts (GenericArray<ConflictEntry> source_set) {
        var entries = new GenericArray<ConflictEntry> ();

        while (source_set.length > 0) {
            var entry = source_set[source_set.length - 1];
            source_set.remove_index (source_set.length - 1);
            entries.add (entry);

            for (int k = entry.in_.length - 1; k >= 0; k--) {
                var u_entry = entry.in_[k];
                if (u_entry.merged) {
                    continue;
                }
                if (!u_entry.has_barycenter || !entry.has_barycenter || u_entry.barycenter >= entry.barycenter) {
                    merge_entries (entry, u_entry);
                }
            }
            foreach (var w_entry in entry.out_) {
                w_entry.in_.add (entry);
                if (--w_entry.indegree == 0) {
                    source_set.add (w_entry);
                }
            }
        }

        var result = new GenericArray<ConflictEntry> ();
        foreach (var entry in entries) {
            if (!entry.merged) {
                result.add (entry);
            }
        }
        return result;
    }

    void merge_entries (ConflictEntry target, ConflictEntry source) {
        double sum = 0;
        double weight = 0;
        if (target.weight != 0) {
            sum += target.barycenter * target.weight;
            weight += target.weight;
        }
        if (source.weight != 0) {
            sum += source.barycenter * source.weight;
            weight += source.weight;
        }
        var vs = new GenericArray<string> ();
        foreach (unowned string v in source.vs) {
            vs.add (v);
        }
        foreach (unowned string v in target.vs) {
            vs.add (v);
        }
        target.vs = vs;
        target.barycenter = sum / weight;
        target.has_barycenter = true;
        target.weight = weight;
        target.i = int.min (source.i, target.i);
        source.merged = true;
    }

    SortResult sort (GenericArray<ConflictEntry> entries, bool bias_right) {
        var sortable = new GenericArray<ConflictEntry> ();
        var unsortable = new GenericArray<ConflictEntry> ();
        foreach (var entry in entries) {
            (entry.has_barycenter ? sortable : unsortable).add (entry);
        }
        unsortable.sort_with_data ((a, b) => b.i - a.i);

        sortable.sort_with_data ((a, b) => {
            if (a.barycenter < b.barycenter) {
                return -1;
            } else if (a.barycenter > b.barycenter) {
                return 1;
            }
            return !bias_right ? a.i - b.i : b.i - a.i;
        });

        var vs = new GenericArray<GenericArray<string>> ();
        double sum = 0, weight = 0;
        int vs_index = consume_unsortable (vs, unsortable, 0);

        foreach (var entry in sortable) {
            vs_index += entry.vs.length;
            vs.add (entry.vs);
            sum += entry.barycenter * entry.weight;
            weight += entry.weight;
            vs_index = consume_unsortable (vs, unsortable, vs_index);
        }

        var result = new SortResult ();
        foreach (var part in vs) {
            foreach (unowned string v in part) {
                result.vs.add (v);
            }
        }
        if (weight != 0) {
            result.has_barycenter = true;
            result.barycenter = sum / weight;
            result.weight = weight;
        }
        return result;
    }

    int consume_unsortable (GenericArray<GenericArray<string>> vs, GenericArray<ConflictEntry> unsortable,
                            int index) {
        while (unsortable.length > 0 && unsortable[unsortable.length - 1].i <= index) {
            var last = unsortable[unsortable.length - 1];
            unsortable.remove_index (unsortable.length - 1);
            vs.add (last.vs);
            index++;
        }
        return index;
    }

    void add_subgraph_constraints (Graph g, Graph cg, GenericArray<string> vs) {
        var prev = new HashTable<string, string> (str_hash, str_equal);
        string? root_prev = null;

        foreach (unowned string v in vs) {
            string? child = g.parent (v);
            while (child != null) {
                string? parent = g.parent (child);
                string? prev_child;
                if (parent != null) {
                    prev_child = prev[parent];
                    prev[parent] = child;
                } else {
                    prev_child = root_prev;
                    root_prev = child;
                }
                if (prev_child != null && prev_child != child) {
                    cg.set_edge (prev_child, child);
                    break;
                }
                child = parent;
            }
        }
    }
}
