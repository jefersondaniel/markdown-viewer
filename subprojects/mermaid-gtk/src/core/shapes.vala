/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Node shapes, after Mermaid 12.2.0's
 * src/rendering-util/rendering-elements/shapes/*.ts in the classic look.
 * Copyright (c) 2014-2022 Knut Sveidqvist and Mermaid contributors. MIT License.
 */

namespace Mermaid {

    public enum ShapeKind {
        RECT,
        ROUNDED,
        STADIUM,
        SUBROUTINE,
        CYLINDER,
        CIRCLE,
        DOUBLE_CIRCLE,
        DIAMOND,
        HEXAGON,
        LEAN_RIGHT,
        LEAN_LEFT,
        TRAPEZOID,
        INV_TRAPEZOID,
        ODD,
        ELLIPSE,
        TEXT,
        SMALL_CIRCLE,
        FRAMED_CIRCLE,
        FILLED_CIRCLE,
        FORK,
        TRIANGLE,
        FLIPPED_TRIANGLE,
        NOTCHED_RECT,
        DOCUMENT,
        DELAY,
        LINED_RECT,
        DIVIDED_RECT,
        SLOPED_RECT,
        HOURGLASS,
        CROSSED_CIRCLE,
        STACKED_RECT,
        WINDOW_PANE,
        NOTCHED_PENTAGON,
        HORIZONTAL_CYLINDER,
        FLAG,
        BOLT,
        BRACE_LEFT,
        BRACE_RIGHT,
        BRACES,
        LINED_CYLINDER,
        LINED_DOCUMENT,
        STACKED_DOCUMENT,
        TAGGED_RECT,
        TAGGED_DOCUMENT,
        DISPLAY,
        STORED_DATA,
        DATA_STORE,
        FOLDER
    }

    /* The outline of a node, its decorations and where its label goes. */
    internal class ShapeGeometry {
        /* Filled and stroked. */
        public Path outline = new Path ();
        /* Only stroked: inner lines such as a subroutine's frame. */
        public Path? decoration;
        /* Only filled with the stroke color, for solid markers. */
        public bool solid;
        /* The label's offset from the node's center. */
        public double label_dy;
        /* Whether the outline is drawn at all (text nodes have none). */
        public bool stroked = true;
    }

    namespace Shapes {

        /* Shape names in "A@{ shape: … }", with their aliases. */
        internal bool from_name (string name, out ShapeKind kind) {
            switch (name) {
            case "rect": case "proc": case "process": case "rectangle": case "square":
                kind = ShapeKind.RECT; return true;
            case "rounded": case "event": case "round":
                kind = ShapeKind.ROUNDED; return true;
            case "stadium": case "terminal": case "pill":
                kind = ShapeKind.STADIUM; return true;
            case "fr-rect": case "subprocess": case "subproc": case "framed-rectangle": case "subroutine":
                kind = ShapeKind.SUBROUTINE; return true;
            case "cyl": case "db": case "database": case "cylinder":
                kind = ShapeKind.CYLINDER; return true;
            case "circle": case "circ":
                kind = ShapeKind.CIRCLE; return true;
            case "dbl-circ": case "double-circle": case "doublecircle":
                kind = ShapeKind.DOUBLE_CIRCLE; return true;
            case "diam": case "decision": case "diamond": case "question":
                kind = ShapeKind.DIAMOND; return true;
            case "hex": case "hexagon": case "prepare":
                kind = ShapeKind.HEXAGON; return true;
            case "lean-r": case "lean-right": case "in-out": case "lean_right":
                kind = ShapeKind.LEAN_RIGHT; return true;
            case "lean-l": case "lean-left": case "out-in": case "lean_left":
                kind = ShapeKind.LEAN_LEFT; return true;
            case "trap-b": case "priority": case "trapezoid-bottom": case "trapezoid":
                kind = ShapeKind.TRAPEZOID; return true;
            case "trap-t": case "manual": case "trapezoid-top": case "inv-trapezoid": case "inv_trapezoid":
                kind = ShapeKind.INV_TRAPEZOID; return true;
            case "odd":
                kind = ShapeKind.ODD; return true;
            case "ellipse":
                kind = ShapeKind.ELLIPSE; return true;
            case "text":
                kind = ShapeKind.TEXT; return true;
            case "sm-circ": case "start": case "small-circle":
                kind = ShapeKind.SMALL_CIRCLE; return true;
            case "fr-circ": case "stop": case "framed-circle":
                kind = ShapeKind.FRAMED_CIRCLE; return true;
            case "f-circ": case "junction": case "filled-circle":
                kind = ShapeKind.FILLED_CIRCLE; return true;
            case "fork": case "join":
                kind = ShapeKind.FORK; return true;
            case "tri": case "extract": case "triangle":
                kind = ShapeKind.TRIANGLE; return true;
            case "flip-tri": case "manual-file": case "flipped-triangle":
                kind = ShapeKind.FLIPPED_TRIANGLE; return true;
            case "notch-rect": case "card": case "notched-rectangle":
                kind = ShapeKind.NOTCHED_RECT; return true;
            case "doc": case "document":
                kind = ShapeKind.DOCUMENT; return true;
            case "delay": case "half-rounded-rectangle":
                kind = ShapeKind.DELAY; return true;
            case "lin-rect": case "lined-rectangle": case "lined-process": case "lin-proc": case "shaded-process":
                kind = ShapeKind.LINED_RECT; return true;
            case "div-rect": case "div-proc": case "divided-rectangle": case "divided-process":
                kind = ShapeKind.DIVIDED_RECT; return true;
            case "sl-rect": case "manual-input": case "sloped-rectangle":
                kind = ShapeKind.SLOPED_RECT; return true;
            case "hourglass": case "collate":
                kind = ShapeKind.HOURGLASS; return true;
            case "cross-circ": case "summary": case "crossed-circle":
                kind = ShapeKind.CROSSED_CIRCLE; return true;
            case "st-rect": case "procs": case "processes": case "stacked-rectangle":
                kind = ShapeKind.STACKED_RECT; return true;
            case "win-pane": case "internal-storage": case "window-pane":
                kind = ShapeKind.WINDOW_PANE; return true;
            case "notch-pent": case "loop-limit": case "notched-pentagon":
                kind = ShapeKind.NOTCHED_PENTAGON; return true;
            case "h-cyl": case "das": case "horizontal-cylinder":
                kind = ShapeKind.HORIZONTAL_CYLINDER; return true;
            case "flag": case "paper-tape":
                kind = ShapeKind.FLAG; return true;
            case "bolt": case "com-link": case "lightning-bolt":
                kind = ShapeKind.BOLT; return true;
            case "brace": case "comment": case "brace-l":
                kind = ShapeKind.BRACE_LEFT; return true;
            case "brace-r":
                kind = ShapeKind.BRACE_RIGHT; return true;
            case "braces":
                kind = ShapeKind.BRACES; return true;
            case "lin-cyl": case "disk": case "lined-cylinder":
                kind = ShapeKind.LINED_CYLINDER; return true;
            case "lin-doc": case "lined-document":
                kind = ShapeKind.LINED_DOCUMENT; return true;
            case "docs": case "documents": case "st-doc": case "stacked-document":
                kind = ShapeKind.STACKED_DOCUMENT; return true;
            case "tag-rect": case "tagged-rectangle": case "tag-proc": case "tagged-process":
                kind = ShapeKind.TAGGED_RECT; return true;
            case "tag-doc": case "tagged-document":
                kind = ShapeKind.TAGGED_DOCUMENT; return true;
            case "curv-trap": case "curved-trapezoid": case "display":
                kind = ShapeKind.DISPLAY; return true;
            case "bow-rect": case "stored-data": case "bow-tie-rectangle":
                kind = ShapeKind.STORED_DATA; return true;
            case "datastore": case "data-store":
                kind = ShapeKind.DATA_STORE; return true;
            case "folder": case "directory":
                kind = ShapeKind.FOLDER; return true;
            }
            kind = ShapeKind.RECT;
            return false;
        }

        /* The node size for a label of the given size, with padding p. */
        internal Size size_for (ShapeKind kind, Size label, double p) {
            double lw = label.width, lh = label.height;
            double w, h;
            switch (kind) {
            case ShapeKind.RECT:
            case ShapeKind.ROUNDED:
            case ShapeKind.NOTCHED_RECT:
            case ShapeKind.LINED_RECT:
            case ShapeKind.STACKED_RECT:
                w = lw + 2 * p;
                h = lh + 2 * p;
                if (kind == ShapeKind.LINED_RECT) {
                    w += 8;
                } else if (kind == ShapeKind.STACKED_RECT) {
                    w += 8;
                    h += 8;
                }
                break;
            case ShapeKind.WINDOW_PANE:
                w = lw + 2 * p + 10;
                h = lh + 2 * p + 10;
                break;
            case ShapeKind.DIVIDED_RECT:
                w = lw + 2 * p;
                h = lh + 2 * p + lh * 0.4;
                break;
            case ShapeKind.STADIUM:
                h = lh + p;
                w = lw + h + p / 2;
                break;
            case ShapeKind.SUBROUTINE:
                w = lw + p + 16;
                h = lh + p;
                break;
            case ShapeKind.CYLINDER:
            case ShapeKind.LINED_CYLINDER:
                w = lw + p;
                double ry = w / 2 / (2.5 + w / 50);
                h = lh + p + 2 * ry;
                break;
            case ShapeKind.HORIZONTAL_CYLINDER:
                h = lh + p;
                double rx = h / 2 / (2.5 + h / 50);
                w = lw + p + 3 * rx;
                break;
            case ShapeKind.CIRCLE:
            case ShapeKind.CROSSED_CIRCLE:
                w = h = Math.sqrt (lw * lw + lh * lh) + p;
                break;
            case ShapeKind.DOUBLE_CIRCLE:
                w = h = Math.sqrt (lw * lw + lh * lh) + p + 10;
                break;
            case ShapeKind.DIAMOND:
                w = h = lw + lh + 2 * p;
                break;
            case ShapeKind.HEXAGON:
                h = lh + p;
                w = lw + 2 * (h / 4) + p;
                break;
            case ShapeKind.LEAN_RIGHT:
            case ShapeKind.LEAN_LEFT:
            case ShapeKind.TRAPEZOID:
            case ShapeKind.INV_TRAPEZOID:
                h = lh + p;
                w = lw + p + h;
                break;
            case ShapeKind.ODD:
                h = lh + p;
                w = lw + p + h / 2;
                break;
            case ShapeKind.ELLIPSE:
                w = lw + 2 * p;
                h = lh + 2 * p;
                break;
            case ShapeKind.TEXT:
                w = lw;
                h = lh;
                break;
            case ShapeKind.SMALL_CIRCLE:
            case ShapeKind.FILLED_CIRCLE:
                w = h = 14;
                break;
            case ShapeKind.FRAMED_CIRCLE:
                w = h = 14;
                break;
            case ShapeKind.FORK:
                w = 70;
                h = 10;
                break;
            case ShapeKind.TRIANGLE:
            case ShapeKind.FLIPPED_TRIANGLE:
                w = (lw + p) * 1.6 + lh;
                h = w * 0.6 + lh / 2;
                break;
            case ShapeKind.DOCUMENT:
            case ShapeKind.FLAG:
            case ShapeKind.LINED_DOCUMENT:
            case ShapeKind.TAGGED_DOCUMENT:
                w = lw + 2 * p;
                h = lh + 2 * p + 8;
                if (kind == ShapeKind.LINED_DOCUMENT) {
                    w += 8;
                }
                break;
            case ShapeKind.STACKED_DOCUMENT:
                w = lw + 2 * p + 8;
                h = lh + 2 * p + 16;
                break;
            case ShapeKind.TAGGED_RECT:
                w = lw + 2 * p;
                h = lh + 2 * p;
                break;
            case ShapeKind.DISPLAY:
            case ShapeKind.STORED_DATA:
                h = lh + p;
                w = lw + p + h;
                break;
            case ShapeKind.DATA_STORE:
                w = lw + 2 * p;
                h = lh + p;
                break;
            case ShapeKind.FOLDER:
                w = lw + 2 * p;
                h = lh + 2 * p + 8;
                break;
            case ShapeKind.DELAY:
                h = lh + 2 * p;
                w = lw + 2 * p + h / 4;
                break;
            case ShapeKind.SLOPED_RECT:
                w = lw + 2 * p;
                h = lh + 2 * p + 10;
                break;
            case ShapeKind.HOURGLASS:
                w = h = 30;
                break;
            case ShapeKind.NOTCHED_PENTAGON:
                w = lw + 2 * p + 20;
                h = lh + 2 * p;
                break;
            case ShapeKind.BOLT:
                w = 35;
                h = 50;
                break;
            case ShapeKind.BRACE_LEFT:
            case ShapeKind.BRACE_RIGHT:
                w = lw + p + 12;
                h = lh + p;
                break;
            case ShapeKind.BRACES:
                w = lw + p + 24;
                h = lh + p;
                break;
            default:
                w = lw + 2 * p;
                h = lh + 2 * p;
                break;
            }
            return Size () { width = w, height = h };
        }

        /* Shapes that never show a label, such as junction points. */
        internal bool unlabeled (ShapeKind kind) {
            return kind == ShapeKind.FORK || kind == ShapeKind.FILLED_CIRCLE
                || kind == ShapeKind.SMALL_CIRCLE || kind == ShapeKind.FRAMED_CIRCLE;
        }

        /* Whether a label is drawn below the shape rather than inside. */
        internal bool label_outside (ShapeKind kind) {
            return kind == ShapeKind.HOURGLASS || kind == ShapeKind.BOLT;
        }

        /* The geometry of a node centered at (cx, cy), w × h large. */
        internal ShapeGeometry geometry (ShapeKind kind, double cx, double cy, double w, double h) {
            var g = new ShapeGeometry ();
            var o = g.outline;
            double x = cx - w / 2, y = cy - h / 2;
            switch (kind) {
            case ShapeKind.RECT:
                o.rect (x, y, w, h);
                break;
            case ShapeKind.ROUNDED:
                o.rounded_rect (x, y, w, h, 5);
                break;
            case ShapeKind.STADIUM:
                o.rounded_rect (x, y, w, h, h / 2);
                break;
            case ShapeKind.SUBROUTINE:
                o.rect (x, y, w, h);
                g.decoration = new Path ();
                g.decoration.move_to (x + 8, y);
                g.decoration.line_to (x + 8, y + h);
                g.decoration.move_to (x + w - 8, y);
                g.decoration.line_to (x + w - 8, y + h);
                break;
            case ShapeKind.CYLINDER:
            case ShapeKind.LINED_CYLINDER: {
                double rx = w / 2, ry = rx / (2.5 + w / 50);
                o.move_to (x, y + ry);
                o.arc (cx, y + ry, rx, ry, Math.PI, 2 * Math.PI, false);
                o.line_to (x + w, y + h - ry);
                o.arc (cx, y + h - ry, rx, ry, 0, Math.PI, false);
                o.close ();
                g.decoration = new Path ();
                g.decoration.arc (cx, y + ry, rx, ry, 0, Math.PI, true);
                if (kind == ShapeKind.LINED_CYLINDER) {
                    g.decoration.arc (cx, y + 3 * ry, rx, ry, 0, Math.PI, true);
                    g.label_dy = ry;
                } else {
                    g.label_dy = ry / 2;
                }
                break;
            }
            case ShapeKind.HORIZONTAL_CYLINDER: {
                double ry = h / 2, rx = ry / (2.5 + h / 50);
                o.move_to (x + rx, y);
                o.line_to (x + w - rx, y);
                o.arc (x + w - rx, cy, rx, ry, -Math.PI / 2, Math.PI / 2, false);
                o.line_to (x + rx, y + h);
                o.arc (x + rx, cy, rx, ry, Math.PI / 2, 3 * Math.PI / 2, false);
                o.close ();
                g.decoration = new Path ();
                g.decoration.arc (x + w - rx, cy, rx, ry, Math.PI / 2, 3 * Math.PI / 2, true);
                break;
            }
            case ShapeKind.CIRCLE:
                o.ellipse (cx, cy, w / 2, h / 2);
                break;
            case ShapeKind.CROSSED_CIRCLE: {
                o.ellipse (cx, cy, w / 2, h / 2);
                double d = w / 2 * 0.70710678;
                g.decoration = new Path ();
                g.decoration.move_to (cx - d, cy - d);
                g.decoration.line_to (cx + d, cy + d);
                g.decoration.move_to (cx + d, cy - d);
                g.decoration.line_to (cx - d, cy + d);
                break;
            }
            case ShapeKind.DOUBLE_CIRCLE:
                o.ellipse (cx, cy, w / 2, h / 2);
                g.decoration = new Path ();
                g.decoration.ellipse (cx, cy, w / 2 - 5, h / 2 - 5);
                break;
            case ShapeKind.ELLIPSE:
                o.ellipse (cx, cy, w / 2, h / 2);
                break;
            case ShapeKind.DIAMOND:
                o.polygon ({ cx, y, x + w, cy, cx, y + h, x, cy });
                break;
            case ShapeKind.HEXAGON: {
                double m = h / 4;
                o.polygon ({ x + m, y, x + w - m, y, x + w, cy, x + w - m, y + h, x + m, y + h, x, cy });
                break;
            }
            case ShapeKind.LEAN_RIGHT: {
                double m = h / 2;
                o.polygon ({ x + m, y, x + w, y, x + w - m, y + h, x, y + h });
                break;
            }
            case ShapeKind.LEAN_LEFT: {
                double m = h / 2;
                o.polygon ({ x, y, x + w - m, y, x + w, y + h, x + m, y + h });
                break;
            }
            case ShapeKind.TRAPEZOID: {
                double m = h / 2;
                o.polygon ({ x + m, y, x + w - m, y, x + w, y + h, x, y + h });
                break;
            }
            case ShapeKind.INV_TRAPEZOID: {
                double m = h / 2;
                o.polygon ({ x, y, x + w, y, x + w - m, y + h, x + m, y + h });
                break;
            }
            case ShapeKind.ODD: {
                double m = h / 2;
                o.polygon ({ x, y, x + w, y, x + w, y + h, x, y + h, x + m, cy });
                g.label_dy = 0;
                break;
            }
            case ShapeKind.TEXT:
                o.rect (x, y, w, h);
                g.stroked = false;
                break;
            case ShapeKind.SMALL_CIRCLE:
            case ShapeKind.FILLED_CIRCLE:
                o.ellipse (cx, cy, w / 2, h / 2);
                g.solid = true;
                break;
            case ShapeKind.FRAMED_CIRCLE:
                o.ellipse (cx, cy, w / 2, h / 2);
                g.decoration = new Path ();
                g.decoration.ellipse (cx, cy, w / 2 - 3, h / 2 - 3);
                break;
            case ShapeKind.FORK:
                o.rect (x, y, w, h);
                g.solid = true;
                break;
            case ShapeKind.TRIANGLE:
                o.polygon ({ cx, y, x + w, y + h, x, y + h });
                g.label_dy = h / 6;
                break;
            case ShapeKind.FLIPPED_TRIANGLE:
                o.polygon ({ x, y, x + w, y, cx, y + h });
                g.label_dy = -h / 6;
                break;
            case ShapeKind.NOTCHED_RECT: {
                double n = 12;
                o.polygon ({ x + n, y, x + w, y, x + w, y + h, x, y + h, x, y + n });
                break;
            }
            case ShapeKind.DOCUMENT: {
                double a = 6;
                o.move_to (x, y);
                o.line_to (x + w, y);
                o.line_to (x + w, y + h - a);
                o.curve_to (x + w * 0.75, y + h - 3 * a, x + w * 0.25, y + h + a, x, y + h - a);
                o.close ();
                g.label_dy = -a / 2;
                break;
            }
            case ShapeKind.LINED_DOCUMENT:
            case ShapeKind.TAGGED_DOCUMENT: {
                double a = 6;
                o.move_to (x, y);
                o.line_to (x + w, y);
                o.line_to (x + w, y + h - a);
                o.curve_to (x + w * 0.75, y + h - 3 * a, x + w * 0.25, y + h + a, x, y + h - a);
                o.close ();
                g.decoration = new Path ();
                if (kind == ShapeKind.LINED_DOCUMENT) {
                    g.decoration.move_to (x + 8, y);
                    g.decoration.line_to (x + 8, y + h - a + 1);
                    g.label_dy = -a / 2;
                } else {
                    double t = 12;
                    g.decoration.polygon ({ x + w - t, y + h - a - 4, x + w, y + h - a - 4 - t, x + w, y + h - a - 4 });
                    g.label_dy = -a / 2;
                }
                break;
            }
            case ShapeKind.STACKED_DOCUMENT: {
                double a = 6, s = 4;
                o.move_to (x, y + 2 * s);
                o.line_to (x + w - 2 * s, y + 2 * s);
                o.line_to (x + w - 2 * s, y + h - a);
                o.curve_to (x + (w - 2 * s) * 0.75, y + h - 3 * a, x + (w - 2 * s) * 0.25, y + h + a, x, y + h - a);
                o.close ();
                g.decoration = new Path ();
                g.decoration.move_to (x + s, y + 2 * s);
                g.decoration.line_to (x + s, y + s);
                g.decoration.line_to (x + w - s, y + s);
                g.decoration.line_to (x + w - s, y + h - 2 * a);
                g.decoration.move_to (x + 2 * s, y + s);
                g.decoration.line_to (x + 2 * s, y);
                g.decoration.line_to (x + w, y);
                g.decoration.line_to (x + w, y + h - 2 * a - s);
                g.label_dy = s - a / 2;
                break;
            }
            case ShapeKind.TAGGED_RECT: {
                double t = 12;
                o.rect (x, y, w, h);
                g.decoration = new Path ();
                g.decoration.polygon ({ x + w - t, y + h, x + w, y + h - t, x + w, y + h });
                break;
            }
            case ShapeKind.DISPLAY: {
                double m = h / 2;
                o.move_to (x + m, y);
                o.line_to (x + w - m, y);
                o.curve_to (x + w, y, x + w, y + h, x + w - m, y + h);
                o.line_to (x + m, y + h);
                o.line_to (x, cy);
                o.close ();
                break;
            }
            case ShapeKind.STORED_DATA: {
                double r = h / 4;
                o.move_to (x + r, y);
                o.line_to (x + w, y);
                o.curve_to (x + w - 2 * r, y, x + w - 2 * r, y + h, x + w, y + h);
                o.line_to (x + r, y + h);
                o.curve_to (x - r, y + h, x - r, y, x + r, y);
                o.close ();
                break;
            }
            case ShapeKind.DATA_STORE:
                o.rect (x, y, w, h);
                g.stroked = true;
                g.decoration = new Path ();
                g.decoration.move_to (x, y);
                g.decoration.line_to (x + w, y);
                g.decoration.move_to (x, y + h);
                g.decoration.line_to (x + w, y + h);
                break;
            case ShapeKind.FOLDER: {
                double tab = double.min (w * 0.4, 40), t = 8;
                o.move_to (x, y);
                o.line_to (x + tab, y);
                o.line_to (x + tab + t, y + t);
                o.line_to (x + w, y + t);
                o.line_to (x + w, y + h);
                o.line_to (x, y + h);
                o.close ();
                g.label_dy = t / 2;
                break;
            }
            case ShapeKind.FLAG: {
                double a = 6;
                o.move_to (x, y + a);
                o.curve_to (x + w * 0.25, y - a, x + w * 0.75, y + 3 * a, x + w, y + a);
                o.line_to (x + w, y + h - a);
                o.curve_to (x + w * 0.75, y + h - 3 * a, x + w * 0.25, y + h + a, x, y + h - a);
                o.close ();
                break;
            }
            case ShapeKind.DELAY: {
                double r = h / 2;
                o.move_to (x, y);
                o.line_to (x + w - r, y);
                o.arc (x + w - r, cy, r, r, -Math.PI / 2, Math.PI / 2, false);
                o.line_to (x, y + h);
                o.close ();
                break;
            }
            case ShapeKind.LINED_RECT:
                o.rect (x, y, w, h);
                g.decoration = new Path ();
                g.decoration.move_to (x + 8, y);
                g.decoration.line_to (x + 8, y + h);
                break;
            case ShapeKind.DIVIDED_RECT: {
                o.rect (x, y, w, h);
                double top = h * 0.2;
                g.decoration = new Path ();
                g.decoration.move_to (x, y + top);
                g.decoration.line_to (x + w, y + top);
                g.label_dy = top / 2;
                break;
            }
            case ShapeKind.SLOPED_RECT:
                o.polygon ({ x, y + 10, x + w, y, x + w, y + h, x, y + h });
                g.label_dy = 5;
                break;
            case ShapeKind.HOURGLASS:
                o.polygon ({ x, y, x + w, y, x, y + h, x + w, y + h });
                break;
            case ShapeKind.STACKED_RECT: {
                double s = 4;
                o.rect (x, y + 2 * s, w - 2 * s, h - 2 * s);
                g.decoration = new Path ();
                g.decoration.move_to (x + s, y + 2 * s);
                g.decoration.line_to (x + s, y + s);
                g.decoration.line_to (x + w - s, y + s);
                g.decoration.line_to (x + w - s, y + h - s);
                g.decoration.line_to (x + w - 2 * s, y + h - s);
                g.decoration.move_to (x + 2 * s, y + s);
                g.decoration.line_to (x + 2 * s, y);
                g.decoration.line_to (x + w, y);
                g.decoration.line_to (x + w, y + h - 2 * s);
                g.decoration.line_to (x + w - s, y + h - 2 * s);
                g.label_dy = s;
                break;
            }
            case ShapeKind.WINDOW_PANE:
                o.rect (x, y, w, h);
                g.decoration = new Path ();
                g.decoration.move_to (x + 10, y);
                g.decoration.line_to (x + 10, y + h);
                g.decoration.move_to (x, y + 10);
                g.decoration.line_to (x + w, y + 10);
                g.label_dy = 5;
                break;
            case ShapeKind.NOTCHED_PENTAGON: {
                double n = 10;
                o.polygon ({ x + n, y, x + w - n, y, x + w, y + n, x + w, y + h, x, y + h, x, y + n });
                break;
            }
            case ShapeKind.BOLT:
                o.polygon ({ x + w * 0.65, y, x + w * 0.1, y + h * 0.55, x + w * 0.45, y + h * 0.55,
                             x + w * 0.35, y + h, x + w * 0.9, y + h * 0.45, x + w * 0.55, y + h * 0.45 });
                break;
            case ShapeKind.BRACE_LEFT:
            case ShapeKind.BRACE_RIGHT:
            case ShapeKind.BRACES:
                o.rect (x, y, w, h);
                g.stroked = false;
                g.decoration = new Path ();
                if (kind != ShapeKind.BRACE_RIGHT) {
                    brace (g.decoration, x + 10, y, h, true);
                }
                if (kind != ShapeKind.BRACE_LEFT) {
                    brace (g.decoration, x + w - 10, y, h, false);
                }
                break;
            default:
                o.rect (x, y, w, h);
                break;
            }
            return g;
        }

        void brace (Path p, double x, double y, double h, bool left) {
            double d = left ? -1 : 1;
            double r = 5;
            p.move_to (x + d * -r, y);
            p.curve_to (x, y, x, y, x, y + r);
            p.line_to (x, y + h / 2 - r);
            p.curve_to (x, y + h / 2, x, y + h / 2, x + d * r, y + h / 2);
            p.curve_to (x, y + h / 2, x, y + h / 2, x, y + h / 2 + r);
            p.line_to (x, y + h - r);
            p.curve_to (x, y + h, x, y + h, x + d * -r, y + h);
        }
    }

    namespace Geometry {

        internal struct Pt {
            public double x;
            public double y;
        }

        /* The path's points, with curves flattened. */
        internal Pt[] flatten (Path path) {
            Pt[] pts = {};
            int c = 0;
            double lx = 0, ly = 0, sx = 0, sy = 0;
            foreach (var op in path.ops) {
                switch (op) {
                case PathOp.MOVE:
                    lx = sx = path.coords[c];
                    ly = sy = path.coords[c + 1];
                    pts += Pt () { x = lx, y = ly };
                    c += 2;
                    break;
                case PathOp.LINE:
                    lx = path.coords[c];
                    ly = path.coords[c + 1];
                    pts += Pt () { x = lx, y = ly };
                    c += 2;
                    break;
                case PathOp.CURVE:
                    double x1 = path.coords[c], y1 = path.coords[c + 1];
                    double x2 = path.coords[c + 2], y2 = path.coords[c + 3];
                    double x3 = path.coords[c + 4], y3 = path.coords[c + 5];
                    for (int i = 1; i <= 8; i++) {
                        double t = i / 8.0, u = 1 - t;
                        pts += Pt () {
                            x = u * u * u * lx + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x3,
                            y = u * u * u * ly + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y3
                        };
                    }
                    lx = x3;
                    ly = y3;
                    c += 6;
                    break;
                case PathOp.CLOSE:
                    pts += Pt () { x = sx, y = sy };
                    lx = sx;
                    ly = sy;
                    break;
                }
            }
            return pts;
        }

        /*
         * Where the line from `outside` to `center` first crosses the
         * outline; `outside` itself when it doesn't.
         */
        internal Pt intersect (Path outline, Pt center, Pt outside) {
            var pts = flatten (outline);
            double best_t = double.INFINITY;
            Pt best = outside;
            for (int i = 0; i + 1 < pts.length; i++) {
                Pt hit;
                double t;
                if (segment_intersection (outside, center, pts[i], pts[i + 1], out hit, out t)) {
                    if (t < best_t) {
                        best_t = t;
                        best = hit;
                    }
                }
            }
            return best;
        }

        /* Whether segments a-b and c-d cross; t is the position along a-b. */
        internal bool segment_intersection (Pt a, Pt b, Pt c, Pt d, out Pt hit, out double t) {
            double rx = b.x - a.x, ry = b.y - a.y;
            double sx = d.x - c.x, sy = d.y - c.y;
            double denom = rx * sy - ry * sx;
            hit = a;
            t = 0;
            if (Math.fabs (denom) < 1e-12) {
                return false;
            }
            double qx = c.x - a.x, qy = c.y - a.y;
            t = (qx * sy - qy * sx) / denom;
            double u = (qx * ry - qy * rx) / denom;
            if (t < -1e-9 || t > 1 + 1e-9 || u < -1e-9 || u > 1 + 1e-9) {
                return false;
            }
            hit = Pt () { x = a.x + t * rx, y = a.y + t * ry };
            return true;
        }

        internal bool inside_rect (Pt p, double cx, double cy, double w, double h) {
            return Math.fabs (p.x - cx) <= w / 2 + 0.01 && Math.fabs (p.y - cy) <= h / 2 + 0.01;
        }
    }
}
