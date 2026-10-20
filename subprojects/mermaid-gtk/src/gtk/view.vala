/* SPDX-License-Identifier: GPL-3.0-or-later */

namespace Mermaid {

    /*
     * Shows a diagram. It is drawn at the widget's font size and shrinks to
     * fit the width it gets, like an image.
     */
    public class View : Gtk.Widget {
        Diagram _diagram;
        Scene? scene;
        double scene_font_px;
        Gdk.RGBA? _accent;

        public Diagram diagram {
            get { return _diagram; }
            set {
                _diagram = value;
                scene = null;
                queue_resize ();
            }
        }

        /* The accent color for nodes. Without one, GNOME's blue is used. */
        public Gdk.RGBA? accent {
            get { return _accent; }
            set {
                _accent = value;
                queue_draw ();
            }
        }

        static construct {
            set_css_name ("mermaid-diagram");
            set_accessible_role (Gtk.AccessibleRole.IMG);
        }

        public View (Diagram diagram) {
            Object (diagram: diagram);
        }

        construct {
            overflow = Gtk.Overflow.HIDDEN;
        }

        /* The font size in pixels that the scene is drawn at. */
        double font_px () {
            var desc = get_pango_context ().get_font_description ();
            double size = (double) desc.get_size () / Pango.SCALE;
            if (!desc.get_size_is_absolute ()) {
                size = size * 96.0 / 72.0;
            }
            return size > 0 ? size : 14.6;
        }

        double scale () {
            return font_px () / FONT_SIZE;
        }

        Scene ensure_scene () {
            double px = font_px ();
            if (scene == null || px != scene_font_px) {
                scene_font_px = px;
                // The layout is kept with the diagram, so a view made again
                // for the same diagram doesn't lay it out again.
                string font = get_pango_context ().get_font_description ().to_string ();
                scene = _diagram.layout_cached (new PangoMeasurer (get_pango_context ()), font);
                update_accessible_description ();
            }
            return scene;
        }

        void update_accessible_description () {
            string? label = _diagram.accessible_title ?? _diagram.title;
            update_property (Gtk.AccessibleProperty.LABEL,
                             label ?? "%s diagram".printf (_diagram.kind));
            if (_diagram.accessible_description != null) {
                update_property (Gtk.AccessibleProperty.DESCRIPTION, _diagram.accessible_description);
            }
        }

        public override void css_changed (Gtk.CssStyleChange change) {
            base.css_changed (change);
            queue_resize ();
        }

        public override Gtk.SizeRequestMode get_request_mode () {
            return Gtk.SizeRequestMode.HEIGHT_FOR_WIDTH;
        }

        public override void measure (Gtk.Orientation orientation, int for_size,
                                      out int minimum, out int natural,
                                      out int minimum_baseline, out int natural_baseline) {
            var s = ensure_scene ();
            double k = scale ();
            double w = s.width * k, h = s.height * k;
            minimum_baseline = natural_baseline = -1;
            if (orientation == Gtk.Orientation.HORIZONTAL) {
                minimum = (int) Math.ceil (double.min (w, 48));
                natural = (int) Math.ceil (w);
            } else {
                double fit = for_size >= 0 && w > 0 ? double.min (1, for_size / w) : 1;
                minimum = natural = (int) Math.ceil (h * fit);
            }
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            var s = ensure_scene ();
            double k = scale ();
            double w = s.width * k;
            double fit = w > 0 ? double.min (1, get_width () / w) : 1;
            double total = k * fit;
            double x = (get_width () - s.width * total) / 2;
            var palette = new Palette.for_widget (this, _accent);
            var painter = new Painter (new PangoMeasurer (get_pango_context ()), palette);
            snapshot.save ();
            snapshot.translate (Graphene.Point () { x = (float) x, y = 0 });
            snapshot.scale ((float) total, (float) total);
            painter.paint (snapshot, s);
            snapshot.restore ();
        }
    }
}
