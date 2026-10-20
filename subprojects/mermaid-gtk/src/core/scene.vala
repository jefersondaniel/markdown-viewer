/* SPDX-License-Identifier: GPL-3.0-or-later */

namespace Mermaid {

    /*
     * The kind of color an item is painted with. The painter picks the actual
     * colors, so a diagram follows the light or dark style without being laid
     * out again.
     */
    public enum Ink {
        NONE,
        /* The diagram's background, for things that cover lines. */
        BACKGROUND,
        TEXT,
        LINE,
        NODE_FILL,
        NODE_STROKE,
        /* Subgraphs, sequence boxes and composite states. */
        GROUP_FILL,
        GROUP_STROKE,
        NOTE_FILL,
        NOTE_STROKE,
        /* Sequence activation bars and similar highlights. */
        ACCENT_FILL,
        /* Solid start and end markers, such as state diagram start points. */
        SOLID,
        /* A color from the categorical palette; see Paint.index. */
        PALETTE,
        /* A color given in the diagram source; see Paint.rgba. */
        CUSTOM
    }

    public struct Paint {
        public Ink ink;
        /* For Ink.PALETTE. */
        public int index;
        /* For Ink.CUSTOM: 0xRRGGBBAA. */
        public uint32 rgba;

        public Paint (Ink ink) {
            this.ink = ink;
            this.index = 0;
            this.rgba = 0;
        }

        public Paint.palette (int index) {
            this.ink = Ink.PALETTE;
            this.index = index;
            this.rgba = 0;
        }

        public Paint.custom (uint32 rgba) {
            this.ink = Ink.CUSTOM;
            this.index = 0;
            this.rgba = rgba;
        }

        public string to_string () {
            switch (ink) {
            case Ink.PALETTE:
                return "palette%d".printf (index);
            case Ink.CUSTOM:
                return "#%08x".printf (rgba);
            default:
                return ink.to_string ().replace ("MERMAID_INK_", "").down ();
            }
        }
    }

    public enum PathOp {
        MOVE,
        LINE,
        CURVE,
        CLOSE
    }

    /* A vector path in scene coordinates. */
    public class Path {
        PathOp[] _ops = {};
        double[] _coords = {};

        public PathOp[] ops {
            get { return _ops; }
        }

        /* Two numbers per point: one point for MOVE and LINE, three for CURVE. */
        public double[] coords {
            get { return _coords; }
        }

        /* Moves every point by (dx, dy). */
        public void translate (double dx, double dy) {
            for (int i = 0; i + 1 < _coords.length; i += 2) {
                _coords[i] += dx;
                _coords[i + 1] += dy;
            }
        }

        public void move_to (double x, double y) {
            _ops += PathOp.MOVE;
            _coords += x;
            _coords += y;
        }

        public void line_to (double x, double y) {
            _ops += PathOp.LINE;
            _coords += x;
            _coords += y;
        }

        public void curve_to (double x1, double y1, double x2, double y2, double x3, double y3) {
            _ops += PathOp.CURVE;
            _coords += x1;
            _coords += y1;
            _coords += x2;
            _coords += y2;
            _coords += x3;
            _coords += y3;
        }

        public void close () {
            _ops += PathOp.CLOSE;
        }

        public void rect (double x, double y, double w, double h) {
            move_to (x, y);
            line_to (x + w, y);
            line_to (x + w, y + h);
            line_to (x, y + h);
            close ();
        }

        public void rounded_rect (double x, double y, double w, double h, double r) {
            r = double.min (r, double.min (w, h) / 2);
            if (r <= 0) {
                rect (x, y, w, h);
                return;
            }
            move_to (x + r, y);
            line_to (x + w - r, y);
            arc_corner (x + w - r, y + r, r, -Math.PI / 2);
            line_to (x + w, y + h - r);
            arc_corner (x + w - r, y + h - r, r, 0);
            line_to (x + r, y + h);
            arc_corner (x + r, y + h - r, r, Math.PI / 2);
            line_to (x, y + r);
            arc_corner (x + r, y + r, r, Math.PI);
            close ();
        }

        /* A quarter circle around (cx, cy), starting at angle `start`. */
        void arc_corner (double cx, double cy, double r, double start) {
            arc (cx, cy, r, r, start, start + Math.PI / 2, false);
        }

        public void ellipse (double cx, double cy, double rx, double ry) {
            move_to (cx + rx, cy);
            arc (cx, cy, rx, ry, 0, 2 * Math.PI, false);
            close ();
        }

        /*
         * An elliptical arc from angle a0 to a1 (radians, clockwise in screen
         * coordinates), approximated with cubic curves. Starts with a line to
         * the arc's first point unless `move` is set.
         */
        public void arc (double cx, double cy, double rx, double ry, double a0, double a1, bool move) {
            int segments = int.max (1, (int) Math.ceil (Math.fabs (a1 - a0) / (Math.PI / 2) - 1e-9));
            double step = (a1 - a0) / segments;
            double k = 4.0 / 3.0 * Math.tan (step / 4);
            double x0 = cx + rx * Math.cos (a0), y0 = cy + ry * Math.sin (a0);
            if (move) {
                move_to (x0, y0);
            } else if (_ops.length == 0 || last_x () != x0 || last_y () != y0) {
                line_to (x0, y0);
            }
            for (int i = 0; i < segments; i++) {
                double t0 = a0 + i * step, t1 = t0 + step;
                double c0 = Math.cos (t0), s0 = Math.sin (t0);
                double c1 = Math.cos (t1), s1 = Math.sin (t1);
                curve_to (cx + rx * (c0 - k * s0), cy + ry * (s0 + k * c0),
                          cx + rx * (c1 + k * s1), cy + ry * (s1 - k * c1),
                          cx + rx * c1, cy + ry * s1);
            }
        }

        double last_x () {
            return _coords.length >= 2 ? _coords[_coords.length - 2] : 0;
        }

        double last_y () {
            return _coords.length >= 2 ? _coords[_coords.length - 1] : 0;
        }

        public void polygon (double[] points) {
            for (int i = 0; i + 1 < points.length; i += 2) {
                if (i == 0) {
                    move_to (points[i], points[i + 1]);
                } else {
                    line_to (points[i], points[i + 1]);
                }
            }
            close ();
        }

        public string to_string () {
            var sb = new StringBuilder ();
            int c = 0;
            unowned double[] coords = _coords;
            foreach (var op in _ops) {
                switch (op) {
                case PathOp.MOVE:
                    sb.append_printf ("M%s,%s ", fmt (coords[c]), fmt (coords[c + 1]));
                    c += 2;
                    break;
                case PathOp.LINE:
                    sb.append_printf ("L%s,%s ", fmt (coords[c]), fmt (coords[c + 1]));
                    c += 2;
                    break;
                case PathOp.CURVE:
                    sb.append_printf ("C%s,%s %s,%s %s,%s ", fmt (coords[c]), fmt (coords[c + 1]),
                                      fmt (coords[c + 2]), fmt (coords[c + 3]),
                                      fmt (coords[c + 4]), fmt (coords[c + 5]));
                    c += 6;
                    break;
                case PathOp.CLOSE:
                    sb.append ("Z ");
                    break;
                }
            }
            return sb.str.strip ();
        }
    }

    /* A number with one decimal, whatever the locale. */
    internal string fmt (double d) {
        char[] buf = new char[double.DTOSTR_BUF_SIZE];
        string s = d.format (buf, "%.1f");
        return s == "-0.0" ? "0.0" : s;
    }

    public enum LineStyle {
        SOLID,
        DASHED,
        DOTTED
    }

    public abstract class Item {
        public abstract string to_string ();
    }

    public class Shape : Item {
        public Path path;
        public Paint fill;
        public Paint stroke;
        public double line_width = 1;
        public LineStyle line_style = LineStyle.SOLID;

        public Shape (Path path, Paint fill, Paint stroke, double line_width = 1) {
            this.path = path;
            this.fill = fill;
            this.stroke = stroke;
            this.line_width = line_width;
        }

        public override string to_string () {
            var sb = new StringBuilder ("shape");
            if (fill.ink != Ink.NONE) {
                sb.append_printf (" fill=%s", fill.to_string ());
            }
            if (stroke.ink != Ink.NONE) {
                sb.append_printf (" stroke=%s/%s", stroke.to_string (), fmt (line_width));
            }
            if (line_style != LineStyle.SOLID) {
                sb.append_printf (" %s", line_style == LineStyle.DASHED ? "dashed" : "dotted");
            }
            sb.append_printf (" %s", path.to_string ());
            return sb.str;
        }
    }

    public enum Align {
        START,
        CENTER,
        END
    }

    /*
     * A block of text. `markup` is Pango markup limited to <b>, <i>, <s> and
     * <tt>, with lines separated by "\n". The block is placed so that its
     * horizontal anchor (start, center or end) is at x and its vertical
     * center at y.
     */
    public class Text : Item {
        public string markup;
        public double x;
        public double y;
        public Align align = Align.CENTER;
        public TextStyle style;
        public Paint color = Paint (Ink.TEXT);
        /* Lines longer than this wrap; 0 means no wrapping. */
        public double wrap_width;

        public Text (string markup, double x, double y, TextStyle style) {
            this.markup = markup;
            this.x = x;
            this.y = y;
            this.style = style;
        }

        public override string to_string () {
            return "text %s,%s %s %s%s%s \"%s\"".printf (
                fmt (x), fmt (y), align.to_string ().replace ("MERMAID_ALIGN_", "").down (),
                fmt (style.size), style.bold ? " bold" : "",
                color.ink != Ink.TEXT ? " color=" + color.to_string () : "", markup.replace ("\n", "\\n"));
        }
    }

    public struct TextStyle {
        public double size;
        public bool bold;
        public bool italic;
        public bool monospace;

        public TextStyle (double size, bool bold = false) {
            this.size = size;
            this.bold = bold;
            this.italic = false;
            this.monospace = false;
        }
    }

    /* A laid-out diagram: items in painting order, in a width × height box. */
    public class Scene {
        public double width;
        public double height;
        public GenericArray<Item> items = new GenericArray<Item> ();
        /* The diagram's title, also drawn as an item when there is one. */
        public string? title;

        public void add (Item item) {
            items.add (item);
        }

        public Shape add_shape (Path path, Paint fill, Paint stroke, double line_width = 1) {
            var shape = new Shape (path, fill, stroke, line_width);
            items.add (shape);
            return shape;
        }

        public Text add_text (string markup, double x, double y, TextStyle style, Align align = Align.CENTER) {
            var text = new Text (markup, x, y, style);
            text.align = align;
            items.add (text);
            return text;
        }

        /* A text dump, used by the tests. */
        public string dump () {
            var sb = new StringBuilder ();
            sb.append_printf ("scene %s %s\n", fmt (width), fmt (height));
            foreach (var item in items) {
                sb.append (item.to_string ());
                sb.append_c ('\n');
            }
            return sb.str;
        }

        /*
         * Grows the scene so that every shape is inside it, with `margin`
         * around shapes that stick out.
         */
        public void fit_shapes (double margin) {
            double x0 = 0, y0 = 0, x1 = width, y1 = height;
            foreach (var item in items) {
                if (item is Shape) {
                    var c = ((Shape) item).path.coords;
                    for (int i = 0; i + 1 < c.length; i += 2) {
                        x0 = double.min (x0, c[i] - margin);
                        x1 = double.max (x1, c[i] + margin);
                        y0 = double.min (y0, c[i + 1] - margin);
                        y1 = double.max (y1, c[i + 1] + margin);
                    }
                }
            }
            if (x0 < 0 || y0 < 0) {
                translate (-x0, -y0);
            }
            width = x1 - x0;
            height = y1 - y0;
        }

        /* Moves every item by (dx, dy). */
        public void translate (double dx, double dy) {
            foreach (var item in items) {
                if (item is Shape) {
                    ((Shape) item).path.translate (dx, dy);
                } else if (item is Text) {
                    ((Text) item).x += dx;
                    ((Text) item).y += dy;
                }
            }
        }
    }
}
