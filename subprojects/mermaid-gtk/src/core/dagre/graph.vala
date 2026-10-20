/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ported from dagre-d3-es 7.0.14, src/graphlib/graph.js.
 * Copyright (c) 2012-2014 Chris Pettitt, (c) 2022-2024 dagre-es contributors. MIT License.
 *
 * JavaScript's graphlib stores arbitrary objects as node and edge labels.
 * Here every graph uses the same label classes, which carry the fields that
 * any stage of the layout reads or writes.
 */

namespace Mermaid.Dagre {

    internal struct Point {
        public double x;
        public double y;
    }

    /* Identifies an edge: tail, head and, in multigraphs, a name. */
    internal class EdgeKey {
        public string v;
        public string w;
        public string? name;

        public EdgeKey (string v, string w, string? name = null) {
            this.v = v;
            this.w = w;
            this.name = name;
        }
    }

    internal class SelfEdge {
        public EdgeKey e;
        public EdgeLabel label;
    }

    internal class NodeLabel {
        public double width;
        public double height;
        public double x;
        public double y;

        public int rank;
        public bool has_rank;
        public int order;

        /* "edge", "edge-label", "edge-proxy", "border", "root" or "selfedge". */
        public string? dummy;

        // Subgraphs.
        public string? border_top;
        public string? border_bottom;
        public HashTable<int, string>? border_left;
        public HashTable<int, string>? border_right;
        public int min_rank;
        public int max_rank;
        public bool has_min_rank;
        /* "borderLeft" or "borderRight" for border segment nodes. */
        public string? border_type;
        /*
         * Not in dagre: room for a subgraph's title on its top side. The
         * border nodes on that side get this size, so the title gets its own
         * band instead of overlapping the subgraph's nodes.
         */
        public double title_height;

        // Self edges, removed during ordering and put back afterwards.
        public GenericArray<SelfEdge>? self_edges;
        public EdgeKey? e;
        public EdgeLabel? label;

        // Dummy nodes of long edges.
        public EdgeLabel? edge_label;
        public EdgeKey? edge_obj;
        public string? labelpos;

        // Spanning tree of the network simplex ranker.
        public int low;
        public int lim;
        public string? parent;

        // Layer graphs: the border nodes of a subgraph on this rank.
        public string? layer_border_left;
        public string? layer_border_right;

        // Greedy feedback arc set.
        public string fas_v;
        public double fas_in;
        public double fas_out;
        public NodeLabel? list_next;
        public weak NodeLabel? list_prev;

        public NodeLabel () {
        }

        public NodeLabel.sized (double width, double height) {
            this.width = width;
            this.height = height;
        }

        public string last_border (bool left) {
            return (left ? border_left : border_right).lookup (max_rank);
        }
    }

    internal class EdgeLabel {
        public int minlen = 1;
        public double weight = 1;
        public double width;
        public double height;
        public double labeloffset = 10;
        public string labelpos = "r";

        public GenericArray<Point?>? points;
        public double x;
        public double y;
        public bool has_xy;

        public bool reversed;
        public string? forward_name;
        public int label_rank;
        public bool has_label_rank;
        public bool nesting_edge;
        public double cutvalue;
    }

    internal class GraphLabel {
        public string rankdir = "tb";
        public double nodesep = 50;
        public double edgesep = 20;
        public double ranksep = 50;
        public double marginx;
        public double marginy;
        public string? acyclicer;
        public string? ranker;
        public string? align;

        public double width;
        public double height;

        public string? nesting_root;
        public int node_rank_factor;
        public GenericArray<string>? dummy_chains;
        public int max_rank;

        /* Layer graphs: the root node that holds the movable nodes. */
        public string? root;
    }

    internal delegate NodeLabel? DefaultNodeLabel (string v);

    /* Number of edges between two nodes (Vala generics can't hold an int). */
    internal class Count {
        public int n;
    }

    internal class Graph {
        const string ROOT = "\x01";
        const string DEFAULT_EDGE_NAME = "\x02";
        const string DELIM = "\x03";

        public bool directed { get; private set; }
        public bool multigraph { get; private set; }
        public bool compound { get; private set; }

        public GraphLabel label = new GraphLabel ();
        DefaultNodeLabel? default_node_label;

        Dict<NodeLabel?> nodes_ = new Dict<NodeLabel?> ();
        Dict<string>? parent_;
        Dict<Dict<string>>? children_;
        Dict<Dict<EdgeKey>> in_ = new Dict<Dict<EdgeKey>> ();
        Dict<Dict<EdgeKey>> out_ = new Dict<Dict<EdgeKey>> ();
        Dict<Dict<Count>> preds = new Dict<Dict<Count>> ();
        Dict<Dict<Count>> sucs = new Dict<Dict<Count>> ();
        Dict<EdgeKey> edge_objs = new Dict<EdgeKey> ();
        Dict<EdgeLabel?> edge_labels = new Dict<EdgeLabel?> ();

        public Graph (bool directed = true, bool multigraph = false, bool compound = false) {
            this.directed = directed;
            this.multigraph = multigraph;
            this.compound = compound;
            if (compound) {
                parent_ = new Dict<string> ();
                children_ = new Dict<Dict<string>> ();
                children_[ROOT] = new Dict<string> ();
            }
        }

        public void set_default_node_label (owned DefaultNodeLabel fn) {
            default_node_label = (owned) fn;
        }

        // Nodes.

        public int node_count () {
            return (int) nodes_.size;
        }

        public string[] nodes () {
            return nodes_.keys ();
        }

        public string[] sources () {
            string[] result = {};
            foreach (unowned string v in nodes_.keys ()) {
                if (in_[v].is_empty ()) {
                    result += v;
                }
            }
            return result;
        }

        public bool has_node (string v) {
            return nodes_.has (v);
        }

        public new NodeLabel? node (string v) {
            return nodes_[v];
        }

        /*
         * Adds v if it is missing, with `value` or the default label. Replaces
         * the label of an existing node when one is given, or when `replace`
         * is set (to store null).
         */
        public void set_node (string v, NodeLabel? value = null, bool replace = false) {
            if (nodes_.has (v)) {
                if (value != null || replace) {
                    nodes_[v] = value;
                }
                return;
            }
            NodeLabel? label = value;
            if (!replace && label == null && default_node_label != null) {
                label = default_node_label (v);
            }
            nodes_[v] = label;
            if (compound) {
                parent_[v] = ROOT;
                children_[v] = new Dict<string> ();
                children_[ROOT][v] = v;
            }
            in_[v] = new Dict<EdgeKey> ();
            preds[v] = new Dict<Count> ();
            out_[v] = new Dict<EdgeKey> ();
            sucs[v] = new Dict<Count> ();
        }

        public void remove_node (string v) {
            if (!nodes_.has (v)) {
                return;
            }
            nodes_.remove (v);
            if (compound) {
                children_[parent_[v]].remove (v);
                parent_.remove (v);
                foreach (unowned string child in children (v)) {
                    set_parent (child, null);
                }
                children_.remove (v);
            }
            foreach (unowned string e in in_[v].keys ()) {
                remove_edge_key (edge_objs[e]);
            }
            in_.remove (v);
            preds.remove (v);
            foreach (unowned string e in out_[v].keys ()) {
                remove_edge_key (edge_objs[e]);
            }
            out_.remove (v);
            sucs.remove (v);
        }

        public void set_parent (string v, string? parent) {
            assert (compound);
            string p = ROOT;
            if (parent != null) {
                for (string? ancestor = parent; ancestor != null; ancestor = this.parent (ancestor)) {
                    if (ancestor == v) {
                        error ("Setting %s as parent of %s would create a cycle", parent, v);
                    }
                }
                set_node (parent);
                p = parent;
            }
            set_node (v);
            children_[parent_[v]].remove (v);
            parent_[v] = p;
            children_[p][v] = v;
        }

        public string? parent (string v) {
            if (compound) {
                string? p = parent_[v];
                if (p != null && p != ROOT) {
                    return p;
                }
            }
            return null;
        }

        /* Children of v, or the top-level nodes when v is null. */
        public string[] children (string? v = null) {
            string key = v ?? ROOT;
            if (compound) {
                var c = children_[key];
                return c != null ? c.keys () : new string[0];
            }
            if (v == null) {
                return nodes ();
            }
            return new string[0];
        }

        public bool has_children (string v) {
            if (!compound) {
                return false;
            }
            var c = children_[v];
            return c != null && !c.is_empty ();
        }

        public string[] predecessors (string v) {
            var p = preds[v];
            return p != null ? p.keys () : new string[0];
        }

        public string[] successors (string v) {
            var s = sucs[v];
            return s != null ? s.keys () : new string[0];
        }

        public string[] neighbors (string v) {
            string[] result = predecessors (v);
            var seen = new HashTable<string, bool> (str_hash, str_equal);
            foreach (unowned string p in result) {
                seen.insert (p, true);
            }
            foreach (unowned string s in successors (v)) {
                if (!seen.contains (s)) {
                    seen.insert (s, true);
                    result += s;
                }
            }
            return result;
        }

        // Edges.

        public GenericArray<EdgeKey> edges () {
            return edge_objs.values ();
        }

        string edge_id (string v, string w, string? name) {
            string a = v, b = w;
            if (!directed && strcmp (a, b) > 0) {
                a = w;
                b = v;
            }
            return a + DELIM + b + DELIM + (name ?? DEFAULT_EDGE_NAME);
        }

        /* Adds or updates the edge. Without a label, keeps the existing one. */
        public void set_edge (string v, string w, EdgeLabel? value = null, string? name = null) {
            string e = edge_id (v, w, name);
            if (edge_labels.has (e)) {
                if (value != null) {
                    edge_labels[e] = value;
                }
                return;
            }
            if (name != null && !multigraph) {
                error ("Cannot set a named edge when isMultigraph = false");
            }
            set_node (v);
            set_node (w);
            edge_labels[e] = value ?? new EdgeLabel ();

            string a = v, b = w;
            if (!directed && strcmp (a, b) > 0) {
                a = w;
                b = v;
            }
            var key = new EdgeKey (a, b, name);
            edge_objs[e] = key;
            increment (preds[b], a);
            increment (sucs[a], b);
            in_[b][e] = key;
            out_[a][e] = key;
        }

        public void set_edge_key (EdgeKey e, EdgeLabel? value = null) {
            set_edge (e.v, e.w, value, e.name);
        }

        public EdgeLabel? edge (string v, string w, string? name = null) {
            return edge_labels[edge_id (v, w, name)];
        }

        public EdgeLabel? edge_of (EdgeKey e) {
            return edge_labels[edge_id (e.v, e.w, e.name)];
        }

        public bool has_edge (string v, string w, string? name = null) {
            return edge_labels.has (edge_id (v, w, name));
        }

        public void remove_edge (string v, string w, string? name = null) {
            string e = edge_id (v, w, name);
            var key = edge_objs[e];
            if (key == null) {
                return;
            }
            edge_labels.remove (e);
            edge_objs.remove (e);
            decrement (preds[key.w], key.v);
            decrement (sucs[key.v], key.w);
            in_[key.w].remove (e);
            out_[key.v].remove (e);
        }

        public void remove_edge_key (EdgeKey e) {
            remove_edge (e.v, e.w, e.name);
        }

        public GenericArray<EdgeKey> in_edges (string v, string? u = null) {
            var result = new GenericArray<EdgeKey> ();
            var in_v = in_[v];
            if (in_v != null) {
                foreach (var e in in_v.values ()) {
                    if (u == null || e.v == u) {
                        result.add (e);
                    }
                }
            }
            return result;
        }

        public GenericArray<EdgeKey> out_edges (string v, string? w = null) {
            var result = new GenericArray<EdgeKey> ();
            var out_v = out_[v];
            if (out_v != null) {
                foreach (var e in out_v.values ()) {
                    if (w == null || e.w == w) {
                        result.add (e);
                    }
                }
            }
            return result;
        }

        public GenericArray<EdgeKey> node_edges (string v, string? w = null) {
            var result = in_edges (v, w);
            foreach (var e in out_edges (v, w)) {
                result.add (e);
            }
            return result;
        }

        static void increment (Dict<Count> map, string k) {
            var c = map[k];
            if (c == null) {
                c = new Count ();
                map[k] = c;
            }
            c.n++;
        }

        static void decrement (Dict<Count> map, string k) {
            var c = map[k];
            if (--c.n <= 0) {
                map.remove (k);
            }
        }
    }
}
