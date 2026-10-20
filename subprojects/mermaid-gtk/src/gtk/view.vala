/* SPDX-License-Identifier: GPL-3.0-or-later */

namespace Mermaid {

    /*
     * Shows a diagram. It is drawn at the widget's font size and shrinks to
     * fit the width it gets, like an image, down to min_scale.
     */
    public class View : Gtk.Widget {
        Diagram _diagram;
        Scene? scene;
        double scene_font_px;
        Gdk.RGBA? _accent;
        int allocated_width = -1;

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

        /*
         * How far the diagram may shrink to fit, as a fraction of its size:
         * 0 lets it shrink freely, 1 keeps it at full size. Its minimum width
         * follows, so put the view in a Gtk.ScrolledWindow to scroll wide
         * diagrams rather than shrink their text past reading.
         */
        public double min_scale { get; set; default = 0; }

        static construct {
            set_css_name ("mermaid-diagram");
            set_accessible_role (Gtk.AccessibleRole.IMG);
        }

        public View (Diagram diagram) {
            Object (diagram: diagram);
        }

        construct {
            overflow = Gtk.Overflow.HIDDEN;
            notify["min-scale"].connect (queue_resize);
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
                minimum = (int) Math.ceil (double.min (w, double.max (48, w * min_scale)));
                natural = (int) Math.ceil (w);
            } else {
                // A Gtk.ScrolledWindow that scrolls sideways asks for the
                // height without a width; the last allocated width is the best guess.
                int width = for_size >= 0 ? for_size : allocated_width;
                double fit = width >= 0 ? fit_scale (w, width) : 1;
                minimum = natural = (int) Math.ceil (h * fit);
            }
        }

        public override void size_allocate (int width, int height, int baseline) {
            if (width != allocated_width) {
                allocated_width = width;
                Idle.add (() => {
                    queue_resize ();
                    return GLib.Source.REMOVE;
                });
            }
        }

        /* The scale that fits a diagram this wide into the width, at most 1. */
        double fit_scale (double w, double width) {
            return w > 0 ? double.max (double.min (1, width / w), double.min (min_scale, 1)) : 1;
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            var s = ensure_scene ();
            double k = scale ();
            double w = s.width * k;
            double fit = fit_scale (w, get_width ());
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
