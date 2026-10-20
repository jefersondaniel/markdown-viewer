/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Pie charts. The grammar follows Mermaid 12.2.0's
 * packages/parser/src/language/pie/pie.langium and the layout its
 * src/diagrams/pie/pieRenderer.ts.
 * Copyright (c) 2014-2022 Knut Sveidqvist and Mermaid contributors. MIT License.
 */

namespace Mermaid {

    public class PieDiagram : Diagram {
        public override string kind {
            get { return "pie"; }
        }

        public bool show_data;
        public GenericArray<string> labels = new GenericArray<string> ();
        public GenericArray<double?> values = new GenericArray<double?> ();

        const double HEIGHT = 450;
        const double MARGIN = 40;
        const double LEGEND_RECT_SIZE = 18;
        const double LEGEND_SPACING = 4;
        /* Where the percentages go, as a fraction of the radius. */
        const double TEXT_POSITION = 0.75;

        internal override bool draws_own_title () {
            return true;
        }

        internal override Scene build (TextMeasurer m) {
            var scene = new Scene ();
            double cx = HEIGHT / 2, cy = HEIGHT / 2;
            double radius = HEIGHT / 2 - MARGIN;

            double sum = 0;
            foreach (var v in values) {
                sum += v;
            }

            var outer = new Path ();
            outer.ellipse (cx, cy, radius + 1, radius + 1);
            scene.add_shape (outer, Paint (Ink.NONE), Paint (Ink.LINE), 2);

            // Slices start at the top and go clockwise. Slices under 1% are left out.
            var section_style = TextStyle (17);
            double angle = -Math.PI / 2;
            var percent_labels = new GenericArray<Text> ();
            for (int i = 0; i < values.length && sum > 0; i++) {
                double fraction = values[i] / sum;
                if (fraction * 100 < 1) {
                    continue;
                }
                double a1 = angle + fraction * 2 * Math.PI;
                var slice = new Path ();
                if (fraction >= 0.9999) {
                    slice.ellipse (cx, cy, radius, radius);
                } else {
                    slice.move_to (cx, cy);
                    slice.arc (cx, cy, radius, radius, angle, a1, false);
                    slice.close ();
                }
                scene.add_shape (slice, Paint.palette (i), Paint (Ink.BACKGROUND), 2);

                if (Math.round (fraction * 100) > 0) {
                    double mid = (angle + a1) / 2;
                    var text = new Text ("%.0f%%".printf (fraction * 100),
                                         cx + Math.cos (mid) * radius * TEXT_POSITION,
                                         cy + Math.sin (mid) * radius * TEXT_POSITION, section_style);
                    percent_labels.add (text);
                }
                angle = a1;
            }
            foreach (var text in percent_labels) {
                scene.add (text);
            }

            // The legend, to the right of the chart.
            var legend_style = TextStyle (17);
            double legend_height = LEGEND_RECT_SIZE + LEGEND_SPACING;
            double longest = 0;
            string[] legend_texts = {};
            for (int i = 0; i < labels.length; i++) {
                string text = Label.escape (labels[i]);
                if (show_data) {
                    text += " [%s]".printf (format_number (values[i]));
                }
                legend_texts += text;
                longest = double.max (longest, measure (m, text, legend_style).width);
            }
            double lx = cx + 12 * LEGEND_RECT_SIZE;
            double top = cy - legend_height * labels.length / 2;
            for (int i = 0; i < labels.length; i++) {
                double y = top + i * legend_height;
                var box = new Path ();
                box.rect (lx, y, LEGEND_RECT_SIZE, LEGEND_RECT_SIZE);
                scene.add_shape (box, Paint.palette (i), Paint.palette (i));
                scene.add_text (legend_texts[i], lx + LEGEND_RECT_SIZE + LEGEND_SPACING,
                                y + LEGEND_RECT_SIZE / 2, legend_style, Align.START);
            }

            double width = HEIGHT + MARGIN + LEGEND_RECT_SIZE + LEGEND_SPACING + longest;
            double height = HEIGHT;
            if (title != null && title != "") {
                var title_style = TextStyle (25);
                string markup = Label.escape (title);
                var size = measure (m, markup, title_style);
                scene.add_text (markup, cx, cy - (HEIGHT - 50) / 2, title_style);
                double left = cx - size.width / 2;
                if (left < 0) {
                    scene.translate (-left, 0);
                    width -= left;
                }
                width = double.max (width, cx + size.width / 2);
            }
            scene.width = width;
            scene.height = height;
            return scene;
        }

        /* The shortest form of the number, with "." whatever the locale. */
        static string format_number (double v) {
            char[] buf = new char[double.DTOSTR_BUF_SIZE];
            return v.format (buf, "%.15g");
        }
    }

    namespace PieParser {

        internal PieDiagram parse (Source src, int first) throws ParseError {
            var d = new PieDiagram ();
            string head = src.lines[first].strip ().substring (3).strip ();
            if (head.has_prefix ("showData")) {
                d.show_data = true;
                head = head.substring (8).strip ();
            }
            if (head.has_prefix ("title")) {
                d.title = head.substring (5).strip ();
            } else if (head != "") {
                throw syntax_error (first, "Expected “showData” or “title” after “pie”");
            }

            for (int i = first + 1; i < src.lines.length; i++) {
                string l = src.lines[i].strip ();
                if (l == "" || common_statement (src, ref i, d)) {
                    continue;
                }
                if (l[0] != '"' && l[0] != '\'') {
                    throw syntax_error (i, "Expected a quoted label, like \"Dogs\" : 42");
                }
                char quote = l[0];
                int end = 1;
                while (end < l.length && l[end] != quote) {
                    end += l[end] == '\\' ? 2 : 1;
                }
                if (end >= l.length) {
                    throw syntax_error (i, "The label has no closing quote");
                }
                string label = l.substring (1, end - 1);
                string rest = l.substring (end + 1).strip ();
                if (!rest.has_prefix (":")) {
                    throw syntax_error (i, "Expected “:” after the label");
                }
                rest = rest.substring (1).strip ();
                double value;
                if (!double.try_parse (rest, out value) || rest.has_prefix ("+")) {
                    throw syntax_error (i, "“%s” isn't a number".printf (rest));
                }
                if (value < 0) {
                    throw syntax_error (i, "Pie values must be positive, “%s” isn't".printf (rest));
                }
                // A repeated label keeps its first position and the latest value.
                int index = -1;
                for (int k = 0; k < d.labels.length; k++) {
                    if (d.labels[k] == label) {
                        index = k;
                    }
                }
                if (index >= 0) {
                    d.values[index] = value;
                } else {
                    d.labels.add (label);
                    d.values.add (value);
                }
            }
            return d;
        }
    }
}
