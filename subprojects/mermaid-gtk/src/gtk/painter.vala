/* SPDX-License-Identifier: GPL-3.0-or-later */

namespace Mermaid {

    /* Measures text with Pango, in the font the painter uses. */
    public class PangoMeasurer : Object, TextMeasurer {
        Pango.Context context;
        Pango.FontDescription base_font;

        public PangoMeasurer (Pango.Context context) {
            this.context = context;
            base_font = context.get_font_description ().copy ();
        }

        internal Pango.Layout layout_for (string markup, TextStyle style, double wrap_width, Align align) {
            var layout = new Pango.Layout (context);
            var font = base_font.copy ();
            font.set_absolute_size (style.size * Pango.SCALE);
            if (style.bold) {
                font.set_weight (Pango.Weight.BOLD);
            }
            if (style.italic) {
                font.set_style (Pango.Style.ITALIC);
            }
            if (style.monospace) {
                font.set_family ("monospace");
            }
            layout.set_font_description (font);
            layout.set_markup (markup, -1);
            switch (align) {
            case Align.START:
                layout.set_alignment (Pango.Alignment.LEFT);
                break;
            case Align.END:
                layout.set_alignment (Pango.Alignment.RIGHT);
                break;
            default:
                layout.set_alignment (Pango.Alignment.CENTER);
                break;
            }
            if (wrap_width > 0) {
                layout.set_width ((int) (wrap_width * Pango.SCALE));
                layout.set_wrap (Pango.WrapMode.WORD_CHAR);
            }
            return layout;
        }

        public void measure (string markup, TextStyle style, double wrap_width,
                             out double width, out double height) {
            var layout = layout_for (markup, style, wrap_width, Align.CENTER);
            Pango.Rectangle logical;
            layout.get_extents (null, out logical);
            width = (double) logical.width / Pango.SCALE;
            height = (double) logical.height / Pango.SCALE;
        }
    }

    /* The colors of each Ink, for the light or dark style. */
    public class Palette : Object {
        public Gdk.RGBA foreground;
        public Gdk.RGBA background;
        public Gdk.RGBA accent;
        public bool dark;

        // The GNOME palette: light shades for light styles, darker ones for dark styles.
        const string[] LIGHT_SERIES = {
            "#99c1f1", "#8ff0a4", "#f9f06b", "#ffbe6f", "#f66151", "#dc8add", "#cdab8f",
            "#93ddc2", "#f4b8e4", "#c0bfbc", "#62a0ea", "#57e389"
        };
        const string[] DARK_SERIES = {
            "#1c71d8", "#26a269", "#c88800", "#c64600", "#a51d2d", "#813d9c", "#865e3c",
            "#0e7c86", "#a1407f", "#5e5c64", "#1a5fb4", "#2ec27e"
        };

        public Palette (Gdk.RGBA foreground, Gdk.RGBA background, Gdk.RGBA accent) {
            this.foreground = foreground;
            this.background = background;
            this.accent = accent;
            dark = luminance (background) < 0.5;
        }

        /* Colors for a widget: its text color, and the accent color given. */
        public Palette.for_widget (Gtk.Widget widget, Gdk.RGBA? accent = null) {
            var fg = widget.get_color ();
            bool is_dark = luminance (fg) > 0.5;
            var bg = Gdk.RGBA ();
            bg.parse (is_dark ? "#1e1e1e" : "#ffffff");
            var a = Gdk.RGBA ();
            if (accent != null) {
                a = accent;
            } else {
                a.parse (is_dark ? "#78aeed" : "#3584e4");
            }
            this (fg, bg, a);
        }

        static double luminance (Gdk.RGBA c) {
            return 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue;
        }

        static Gdk.RGBA mix (Gdk.RGBA a, Gdk.RGBA b, double t) {
            var c = Gdk.RGBA ();
            c.red = (float) (a.red * (1 - t) + b.red * t);
            c.green = (float) (a.green * (1 - t) + b.green * t);
            c.blue = (float) (a.blue * (1 - t) + b.blue * t);
            c.alpha = 1;
            return c;
        }

        static Gdk.RGBA rgba (string spec) {
            var c = Gdk.RGBA ();
            c.parse (spec);
            return c;
        }

        static Gdk.RGBA with_alpha (Gdk.RGBA c, double alpha) {
            var r = c;
            r.alpha = (float) (c.alpha * alpha);
            return r;
        }

        public Gdk.RGBA color (Paint paint) {
            switch (paint.ink) {
            case Ink.BACKGROUND:
                return background;
            case Ink.TEXT:
            case Ink.SOLID:
                return foreground;
            case Ink.LINE:
                return mix (background, foreground, 0.75);
            case Ink.NODE_FILL:
                return mix (background, accent, dark ? 0.22 : 0.12);
            case Ink.NODE_STROKE:
                return accent;
            case Ink.GROUP_FILL:
                return mix (background, foreground, dark ? 0.06 : 0.035);
            case Ink.GROUP_STROKE:
                return mix (background, foreground, 0.35);
            case Ink.NOTE_FILL:
                return dark ? rgba ("#4b4320") : rgba ("#fff5c2");
            case Ink.NOTE_STROKE:
                return dark ? rgba ("#c9a227") : rgba ("#d5a700");
            case Ink.ACCENT_FILL:
                return mix (background, accent, dark ? 0.4 : 0.25);
            case Ink.PALETTE:
                unowned string[] series = dark ? DARK_SERIES : LIGHT_SERIES;
                return rgba (series[paint.index % series.length]);
            case Ink.CUSTOM:
                var c = Gdk.RGBA ();
                c.red = ((paint.rgba >> 24) & 0xff) / 255f;
                c.green = ((paint.rgba >> 16) & 0xff) / 255f;
                c.blue = ((paint.rgba >> 8) & 0xff) / 255f;
                c.alpha = (paint.rgba & 0xff) / 255f;
                return c;
            default:
                return with_alpha (foreground, 0);
            }
        }
    }

    /* Paints a scene into a snapshot, in scene coordinates. */
    public class Painter : Object {
        PangoMeasurer text;
        Palette palette;

        public Painter (PangoMeasurer text, Palette palette) {
            this.text = text;
            this.palette = palette;
        }

        public void paint (Gtk.Snapshot snapshot, Scene scene) {
            foreach (var item in scene.items) {
                if (item is Shape) {
                    paint_shape (snapshot, (Shape) item);
                } else if (item is Text) {
                    paint_text (snapshot, (Text) item);
                }
            }
        }

        static Gsk.Path? to_gsk (Path path) {
            if (path.ops.length == 0) {
                return null;
            }
            var b = new Gsk.PathBuilder ();
            int c = 0;
            foreach (var op in path.ops) {
                switch (op) {
                case PathOp.MOVE:
                    b.move_to ((float) path.coords[c], (float) path.coords[c + 1]);
                    c += 2;
                    break;
                case PathOp.LINE:
                    b.line_to ((float) path.coords[c], (float) path.coords[c + 1]);
                    c += 2;
                    break;
                case PathOp.CURVE:
                    b.cubic_to ((float) path.coords[c], (float) path.coords[c + 1],
                                (float) path.coords[c + 2], (float) path.coords[c + 3],
                                (float) path.coords[c + 4], (float) path.coords[c + 5]);
                    c += 6;
                    break;
                case PathOp.CLOSE:
                    b.close ();
                    break;
                }
            }
            return b.to_path ();
        }

        void paint_shape (Gtk.Snapshot snapshot, Shape shape) {
            var path = to_gsk (shape.path);
            if (path == null) {
                return;
            }
            if (shape.fill.ink != Ink.NONE) {
                snapshot.append_fill (path, Gsk.FillRule.WINDING, palette.color (shape.fill));
            }
            if (shape.stroke.ink != Ink.NONE && shape.line_width > 0) {
                var stroke = new Gsk.Stroke ((float) shape.line_width);
                stroke.set_line_join (Gsk.LineJoin.ROUND);
                switch (shape.line_style) {
                case LineStyle.DASHED:
                    stroke.set_dash ({ 6f, 4f });
                    break;
                case LineStyle.DOTTED:
                    stroke.set_dash ({ 3f, 3f });
                    break;
                default:
                    break;
                }
                snapshot.append_stroke (path, stroke, palette.color (shape.stroke));
            }
        }

        void paint_text (Gtk.Snapshot snapshot, Text t) {
            var layout = text.layout_for (t.markup, t.style, t.wrap_width, t.align);
            Pango.Rectangle logical;
            layout.get_extents (null, out logical);
            double w = (double) logical.width / Pango.SCALE;
            double h = (double) logical.height / Pango.SCALE;
            double lx = (double) logical.x / Pango.SCALE;
            double x;
            switch (t.align) {
            case Align.START:
                x = t.x;
                break;
            case Align.END:
                x = t.x - w;
                break;
            default:
                x = t.x - w / 2;
                break;
            }
            snapshot.save ();
            snapshot.translate (Graphene.Point () { x = (float) (x - lx), y = (float) (t.y - h / 2) });
            snapshot.append_layout (layout, palette.color (t.color));
            snapshot.restore ();
        }
    }
}
