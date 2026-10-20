/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ported from dagre-d3-es 7.0.14, src/dagre/acyclic.js, greedy-fas.js and data/list.js.
 * Copyright (c) 2012-2014 Chris Pettitt, (c) 2022-2024 dagre-es contributors. MIT License.
 */

namespace Mermaid.Dagre.Acyclic {

    /* Reverses a set of edges so that the graph has no cycles. */
    internal void run (Graph g) {
        var fas = g.label.acyclicer == "greedy" ? greedy_fas (g) : dfs_fas (g);
        foreach (var e in fas) {
            var label = g.edge_of (e);
            g.remove_edge_key (e);
            label.forward_name = e.name;
            label.reversed = true;
            g.set_edge (e.w, e.v, label, Util.unique_id ("rev"));
        }
    }

    GenericArray<EdgeKey> dfs_fas (Graph g) {
        var fas = new GenericArray<EdgeKey> ();
        var stack = new HashTable<string, bool> (str_hash, str_equal);
        var visited = new HashTable<string, bool> (str_hash, str_equal);
        foreach (unowned string v in g.nodes ()) {
            dfs_visit (g, v, fas, stack, visited);
        }
        return fas;
    }

    void dfs_visit (Graph g, string v, GenericArray<EdgeKey> fas,
                    HashTable<string, bool> stack, HashTable<string, bool> visited) {
        if (visited.contains (v)) {
            return;
        }
        visited.insert (v, true);
        stack.insert (v, true);
        foreach (var e in g.out_edges (v)) {
            if (stack.contains (e.w)) {
                fas.add (e);
            } else {
                dfs_visit (g, e.w, fas, stack, visited);
            }
        }
        stack.remove (v);
    }

    internal void undo (Graph g) {
        foreach (var e in g.edges ()) {
            var label = g.edge_of (e);
            if (label.reversed) {
                g.remove_edge_key (e);
                string? forward_name = label.forward_name;
                label.reversed = false;
                label.forward_name = null;
                g.set_edge (e.w, e.v, label, forward_name);
            }
        }
    }

    // Greedy feedback arc set: P. Eades, X. Lin and W. F. Smyth, "A fast and
    // effective heuristic for the feedback arc set problem", with weights.

    /* A doubly linked list of node entries, from Cormen et al. */
    class List {
        NodeLabel sentinel = new NodeLabel ();

        public List () {
            sentinel.list_next = sentinel;
            sentinel.list_prev = sentinel;
        }

        public NodeLabel? dequeue () {
            NodeLabel entry = sentinel.list_prev;
            if (entry != sentinel) {
                unlink (entry);
                return entry;
            }
            return null;
        }

        public void enqueue (NodeLabel entry) {
            if (entry.list_prev != null && entry.list_next != null) {
                unlink (entry);
            }
            entry.list_next = sentinel.list_next;
            sentinel.list_next.list_prev = entry;
            sentinel.list_next = entry;
            entry.list_prev = sentinel;
        }

        static void unlink (NodeLabel entry) {
            entry.list_prev.list_next = entry.list_next;
            entry.list_next.list_prev = entry.list_prev;
            entry.list_next = null;
            entry.list_prev = null;
        }

        public void clear () {
            // Break the reference cycle through the sentinel.
            sentinel.list_next = null;
        }
    }

    GenericArray<EdgeKey> greedy_fas (Graph g) {
        var result = new GenericArray<EdgeKey> ();
        if (g.node_count () <= 1) {
            return result;
        }

        var fas_graph = new Graph ();
        double max_in = 0, max_out = 0;
        foreach (unowned string v in g.nodes ()) {
            var entry = new NodeLabel ();
            entry.fas_v = v;
            fas_graph.set_node (v, entry);
        }
        // Sum the weights across multi-edges into a single edge.
        foreach (var e in g.edges ()) {
            var prev = fas_graph.edge (e.v, e.w);
            double weight = g.edge_of (e).weight;
            var label = new EdgeLabel ();
            label.weight = (prev != null ? prev.weight : 0) + weight;
            fas_graph.set_edge (e.v, e.w, label);
            max_out = double.max (max_out, fas_graph.node (e.v).fas_out += weight);
            max_in = double.max (max_in, fas_graph.node (e.w).fas_in += weight);
        }

        var buckets = new GenericArray<List> ();
        int count = (int) (max_out + max_in + 3);
        for (int i = 0; i < count; i++) {
            buckets.add (new List ());
        }
        int zero_idx = (int) max_in + 1;
        foreach (unowned string v in fas_graph.nodes ()) {
            assign_bucket (buckets, zero_idx, fas_graph.node (v));
        }

        var sources = buckets[buckets.length - 1];
        var sinks = buckets[0];
        var removed = new GenericArray<EdgeKey> ();
        NodeLabel? entry;
        while (fas_graph.node_count () > 0) {
            while ((entry = sinks.dequeue ()) != null) {
                remove_node (fas_graph, buckets, zero_idx, entry, null);
            }
            while ((entry = sources.dequeue ()) != null) {
                remove_node (fas_graph, buckets, zero_idx, entry, null);
            }
            if (fas_graph.node_count () > 0) {
                for (int i = buckets.length - 2; i > 0; --i) {
                    entry = buckets[i].dequeue ();
                    if (entry != null) {
                        remove_node (fas_graph, buckets, zero_idx, entry, removed);
                        break;
                    }
                }
            }
        }
        foreach (var list in buckets) {
            list.clear ();
        }

        // Expand multi-edges.
        foreach (var e in removed) {
            foreach (var edge in g.out_edges (e.v, e.w)) {
                result.add (edge);
            }
        }
        return result;
    }

    void remove_node (Graph g, GenericArray<List> buckets, int zero_idx, NodeLabel entry,
                      GenericArray<EdgeKey>? results) {
        foreach (var edge in g.in_edges (entry.fas_v)) {
            double weight = g.edge_of (edge).weight;
            var u_entry = g.node (edge.v);
            if (results != null) {
                results.add (new EdgeKey (edge.v, edge.w));
            }
            u_entry.fas_out -= weight;
            assign_bucket (buckets, zero_idx, u_entry);
        }
        foreach (var edge in g.out_edges (entry.fas_v)) {
            double weight = g.edge_of (edge).weight;
            var w_entry = g.node (edge.w);
            w_entry.fas_in -= weight;
            assign_bucket (buckets, zero_idx, w_entry);
        }
        g.remove_node (entry.fas_v);
    }

    void assign_bucket (GenericArray<List> buckets, int zero_idx, NodeLabel entry) {
        if (entry.fas_out == 0) {
            buckets[0].enqueue (entry);
        } else if (entry.fas_in == 0) {
            buckets[buckets.length - 1].enqueue (entry);
        } else {
            buckets[(int) (entry.fas_out - entry.fas_in) + zero_idx].enqueue (entry);
        }
    }
}
