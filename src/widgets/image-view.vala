/* Displays a paintable at its natural size, scaled down (never up, unless an
 * explicit width was requested) to fit the available width, keeping the
 * aspect ratio. Gtk.Picture always asks for its full natural width, which is
 * not what a document flow wants. */

public class Notes.ImageView : Gtk.Widget {
    Gdk.Paintable? paintable;
    int requested_width;

    public ImageView (int requested_width = -1) {
        this.requested_width = requested_width;
        halign = Gtk.Align.START;
    }

    public void set_paintable (Gdk.Paintable paintable) {
        this.paintable = paintable;
        queue_resize ();
    }

    double target_width () {
        double iw = paintable.get_intrinsic_width ();
        return requested_width > 0 ? requested_width : iw;
    }

    public override Gtk.SizeRequestMode get_request_mode () {
        return Gtk.SizeRequestMode.HEIGHT_FOR_WIDTH;
    }

    public override void measure (Gtk.Orientation orientation, int for_size,
                                  out int minimum, out int natural,
                                  out int minimum_baseline, out int natural_baseline) {
        minimum = natural = 0;
        minimum_baseline = natural_baseline = -1;
        if (paintable == null) {
            return;
        }
        double iw = paintable.get_intrinsic_width ();
        double ih = paintable.get_intrinsic_height ();
        if (iw <= 0 || ih <= 0) {
            return;
        }
        double w = target_width ();
        if (orientation == Gtk.Orientation.HORIZONTAL) {
            natural = (int) w;
            minimum = int.min (natural, 32);
        } else {
            double width = for_size >= 0 ? double.min (for_size, w) : w;
            minimum = natural = (int) (width * ih / iw + 0.999);
        }
    }

    public override void snapshot (Gtk.Snapshot snapshot) {
        if (paintable == null) {
            return;
        }
        double iw = paintable.get_intrinsic_width ();
        double ih = paintable.get_intrinsic_height ();
        if (iw <= 0 || ih <= 0) {
            return;
        }
        double scale = double.min (get_width () / iw, get_height () / ih);
        float dw = (float) (iw * scale);
        float dh = (float) (ih * scale);

        // Large images get soft corners; small ones (badges, icons) stay crisp.
        bool rounded = dh > 64;
        if (rounded) {
            var bounds = Graphene.Rect ();
            bounds.init (0, 0, dw, dh);
            var clip = Gsk.RoundedRect ();
            clip.init_from_rect (bounds, 10);
            snapshot.push_rounded_clip (clip);
        }
        paintable.snapshot (snapshot, dw, dh);
        if (rounded) {
            snapshot.pop ();
        }
    }
}
