/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Reads a graph in a small text format, lays it out with the dagre port and
 * prints the result. tests/dagre-dump.mjs does the same with the original
 * JavaScript dagre, so the two outputs can be compared.
 *
 *   graph <rankdir> <nodesep> <edgesep> <ranksep> <marginx> <marginy>
 *   node <id> <width> <height> [<parent>]
 *   edge <v> <w> <name|-> <minlen> <weight> <width> <height> <labelpos>
 */

using Mermaid.Dagre;

int main (string[] args) {
    if (args.length < 2) {
        stderr.printf ("Usage: %s GRAPH-FILE\n", args[0]);
        return 2;
    }
    string text;
    try {
        FileUtils.get_contents (args[1], out text);
    } catch (FileError e) {
        stderr.printf ("%s\n", e.message);
        return 1;
    }

    var g = new Graph (true, true, true);
    var parents = new GenericArray<string> ();
    foreach (unowned string line in text.split ("\n")) {
        string[] f = line.strip ().split (" ");
        switch (f[0]) {
        case "graph":
            g.label.rankdir = f[1];
            g.label.nodesep = double.parse (f[2]);
            g.label.edgesep = double.parse (f[3]);
            g.label.ranksep = double.parse (f[4]);
            g.label.marginx = double.parse (f[5]);
            g.label.marginy = double.parse (f[6]);
            break;
        case "node":
            g.set_node (f[1], new NodeLabel.sized (double.parse (f[2]), double.parse (f[3])));
            if (f.length > 4) {
                parents.add (f[1]);
                parents.add (f[4]);
            }
            break;
        case "edge":
            var label = new EdgeLabel ();
            label.minlen = int.parse (f[4]);
            label.weight = double.parse (f[5]);
            label.width = double.parse (f[6]);
            label.height = double.parse (f[7]);
            label.labelpos = f[8];
            g.set_edge (f[1], f[2], label, f[3] == "-" ? null : f[3]);
            break;
        }
    }
    for (int i = 0; i < parents.length; i += 2) {
        if (!g.has_node (parents[i + 1])) {
            g.set_node (parents[i + 1], new NodeLabel ());
        }
        g.set_parent (parents[i], parents[i + 1]);
    }

    layout (g);

    print ("graph %s %s\n", fmt (g.label.width), fmt (g.label.height));
    foreach (unowned string v in g.nodes ()) {
        var n = g.node (v);
        print ("node %s %s %s %s %s\n", v, fmt (n.x), fmt (n.y), fmt (n.width), fmt (n.height));
    }
    foreach (var e in g.edges ()) {
        var l = g.edge_of (e);
        var sb = new StringBuilder ();
        sb.append_printf ("edge %s %s %s", e.v, e.w, e.name ?? "-");
        if (l.has_xy) {
            sb.append_printf (" label %s %s", fmt (l.x), fmt (l.y));
        }
        sb.append (" points");
        foreach (var p in l.points) {
            sb.append_printf (" %s,%s", fmt (p.x), fmt (p.y));
        }
        print ("%s\n", sb.str);
    }
    return 0;
}

string fmt (double d) {
    char[] buf = new char[double.DTOSTR_BUF_SIZE];
    string s = d.format (buf, "%.3f");
    return s == "-0.000" ? "0.000" : s;
}
