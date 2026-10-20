/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Shows a Mermaid file in a window, or renders it to a PNG file:
 *
 *   mermaid-demo FILE.mmd
 *   mermaid-demo FILE.mmd --png OUT.png [--dark] [--scale N]
 */

int main (string[] args) {
    if (args.length < 2) {
        stderr.printf ("Usage: %s FILE.mmd [--png OUT.png [--dark] [--scale N]]\n", args[0]);
        return 2;
    }
    string text;
    try {
        FileUtils.get_contents (args[1], out text);
    } catch (FileError e) {
        stderr.printf ("%s\n", e.message);
        return 1;
    }
    string? png = null;
    bool dark = false;
    double scale = 1;
    for (int i = 2; i < args.length; i++) {
        if (args[i] == "--png" && i + 1 < args.length) {
            png = args[++i];
        } else if (args[i] == "--dark") {
            dark = true;
        } else if (args[i] == "--scale" && i + 1 < args.length) {
            scale = double.parse (args[++i]);
        }
    }

    Mermaid.Diagram diagram;
    try {
        diagram = Mermaid.parse (text);
    } catch (Mermaid.ParseError e) {
        stderr.printf ("%s\n", e.message);
        return 1;
    }

    if (png != null) {
        return render_png (diagram, png, dark, scale);
    }

    var app = new Gtk.Application ("io.github.jefersondaniel.MermaidDemo", ApplicationFlags.NON_UNIQUE);
    app.activate.connect (() => {
        var window = new Gtk.ApplicationWindow (app);
        window.title = Path.get_basename (args[1]);
        window.default_width = 900;
        window.default_height = 700;
        var view = new Mermaid.View (diagram);
        view.margin_top = view.margin_bottom = view.margin_start = view.margin_end = 24;
        var scroller = new Gtk.ScrolledWindow ();
        scroller.child = view;
        window.child = scroller;
        window.present ();
    });
    return app.run (new string[] { args[0] });
}

int render_png (Mermaid.Diagram diagram, string path, bool dark, double scale) {
    // Registers the render node types; works without a display too.
    Gtk.init_check ();
    var font_map = Pango.CairoFontMap.get_default ();
    var context = font_map.create_context ();
    context.set_font_description (Pango.FontDescription.from_string ("Adwaita Sans 11"));
    var scene = diagram.layout (new Mermaid.PangoMeasurer (context));

    var fg = Gdk.RGBA ();
    var bg = Gdk.RGBA ();
    var accent = Gdk.RGBA ();
    fg.parse (dark ? "#ffffff" : "#000000cc");
    bg.parse (dark ? "#1e1e1e" : "#ffffff");
    accent.parse (dark ? "#78aeed" : "#3584e4");
    var palette = new Mermaid.Palette (fg, bg, accent);
    var painter = new Mermaid.Painter (new Mermaid.PangoMeasurer (context), palette);

    var snapshot = new Gtk.Snapshot ();
    snapshot.scale ((float) scale, (float) scale);
    painter.paint (snapshot, scene);
    var node = snapshot.free_to_node ();

    int w = (int) Math.ceil (scene.width * scale), h = (int) Math.ceil (scene.height * scale);
    var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, int.max (w, 1), int.max (h, 1));
    var cr = new Cairo.Context (surface);
    cr.set_source_rgb (bg.red, bg.green, bg.blue);
    cr.paint ();
    if (node != null) {
        node.draw (cr);
    }
    surface.write_to_png (path);
    print ("%s: %d×%d\n", path, w, h);
    return 0;
}
