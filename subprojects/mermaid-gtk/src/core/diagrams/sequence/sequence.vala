/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Sequence diagrams. The syntax follows Mermaid 12.2.0's
 * src/diagrams/sequence/parser/sequenceDiagram.jison and sequenceDb.ts, and
 * the layout the configuration and spacing of its sequenceRenderer.ts.
 * Copyright (c) 2014-2022 Knut Sveidqvist and Mermaid contributors. MIT License.
 */

namespace Mermaid {

    internal class SeqActor {
        public string id;
        public string label;
        public bool stick_figure;
        public int index;
        public double width;
        public double x;
        /* The gap to the next actor. */
        public double margin = SequenceDiagram.ACTOR_MARGIN;
        public bool created;
        public SeqBox? box;
    }

    internal class SeqBox {
        public string title = "";
        public Paint? fill;
        public GenericArray<SeqActor> actors = new GenericArray<SeqActor> ();
    }

    internal enum SeqKind {
        MESSAGE,
        NOTE,
        ACTIVATE,
        DEACTIVATE,
        BLOCK_START,
        BLOCK_SECTION,
        BLOCK_END,
        AUTONUMBER,
        CREATE,
        DESTROY
    }

    internal class SeqEvent {
        public SeqKind kind;
        public SeqActor? from;
        public SeqActor? to;
        public string text = "";
        // Messages.
        public bool dotted;
        public Marker head = Marker.NONE;
        public Marker tail = Marker.NONE;
        public bool activate_target;
        public bool deactivate_source;
        // Notes: "left", "right" or "over".
        public string placement = "over";
        // Blocks: "loop", "alt", "opt", "par", "critical", "break" or "rect".
        public string block = "";
        public Paint? block_fill;
        // Autonumber.
        public int number_start = 1;
        public int number_step = 1;
        public bool numbers_visible = true;
    }

    public class SequenceDiagram : Diagram {
        public override string kind {
            get { return "sequence"; }
        }

        internal const double ACTOR_WIDTH = 150;
        internal const double ACTOR_HEIGHT = 65;
        internal const double ACTOR_MARGIN = 50;
        internal const double BOX_MARGIN = 10;
        internal const double BOX_TEXT_MARGIN = 5;
        internal const double NOTE_MARGIN = 10;
        internal const double MESSAGE_MARGIN = 35;
        internal const double ACTIVATION_WIDTH = 10;
        internal const double WRAP_PADDING = 10;
        internal const double LABEL_BOX_WIDTH = 50;
        internal const double LABEL_BOX_HEIGHT = 20;
        internal const double DIAGRAM_MARGIN_X = 50;
        internal const double DIAGRAM_MARGIN_Y = 10;

        internal Dagre.Dict<SeqActor> actors = new Dagre.Dict<SeqActor> ();
        internal GenericArray<SeqActor> order = new GenericArray<SeqActor> ();
        internal GenericArray<SeqEvent> events = new GenericArray<SeqEvent> ();
        internal GenericArray<SeqBox> boxes = new GenericArray<SeqBox> ();

        internal SeqActor actor (string id) {
            var a = actors[id];
            if (a == null) {
                a = new SeqActor ();
                a.id = id;
                a.label = id;
                a.index = order.length;
                actors[id] = a;
                order.add (a);
            }
            return a;
        }

        // Layout state.
        TextMeasurer m;
        Scene scene;
        TextStyle message_style = TextStyle (16);
        TextStyle actor_style = TextStyle (16);
        TextStyle note_style = TextStyle (14);

        class Activation {
            public SeqActor actor;
            public double start_y;
            public int depth;
        }

        class Frame {
            public string block;
            public Paint? fill;
            public double start_y;
            public double min_x = double.INFINITY;
            public double max_x = -double.INFINITY;
            /* The y and text of each section: the first, then each else/and/option. */
            public GenericArray<double?> section_y = new GenericArray<double?> ();
            public GenericArray<string> section_text = new GenericArray<string> ();
            public int depth;
        }

        GenericArray<Activation> activations;
        GenericArray<Frame> frames;
        /* Items drawn behind everything else: rect blocks and boxes. */
        GenericArray<Item> background;

        double label_width (string markup, TextStyle style) {
            return measure (m, markup, style).width;
        }

        double center (SeqActor a) {
            return a.x + a.width / 2;
        }

        int active_depth (SeqActor a) {
            int depth = 0;
            foreach (var act in activations) {
                if (act.actor == a) {
                    depth++;
                }
            }
            return depth;
        }

        /* Where a message line meets an actor's lifeline or activation bar. */
        double attach_x (SeqActor a, bool from_left) {
            int depth = active_depth (a);
            double c = center (a);
            if (depth == 0) {
                return c;
            }
            double offset = (depth - 1) * ACTIVATION_WIDTH / 2;
            return from_left ? c + offset - ACTIVATION_WIDTH / 2 : c + offset + ACTIVATION_WIDTH / 2;
        }

        void widen_frames (double x0, double x1) {
            foreach (var f in frames) {
                f.min_x = double.min (f.min_x, x0);
                f.max_x = double.max (f.max_x, x1);
            }
        }

        /* Sets the actors' widths and positions, making room for the messages. */
        void place_actors () {
            foreach (var a in order) {
                double w = label_width (a.label, actor_style) + 2 * WRAP_PADDING;
                a.width = double.max (ACTOR_WIDTH, w);
                a.margin = ACTOR_MARGIN;
            }
            // Messages and notes between neighbors need room for their text.
            foreach (var e in events) {
                if (e.kind == SeqKind.MESSAGE && e.from != e.to) {
                    var a = e.from.index < e.to.index ? e.from : e.to;
                    var b = e.from.index < e.to.index ? e.to : e.from;
                    double needed = label_width (e.text, message_style) + 2 * WRAP_PADDING;
                    require_span (a, b, needed);
                } else if (e.kind == SeqKind.MESSAGE) {
                    double needed = label_width (e.text, message_style) / 2 + 60;
                    var next = e.from.index + 1 < order.length ? order[e.from.index + 1] : null;
                    if (next != null) {
                        require_span (e.from, next, needed + next.width / 2);
                    }
                } else if (e.kind == SeqKind.NOTE) {
                    double w = label_width (e.text, note_style) + 2 * NOTE_MARGIN;
                    if (e.placement == "right") {
                        var next = e.from.index + 1 < order.length ? order[e.from.index + 1] : null;
                        if (next != null) {
                            require_span (e.from, next, w + next.width / 2 + 2 * NOTE_MARGIN);
                        }
                    } else if (e.placement == "left") {
                        var prev = e.from.index > 0 ? order[e.from.index - 1] : null;
                        if (prev != null) {
                            require_span (prev, e.from, w + prev.width / 2 + 2 * NOTE_MARGIN);
                        }
                    } else if (e.to != null && e.to != e.from) {
                        var a = e.from.index < e.to.index ? e.from : e.to;
                        var b = e.from.index < e.to.index ? e.to : e.from;
                        require_span (a, b, w - a.width / 2 - b.width / 2 + 2 * NOTE_MARGIN);
                    }
                }
            }
            double x = 0;
            foreach (var a in order) {
                a.x = x;
                x += a.width + a.margin;
            }
        }

        /* Makes the distance between the centers of a and b at least `needed`. */
        void require_span (SeqActor a, SeqActor b, double needed) {
            double span = 0;
            for (int i = a.index; i < b.index; i++) {
                span += order[i].width / 2 + order[i].margin + order[i + 1].width / 2;
            }
            if (span < needed) {
                order[b.index - 1].margin += needed - span;
            }
        }

        void draw_actor (SeqActor a, double top, bool bottom) {
            double cx = center (a);
            if (a.stick_figure) {
                var p = new Path ();
                double head = 8;
                double y0 = top + 4;
                p.ellipse (cx, y0 + head, head, head);
                scene.add_shape (p, Paint (Ink.NODE_FILL), Paint (Ink.NODE_STROKE), 2);
                var body = new Path ();
                body.move_to (cx, y0 + 2 * head);
                body.line_to (cx, y0 + 2 * head + 18);
                body.move_to (cx - 14, y0 + 2 * head + 6);
                body.line_to (cx + 14, y0 + 2 * head + 6);
                body.move_to (cx - 12, y0 + 2 * head + 32);
                body.line_to (cx, y0 + 2 * head + 18);
                body.line_to (cx + 12, y0 + 2 * head + 32);
                scene.add_shape (body, Paint (Ink.NONE), Paint (Ink.NODE_STROKE), 2);
                scene.add_text (a.label, cx, top + ACTOR_HEIGHT - 4, actor_style);
            } else {
                var box = new Path ();
                box.rounded_rect (a.x, top, a.width, ACTOR_HEIGHT, 3);
                scene.add_shape (box, Paint (Ink.NODE_FILL), Paint (Ink.NODE_STROKE));
                scene.add_text (a.label, cx, top + ACTOR_HEIGHT / 2, actor_style);
            }
        }

        internal override Scene build (TextMeasurer measurer) {
            m = measurer;
            scene = new Scene ();
            activations = new GenericArray<Activation> ();
            frames = new GenericArray<Frame> ();
            background = new GenericArray<Item> ();
            place_actors ();

            double box_top = boxes.length > 0 ? 25 : 0;
            double y = box_top + ACTOR_HEIGHT;
            var lifeline_start = new HashTable<string, double?> (str_hash, str_equal);
            var lifeline_end = new HashTable<string, double?> (str_hash, str_equal);
            var created_at = new HashTable<string, double?> (str_hash, str_equal);
            foreach (var a in order) {
                if (!a.created) {
                    lifeline_start[a.id] = y;
                }
            }

            var items_before = scene.items.length;
            int number = 1, step = 1;
            bool numbering = false;
            double max_right = 0;
            foreach (var a in order) {
                max_right = double.max (max_right, a.x + a.width);
            }

            foreach (var e in events) {
                switch (e.kind) {
                case SeqKind.AUTONUMBER:
                    numbering = e.numbers_visible;
                    if (e.numbers_visible) {
                        number = e.number_start;
                        step = e.number_step;
                    }
                    break;
                case SeqKind.CREATE:
                    // The actor box is drawn where its first message arrives.
                    y += BOX_MARGIN;
                    created_at[e.from.id] = y;
                    draw_actor (e.from, y, false);
                    y += ACTOR_HEIGHT;
                    lifeline_start[e.from.id] = y;
                    break;
                case SeqKind.DESTROY:
                    lifeline_end[e.from.id] = y;
                    var cross = new Path ();
                    double cx = center (e.from);
                    cross.move_to (cx - 9, y - 9);
                    cross.line_to (cx + 9, y + 9);
                    cross.move_to (cx + 9, y - 9);
                    cross.line_to (cx - 9, y + 9);
                    scene.add_shape (cross, Paint (Ink.NONE), Paint (Ink.LINE), 2);
                    y += 12;
                    break;
                case SeqKind.MESSAGE:
                    y = draw_message (e, y, numbering ? number : -1);
                    if (numbering) {
                        number += step;
                    }
                    if (e.activate_target) {
                        var act = new Activation ();
                        act.actor = e.to;
                        act.start_y = y - 8;
                        act.depth = active_depth (e.to);
                        activations.add (act);
                    }
                    if (e.deactivate_source) {
                        end_activation (e.from, y - 8);
                    }
                    break;
                case SeqKind.ACTIVATE:
                    var act = new Activation ();
                    act.actor = e.from;
                    act.start_y = y - 8;
                    act.depth = active_depth (e.from);
                    activations.add (act);
                    break;
                case SeqKind.DEACTIVATE:
                    end_activation (e.from, y - 8);
                    break;
                case SeqKind.NOTE:
                    y = draw_note (e, y);
                    break;
                case SeqKind.BLOCK_START:
                    var f = new Frame ();
                    f.block = e.block;
                    f.fill = e.block_fill;
                    f.depth = frames.length;
                    y += BOX_MARGIN;
                    f.start_y = y;
                    f.section_y.add (y);
                    f.section_text.add (e.text);
                    frames.add (f);
                    if (e.block != "rect") {
                        double th = e.text != "" ? measure (m, e.text, message_style).height : 0;
                        y += double.max (LABEL_BOX_HEIGHT, th) + BOX_MARGIN;
                    }
                    break;
                case SeqKind.BLOCK_SECTION:
                    if (frames.length > 0) {
                        var f = frames[frames.length - 1];
                        y += BOX_MARGIN;
                        f.section_y.add (y);
                        f.section_text.add (e.text);
                        double th = e.text != "" ? measure (m, e.text, message_style).height : 0;
                        y += double.max (LABEL_BOX_HEIGHT * 0.5, th) + BOX_MARGIN;
                    }
                    break;
                case SeqKind.BLOCK_END:
                    if (frames.length > 0) {
                        var f = frames[frames.length - 1];
                        frames.remove_index (frames.length - 1);
                        y += BOX_MARGIN;
                        draw_frame (f, y);
                        // The enclosing frames grow around this one.
                        widen_frames (f.min_x - BOX_MARGIN, f.max_x + BOX_MARGIN);
                    }
                    break;
                }
            }
            foreach (var act in activations) {
                draw_activation (act, y);
            }
            activations = new GenericArray<Activation> ();

            y += BOX_MARGIN * 2;
            // Lifelines, behind the messages.
            var lines = new GenericArray<Item> ();
            foreach (var a in order) {
                double? start = lifeline_start[a.id];
                double? end = lifeline_end[a.id];
                if (start == null) {
                    continue;
                }
                var p = new Path ();
                p.move_to (center (a), start);
                p.line_to (center (a), end ?? y);
                var s = new Shape (p, Paint (Ink.NONE), Paint (Ink.GROUP_STROKE), 1);
                lines.add (s);
            }
            // Mirrored actors at the bottom.
            foreach (var a in order) {
                if (lifeline_end[a.id] == null) {
                    draw_actor (a, y, true);
                }
            }
            double height = y + ACTOR_HEIGHT;

            // Assemble: backgrounds, lifelines, top actors, then the rest.
            var rest = new GenericArray<Item> ();
            for (int i = items_before; i < scene.items.length; i++) {
                rest.add (scene.items[i]);
            }
            scene.items = new GenericArray<Item> ();
            foreach (var box in boxes) {
                draw_box (box, box_top, height);
            }
            foreach (var item in background) {
                scene.add (item);
            }
            foreach (var item in lines) {
                scene.add (item);
            }
            foreach (var a in order) {
                if (!a.created) {
                    draw_actor (a, box_top, false);
                }
            }
            foreach (var item in rest) {
                scene.add (item);
            }

            // Fit the scene around everything, with Mermaid's margins.
            double min_x = 0, max_x = max_right;
            foreach (var item in scene.items) {
                if (item is Shape) {
                    var c = ((Shape) item).path.coords;
                    for (int i = 0; i + 1 < c.length; i += 2) {
                        min_x = double.min (min_x, c[i]);
                        max_x = double.max (max_x, c[i]);
                    }
                }
            }
            scene.translate (-min_x + DIAGRAM_MARGIN_X / 2, DIAGRAM_MARGIN_Y);
            scene.width = max_x - min_x + DIAGRAM_MARGIN_X;
            scene.height = height + 2 * DIAGRAM_MARGIN_Y;
            return scene;
        }

        void end_activation (SeqActor a, double y) {
            for (int i = activations.length - 1; i >= 0; i--) {
                if (activations[i].actor == a) {
                    draw_activation (activations[i], y);
                    activations.remove_index (i);
                    return;
                }
            }
        }

        void draw_activation (Activation act, double end_y) {
            double cx = center (act.actor) + act.depth * ACTIVATION_WIDTH / 2;
            var p = new Path ();
            p.rect (cx - ACTIVATION_WIDTH / 2, act.start_y, ACTIVATION_WIDTH, double.max (end_y - act.start_y, 6));
            background.add (new Shape (p, Paint (Ink.ACCENT_FILL), Paint (Ink.NODE_STROKE)));
        }

        double draw_message (SeqEvent e, double y, int number) {
            var size = e.text != "" ? measure (m, e.text, message_style) : Size () { width = 0, height = 0 };
            double text_y = y + MESSAGE_MARGIN / 2 + size.height / 2;
            double line_y = y + MESSAGE_MARGIN / 2 + size.height + 8;
            var stroke = Paint (Ink.LINE);

            if (e.from == e.to) {
                // A loop back to the same lifeline.
                double x = attach_x (e.from, false);
                var p = new Path ();
                p.move_to (x, line_y);
                p.curve_to (x + 60, line_y - 10, x + 60, line_y + 30, x, line_y + 20);
                var s = scene.add_shape (p, Paint (Ink.NONE), stroke, 1.5);
                if (e.dotted) {
                    s.line_style = LineStyle.DOTTED;
                }
                if (e.text != "") {
                    scene.add_text (e.text, x + 30 + size.width / 2 - 20, text_y, message_style, Align.CENTER);
                }
                draw_head (e.head, x, line_y + 20, x + 20, line_y + 23);
                widen_frames (x, x + 60 + size.width / 2);
                if (number >= 0) {
                    draw_number (number, x, line_y);
                }
                return line_y + 30;
            }

            bool right = e.to.index > e.from.index;
            double x1 = attach_x (e.from, !right);
            double x2 = attach_x (e.to, right);
            if (!right) {
                x1 = attach_x (e.from, false);
                x2 = attach_x (e.to, true);
            }
            double dir = x2 > x1 ? 1 : -1;
            double inset_end = marker_inset (e.head), inset_start = marker_inset (e.tail);
            var line = new Path ();
            line.move_to (x1 + dir * inset_start, line_y);
            line.line_to (x2 - dir * inset_end, line_y);
            var s = scene.add_shape (line, Paint (Ink.NONE), stroke, 1.5);
            if (e.dotted) {
                s.line_style = LineStyle.DOTTED;
            }
            if (e.text != "") {
                scene.add_text (e.text, (x1 + x2) / 2, text_y, message_style);
            }
            draw_head (e.head, x2, line_y, x1, line_y);
            draw_head (e.tail, x1, line_y, x2, line_y);
            if (number >= 0) {
                draw_number (number, x1, line_y);
            }
            widen_frames (double.min (x1, x2), double.max (x1, x2));
            return line_y;
        }

        static double marker_inset (Marker m) {
            switch (m) {
            case Marker.ARROW:
                return 6;
            case Marker.CROSS:
                return 0;
            default:
                return 0;
            }
        }

        /* An arrowhead with its tip at (x, y), for a line coming from (fx, fy). */
        void draw_head (Marker marker, double x, double y, double fx, double fy) {
            if (marker == Marker.NONE) {
                return;
            }
            double dx = x - fx, dy = y - fy;
            double d = Math.sqrt (dx * dx + dy * dy);
            if (d < 1e-6) {
                return;
            }
            double ux = dx / d, uy = dy / d, nx = -uy, ny = ux;
            var p = new Path ();
            var stroke = Paint (Ink.LINE);
            switch (marker) {
            case Marker.ARROW:
                p.polygon ({ x, y, x - ux * 10 + nx * 5, y - uy * 10 + ny * 5, x - ux * 10 - nx * 5, y - uy * 10 - ny * 5 });
                scene.add_shape (p, stroke, stroke, 1);
                break;
            case Marker.DEPENDENCY:
                p.move_to (x - ux * 9 + nx * 5, y - uy * 9 + ny * 5);
                p.line_to (x, y);
                p.line_to (x - ux * 9 - nx * 5, y - uy * 9 - ny * 5);
                scene.add_shape (p, Paint (Ink.NONE), stroke, 1.5);
                break;
            case Marker.CROSS:
                double cx = x - ux * 6, cy = y - uy * 6;
                p.move_to (cx - 5, cy - 5);
                p.line_to (cx + 5, cy + 5);
                p.move_to (cx + 5, cy - 5);
                p.line_to (cx - 5, cy + 5);
                scene.add_shape (p, Paint (Ink.NONE), stroke, 2);
                break;
            default:
                break;
            }
        }

        void draw_number (int number, double x, double y) {
            var p = new Path ();
            p.ellipse (x, y, 9, 9);
            scene.add_shape (p, Paint (Ink.SOLID), Paint (Ink.NONE));
            var t = scene.add_text ("%d".printf (number), x, y, TextStyle (11, true));
            t.color = Paint (Ink.BACKGROUND);
        }

        double draw_note (SeqEvent e, double y) {
            var size = measure (m, e.text, note_style);
            double w = size.width + 2 * NOTE_MARGIN;
            double h = size.height + 2 * NOTE_MARGIN;
            double x;
            double c = center (e.from);
            switch (e.placement) {
            case "left":
                w = double.max (w, ACTOR_WIDTH * 0.66);
                x = c - w - NOTE_MARGIN * 2.5;
                break;
            case "right":
                w = double.max (w, ACTOR_WIDTH * 0.66);
                x = c + NOTE_MARGIN * 2.5;
                break;
            default:
                if (e.to != null && e.to != e.from) {
                    double c2 = center (e.to);
                    double l = double.min (c, c2), r = double.max (c, c2);
                    double span = r - l + ACTOR_WIDTH * 0.5;
                    w = double.max (w, span);
                    x = (l + r) / 2 - w / 2;
                } else {
                    w = double.max (w, ACTOR_WIDTH * 0.75);
                    x = c - w / 2;
                }
                break;
            }
            y += BOX_MARGIN;
            var p = new Path ();
            p.rect (x, y, w, h);
            scene.add_shape (p, Paint (Ink.NOTE_FILL), Paint (Ink.NOTE_STROKE));
            scene.add_text (e.text, x + w / 2, y + h / 2, note_style);
            widen_frames (x, x + w);
            return y + h;
        }

        void draw_frame (Frame f, double end_y) {
            double pad = BOX_MARGIN * 2;
            if (f.min_x == double.INFINITY) {
                f.min_x = order.length > 0 ? center (order[0]) : 0;
                f.max_x = f.min_x + LABEL_BOX_WIDTH * 2;
            }
            double x0 = f.min_x - pad, x1 = f.max_x + pad;
            f.min_x = x0;
            f.max_x = x1;
            double y0 = f.start_y;

            if (f.block == "rect") {
                var p = new Path ();
                p.rect (x0, y0, x1 - x0, end_y - y0);
                background.add (new Shape (p, f.fill ?? Paint (Ink.GROUP_FILL), Paint (Ink.NONE)));
                return;
            }

            var frame = new Path ();
            frame.rect (x0, y0, x1 - x0, end_y - y0);
            scene.add_shape (frame, Paint (Ink.NONE), Paint (Ink.GROUP_STROKE), 1.5);

            // The tag in the corner: "loop", "alt" and so on.
            var tag_style = TextStyle (14, true);
            double tw = double.max (LABEL_BOX_WIDTH, measure (m, f.block, tag_style).width + 16);
            var tag = new Path ();
            tag.polygon ({ x0, y0, x0 + tw, y0, x0 + tw, y0 + LABEL_BOX_HEIGHT - 6,
                           x0 + tw - 7, y0 + LABEL_BOX_HEIGHT, x0, y0 + LABEL_BOX_HEIGHT });
            scene.add_shape (tag, Paint (Ink.GROUP_FILL), Paint (Ink.GROUP_STROKE), 1.5);
            scene.add_text (Label.escape (f.block), x0 + tw / 2, y0 + LABEL_BOX_HEIGHT / 2, tag_style);

            for (int i = 0; i < f.section_y.length; i++) {
                double sy = f.section_y[i];
                string text = f.section_text[i];
                if (i > 0) {
                    var sep = new Path ();
                    sep.move_to (x0, sy);
                    sep.line_to (x1, sy);
                    var s = scene.add_shape (sep, Paint (Ink.NONE), Paint (Ink.GROUP_STROKE), 1.5);
                    s.line_style = LineStyle.DASHED;
                }
                if (text != "") {
                    var size = measure (m, text, message_style);
                    double ty = i == 0 ? sy + LABEL_BOX_HEIGHT / 2 + 2 : sy + BOX_TEXT_MARGIN + size.height / 2;
                    if (i == 0) {
                        ty = sy + double.max (LABEL_BOX_HEIGHT, size.height) / 2 + BOX_TEXT_MARGIN;
                    }
                    var t = scene.add_text ("[" + text + "]", (x0 + tw + x1) / 2, ty, message_style);
                    t.style.bold = false;
                }
            }
        }

        void draw_box (SeqBox box, double top, double height) {
            if (box.actors.length == 0) {
                return;
            }
            double x0 = double.INFINITY, x1 = -double.INFINITY;
            foreach (var a in box.actors) {
                x0 = double.min (x0, a.x);
                x1 = double.max (x1, a.x + a.width);
            }
            x0 -= BOX_MARGIN;
            x1 += BOX_MARGIN;
            var p = new Path ();
            p.rect (x0, 0, x1 - x0, height);
            scene.add_shape (p, box.fill ?? Paint (Ink.GROUP_FILL), Paint (Ink.GROUP_STROKE));
            if (box.title != "") {
                scene.add_text (box.title, (x0 + x1) / 2, top / 2, message_style);
            }
        }
    }

    namespace SequenceParser {

        struct ArrowType {
            unowned string token;
            bool dotted;
            Marker head;
            Marker tail;
        }

        // Longest first, so that "-->>" isn't read as "-->".
        const ArrowType[] ARROWS = {
            { "<<-->>", true, Marker.ARROW, Marker.ARROW },
            { "<<->>", false, Marker.ARROW, Marker.ARROW },
            { "-->>", true, Marker.ARROW, Marker.NONE },
            { "->>", false, Marker.ARROW, Marker.NONE },
            { "--|\\", true, Marker.ARROW, Marker.NONE },
            { "--|/", true, Marker.ARROW, Marker.NONE },
            { "--\\\\", true, Marker.DEPENDENCY, Marker.NONE },
            { "--//", true, Marker.DEPENDENCY, Marker.NONE },
            { "/|--", true, Marker.NONE, Marker.ARROW },
            { "\\|--", true, Marker.NONE, Marker.ARROW },
            { "//--", true, Marker.NONE, Marker.DEPENDENCY },
            { "\\\\--", true, Marker.NONE, Marker.DEPENDENCY },
            { "-|\\", false, Marker.ARROW, Marker.NONE },
            { "-|/", false, Marker.ARROW, Marker.NONE },
            { "-\\\\", false, Marker.DEPENDENCY, Marker.NONE },
            { "-//", false, Marker.DEPENDENCY, Marker.NONE },
            { "/|-", false, Marker.NONE, Marker.ARROW },
            { "\\|-", false, Marker.NONE, Marker.ARROW },
            { "//-", false, Marker.NONE, Marker.DEPENDENCY },
            { "\\\\-", false, Marker.NONE, Marker.DEPENDENCY },
            { "--x", true, Marker.CROSS, Marker.NONE },
            { "-x", false, Marker.CROSS, Marker.NONE },
            { "--)", true, Marker.DEPENDENCY, Marker.NONE },
            { "-)", false, Marker.DEPENDENCY, Marker.NONE },
            { "-->", true, Marker.NONE, Marker.NONE },
            { "->", false, Marker.NONE, Marker.NONE }
        };

        class Parser {
            public SequenceDiagram d = new SequenceDiagram ();
            Source src;
            GenericArray<string> open_blocks = new GenericArray<string> ();
            SeqBox? box;
            bool create_next;

            public Parser (Source src) {
                this.src = src;
            }

            public void run (int first) throws ParseError {
                for (int i = first + 1; i < src.lines.length; i++) {
                    // ";" separates statements too.
                    foreach (unowned string part in split_statements (src.lines[i])) {
                        string l = part.strip ();
                        if (l == "" || l.has_prefix ("#")) {
                            continue;
                        }
                        if (l.has_prefix ("title:")) {
                            d.title = l.substring (6).strip ();
                            continue;
                        }
                        int k = i;
                        if (common_statement_line (l, ref k)) {
                            i = k;
                            continue;
                        }
                        statement (i, l);
                    }
                }
                if (open_blocks.length > 0) {
                    throw syntax_error (src.lines.length - 1, "A “%s” block is missing its “end”".printf (
                        open_blocks[open_blocks.length - 1]));
                }
                if (box != null) {
                    throw syntax_error (src.lines.length - 1, "A “box” is missing its “end”");
                }
            }

            static string[] split_statements (string line) {
                // Message text can't contain ";", so splitting is safe.
                return line.split (";");
            }

            bool common_statement_line (string l, ref int i) {
                var tmp = new Source ("");
                tmp.lines = { l };
                int k = 0;
                if (l.has_prefix ("accDescr") && l.contains ("{") && !l.contains ("}")) {
                    return common_statement (src, ref i, d);
                }
                return common_statement (tmp, ref k, d);
            }

            static string message_text (string s) {
                string t = s.strip ();
                if (t.has_prefix ("wrap:")) {
                    t = t.substring (5);
                } else if (t.has_prefix ("nowrap:")) {
                    t = t.substring (7);
                }
                return Label.from_text (t.strip ());
            }

            /* "box" and block statements take the rest of the line. */
            static bool keyword (string l, string word, out string rest) {
                rest = "";
                if (l == word) {
                    return true;
                }
                if (l.has_prefix (word + " ") || l.has_prefix (word + "\t")) {
                    rest = l.substring (word.length).strip ();
                    return true;
                }
                return false;
            }

            void statement (int i, string l) throws ParseError {
                string rest;
                if (keyword (l, "participant", out rest) || keyword (l, "actor", out rest)) {
                    participant (i, rest, l.has_prefix ("actor"));
                    return;
                }
                if (keyword (l, "create", out rest)) {
                    create_next = true;
                    string r2;
                    if (keyword (rest, "participant", out r2) || keyword (rest, "actor", out r2)) {
                        participant (i, r2, rest.has_prefix ("actor"));
                    } else {
                        throw syntax_error (i, "Expected “participant” or “actor” after “create”");
                    }
                    return;
                }
                if (keyword (l, "destroy", out rest)) {
                    var ev = new SeqEvent ();
                    ev.kind = SeqKind.DESTROY;
                    ev.from = d.actor (rest);
                    pending_destroy.add (ev);
                    return;
                }
                if (keyword (l, "autonumber", out rest)) {
                    var ev = new SeqEvent ();
                    ev.kind = SeqKind.AUTONUMBER;
                    if (rest == "off") {
                        ev.numbers_visible = false;
                    } else if (rest != "") {
                        string[] nums = rest.split (" ");
                        ev.number_start = int.parse (nums[0]);
                        if (nums.length > 1) {
                            ev.number_step = int.parse (nums[nums.length - 1]);
                        }
                    }
                    d.events.add (ev);
                    return;
                }
                if (keyword (l, "activate", out rest) || keyword (l, "deactivate", out rest)) {
                    var ev = new SeqEvent ();
                    ev.kind = l.has_prefix ("activate") ? SeqKind.ACTIVATE : SeqKind.DEACTIVATE;
                    ev.from = d.actor (rest);
                    d.events.add (ev);
                    return;
                }
                if (keyword (l, "box", out rest)) {
                    if (box != null) {
                        throw syntax_error (i, "Boxes can't be nested");
                    }
                    box = new SeqBox ();
                    // An optional color first, then the title.
                    string[] words = rest.split (" ", 2);
                    uint32 rgba = 0;
                    if (words.length > 0 && words[0] != "" && Css.parse_color (words[0], out rgba)) {
                        if ((rgba & 0xff) != 0) {
                            box.fill = backdrop (rgba);
                        }
                        box.title = words.length > 1 ? Label.from_text (words[1].strip ()) : "";
                    } else if (rest.has_prefix ("rgb")) {
                        int close = rest.index_of_char (')');
                        if (close > 0 && Css.parse_color (rest.substring (0, close + 1), out rgba)) {
                            box.fill = backdrop (rgba);
                        }
                        box.title = Label.from_text (rest.substring (close + 1).strip ());
                    } else {
                        box.title = Label.from_text (rest);
                    }
                    d.boxes.add (box);
                    return;
                }
                foreach (unowned string block in new string[] { "loop", "alt", "opt", "par_over", "par", "critical", "break", "rect" }) {
                    if (keyword (l, block, out rest)) {
                        var ev = new SeqEvent ();
                        ev.kind = SeqKind.BLOCK_START;
                        ev.block = block == "par_over" ? "par" : block;
                        if (block == "rect") {
                            uint32 rgba = 0;
                            if (Css.parse_color (rest, out rgba)) {
                                ev.block_fill = backdrop (rgba);
                            }
                        } else {
                            ev.text = message_text (rest);
                        }
                        d.events.add (ev);
                        open_blocks.add (ev.block);
                        return;
                    }
                }
                foreach (unowned string section in new string[] { "else", "and", "option" }) {
                    if (keyword (l, section, out rest)) {
                        if (open_blocks.length == 0) {
                            throw syntax_error (i, "“%s” outside of a block".printf (section));
                        }
                        var ev = new SeqEvent ();
                        ev.kind = SeqKind.BLOCK_SECTION;
                        ev.text = message_text (rest);
                        d.events.add (ev);
                        return;
                    }
                }
                if (l == "end") {
                    if (open_blocks.length > 0) {
                        open_blocks.remove_index (open_blocks.length - 1);
                        var ev = new SeqEvent ();
                        ev.kind = SeqKind.BLOCK_END;
                        d.events.add (ev);
                    } else if (box != null) {
                        box = null;
                    } else {
                        throw syntax_error (i, "Unexpected “end”");
                    }
                    return;
                }
                if (keyword (l, "note", out rest) || keyword (l, "Note", out rest)) {
                    note (i, rest);
                    return;
                }
                if (keyword (l, "links", out rest) || keyword (l, "link", out rest)
                    || keyword (l, "properties", out rest) || keyword (l, "details", out rest)) {
                    // Actor menus are interactive; they're ignored.
                    return;
                }
                message (i, l);
            }

            GenericArray<SeqEvent> pending_destroy = new GenericArray<SeqEvent> ();

            /*
             * Colors behind text are made translucent, so that the text stays
             * readable in both light and dark styles.
             */
            static Paint backdrop (uint32 rgba) {
                uint32 alpha = (uint32) ((rgba & 0xff) * 0.35);
                return Paint.custom ((rgba & 0xffffff00) | alpha);
            }

            void participant (int i, string rest, bool stick) throws ParseError {
                string id = rest;
                string? alias = null;
                int as_pos = find_as (rest);
                if (as_pos >= 0) {
                    id = rest.substring (0, as_pos).strip ();
                    alias = rest.substring (as_pos + 4).strip ();
                }
                int config = id.index_of ("@{");
                if (config >= 0) {
                    id = id.substring (0, config).strip ();
                }
                if (id == "") {
                    throw syntax_error (i, "Expected a participant name");
                }
                bool is_new = d.actors[id] == null;
                var a = d.actor (id);
                a.stick_figure = stick;
                if (alias != null) {
                    a.label = Label.from_text (alias);
                } else if (is_new) {
                    a.label = Label.from_text (id);
                }
                if (box != null && is_new) {
                    box.actors.add (a);
                    a.box = box;
                }
                if (create_next) {
                    create_next = false;
                    a.created = true;
                    var ev = new SeqEvent ();
                    ev.kind = SeqKind.CREATE;
                    ev.from = a;
                    pending_create = ev;
                }
            }

            SeqEvent? pending_create;

            static int find_as (string s) {
                int k = s.index_of (" as ");
                return k;
            }

            void note (int i, string rest) throws ParseError {
                var ev = new SeqEvent ();
                ev.kind = SeqKind.NOTE;
                string r = rest;
                if (r.has_prefix ("left of ")) {
                    ev.placement = "left";
                    r = r.substring (8);
                } else if (r.has_prefix ("right of ")) {
                    ev.placement = "right";
                    r = r.substring (9);
                } else if (r.has_prefix ("over ")) {
                    ev.placement = "over";
                    r = r.substring (5);
                } else {
                    throw syntax_error (i, "Expected “left of”, “right of” or “over” after “note”");
                }
                int colon = r.index_of_char (':');
                if (colon < 0) {
                    throw syntax_error (i, "Expected “:” and the note's text");
                }
                string who = r.substring (0, colon).strip ();
                ev.text = message_text (r.substring (colon + 1));
                string[] names = who.split (",");
                ev.from = d.actor (names[0].strip ());
                if (names.length > 1) {
                    ev.to = d.actor (names[1].strip ());
                }
                d.events.add (ev);
            }

            void message (int i, string l) throws ParseError {
                // Find the arrow: the first position where one of the tokens matches.
                int at = -1;
                ArrowType arrow = ARROWS[0];
                for (int p = 0; p < l.length && at < 0; p++) {
                    foreach (var a in ARROWS) {
                        if (l.length - p >= a.token.length && l.substring (p, a.token.length) == a.token) {
                            at = p;
                            arrow = a;
                            break;
                        }
                    }
                }
                if (at <= 0) {
                    throw syntax_error (i, "Unexpected “%s”".printf (l));
                }
                string from = l.substring (0, at).strip ();
                string rest = l.substring (at + arrow.token.length);
                int colon = rest.index_of_char (':');
                string to = (colon >= 0 ? rest.substring (0, colon) : rest).strip ();
                string text = colon >= 0 ? rest.substring (colon + 1) : "";

                var ev = new SeqEvent ();
                ev.kind = SeqKind.MESSAGE;
                if (to.has_prefix ("+")) {
                    ev.activate_target = true;
                    to = to.substring (1).strip ();
                } else if (to.has_prefix ("-")) {
                    ev.deactivate_source = true;
                    to = to.substring (1).strip ();
                }
                if (from == "" || to == "") {
                    throw syntax_error (i, "A message needs a participant on both sides of the arrow");
                }
                bool to_known = d.actors[to] != null;
                ev.from = d.actor (from);
                ev.to = d.actor (to);
                ev.dotted = arrow.dotted;
                ev.head = arrow.head;
                ev.tail = arrow.tail;
                ev.text = message_text (text);
                if (pending_create != null && (pending_create.from == ev.to || pending_create.from == ev.from)) {
                    d.events.add (pending_create);
                    pending_create = null;
                } else if (!to_known) {
                    // A participant first named in a message.
                }
                d.events.add (ev);
                // "destroy X" takes effect after X's next message.
                for (int k = pending_destroy.length - 1; k >= 0; k--) {
                    var de = pending_destroy[k];
                    if (de.from == ev.from || de.from == ev.to) {
                        d.events.add (de);
                        pending_destroy.remove_index (k);
                    }
                }
            }
        }

        internal SequenceDiagram parse (Source src, int first) throws ParseError {
            var p = new Parser (src);
            p.run (first);
            return p.d;
        }
    }
}
