/* Lays children out left to right, wrapping onto new lines like words in a
 * paragraph. Used for rows of images and badges. (Adw.WrapBox does this from
 * libadwaita 1.7 on.) */

public class Notes.WrapBox : Gtk.Widget {
    public int spacing { get; set; default = 6; }
    public Gtk.Align line_align { get; set; default = Gtk.Align.START; }

    public void append (Gtk.Widget child) {
        child.set_parent (this);
        queue_resize ();
    }

    public override void dispose () {
        Gtk.Widget? child;
        while ((child = get_first_child ()) != null) {
            child.unparent ();
        }
        base.dispose ();
    }

    public override Gtk.SizeRequestMode get_request_mode () {
        return Gtk.SizeRequestMode.HEIGHT_FOR_WIDTH;
    }

    public override void measure (Gtk.Orientation orientation, int for_size,
                                  out int minimum, out int natural,
                                  out int minimum_baseline, out int natural_baseline) {
        minimum_baseline = natural_baseline = -1;
        if (orientation == Gtk.Orientation.HORIZONTAL) {
            minimum = natural = 0;
            int count = 0;
            for (var child = get_first_child (); child != null; child = child.get_next_sibling ()) {
                if (!child.should_layout ()) {
                    continue;
                }
                int cmin, cnat, b1, b2;
                child.measure (Gtk.Orientation.HORIZONTAL, -1, out cmin, out cnat, out b1, out b2);
                minimum = int.max (minimum, cmin);
                natural += cnat;
                count++;
            }
            natural += spacing * int.max (0, count - 1);
        } else {
            minimum = natural = layout (for_size < 0 ? int.MAX : for_size, false);
        }
    }

    public override void size_allocate (int width, int height, int baseline) {
        layout (width, true);
    }

    /* Returns the total height needed for `width`; positions children when `apply`. */
    int layout (int width, bool apply) {
        var line = new GenericArray<Gtk.Widget> ();
        int[] xs = {}, ws = {}, hs = {};
        int x = 0, y = 0, line_height = 0;

        for (var child = get_first_child (); child != null; child = child.get_next_sibling ()) {
            if (!child.should_layout ()) {
                continue;
            }
            int cmin, cnat, b1, b2;
            child.measure (Gtk.Orientation.HORIZONTAL, -1, out cmin, out cnat, out b1, out b2);
            int w = int.max (cmin, int.min (cnat, width));
            int hmin, hnat;
            child.measure (Gtk.Orientation.VERTICAL, w, out hmin, out hnat, out b1, out b2);

            if (x > 0 && x + w > width) {
                if (apply) {
                    place_line (line, xs, ws, hs, x - spacing, width, y, line_height);
                }
                line = new GenericArray<Gtk.Widget> ();
                xs = {};
                ws = {};
                hs = {};
                y += line_height + spacing;
                x = 0;
                line_height = 0;
            }
            line.add (child);
            xs += x;
            ws += w;
            hs += hnat;
            x += w + spacing;
            line_height = int.max (line_height, hnat);
        }
        if (apply && line.length > 0) {
            place_line (line, xs, ws, hs, x - spacing, width, y, line_height);
        }
        return line.length > 0 ? y + line_height : 0;
    }

    void place_line (GenericArray<Gtk.Widget> line, int[] xs, int[] ws, int[] hs,
                     int line_width, int width, int y, int line_height) {
        int offset = 0;
        if (line_align == Gtk.Align.CENTER) {
            offset = (width - line_width) / 2;
        } else if (line_align == Gtk.Align.END) {
            offset = width - line_width;
        }
        for (int k = 0; k < line.length; k++) {
            var point = Graphene.Point () { x = offset + xs[k], y = y + (line_height - hs[k]) / 2 };
            line[k].allocate (ws[k], hs[k], -1, new Gsk.Transform ().translate (point));
        }
    }
}
