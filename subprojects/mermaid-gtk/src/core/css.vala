/* SPDX-License-Identifier: GPL-3.0-or-later */

namespace Mermaid {

    /* The CSS properties that diagrams can set with style statements. */
    internal class CssStyle {
        public Paint? fill;
        public Paint? stroke;
        public Paint? color;
        public double stroke_width = -1;
        public bool dashed;
        public bool bold;
        public bool italic;

        /* Applies "fill:#f9f,stroke:#333" style declarations. */
        public void apply (string declarations) {
            foreach (unowned string decl in split_declarations (declarations)) {
                int colon = decl.index_of_char (':');
                if (colon < 0) {
                    continue;
                }
                string name = decl.substring (0, colon).strip ().down ();
                string value = decl.substring (colon + 1).strip ().replace ("!important", "").strip ();
                uint32 rgba;
                switch (name) {
                case "fill":
                case "background":
                case "background-color":
                    if (Css.parse_color (value, out rgba)) {
                        fill = Paint.custom (rgba);
                    }
                    break;
                case "stroke":
                case "border-color":
                    if (Css.parse_color (value, out rgba)) {
                        stroke = Paint.custom (rgba);
                    }
                    break;
                case "color":
                    if (Css.parse_color (value, out rgba)) {
                        color = Paint.custom (rgba);
                    }
                    break;
                case "stroke-width":
                    double w;
                    if (double.try_parse (value.replace ("px", "").strip (), out w)) {
                        stroke_width = w;
                    }
                    break;
                case "stroke-dasharray":
                    dashed = value != "0" && value != "none";
                    break;
                case "font-weight":
                    bold = value == "bold" || int.parse (value) >= 600;
                    break;
                case "font-style":
                    italic = value == "italic";
                    break;
                }
            }
        }

        public void merge (CssStyle other) {
            if (other.fill != null) {
                fill = other.fill;
            }
            if (other.stroke != null) {
                stroke = other.stroke;
            }
            if (other.color != null) {
                color = other.color;
            }
            if (other.stroke_width >= 0) {
                stroke_width = other.stroke_width;
            }
            dashed = dashed || other.dashed;
            bold = bold || other.bold;
            italic = italic || other.italic;
        }

        /* Splits at commas and semicolons, but not inside parentheses or after "\". */
        static string[] split_declarations (string s) {
            string[] result = {};
            var sb = new StringBuilder ();
            int depth = 0;
            for (int i = 0; i < s.length; i++) {
                char c = s[i];
                if (c == '\\' && i + 1 < s.length && s[i + 1] == ',') {
                    sb.append_c (',');
                    i++;
                } else if (c == '(') {
                    depth++;
                    sb.append_c (c);
                } else if (c == ')') {
                    depth--;
                    sb.append_c (c);
                } else if ((c == ',' || c == ';') && depth <= 0) {
                    result += sb.str;
                    sb.truncate ();
                } else {
                    sb.append_c (c);
                }
            }
            if (sb.len > 0) {
                result += sb.str;
            }
            return result;
        }
    }

    namespace Css {

        struct Named {
            unowned string name;
            uint32 rgb;
        }

        const Named[] NAMED = {
            { "black", 0x000000 }, { "white", 0xffffff }, { "red", 0xff0000 }, { "green", 0x008000 },
            { "blue", 0x0000ff }, { "yellow", 0xffff00 }, { "orange", 0xffa500 }, { "purple", 0x800080 },
            { "pink", 0xffc0cb }, { "brown", 0xa52a2a }, { "gray", 0x808080 }, { "grey", 0x808080 },
            { "cyan", 0x00ffff }, { "aqua", 0x00ffff }, { "magenta", 0xff00ff }, { "fuchsia", 0xff00ff },
            { "lime", 0x00ff00 }, { "navy", 0x000080 }, { "teal", 0x008080 }, { "olive", 0x808000 },
            { "maroon", 0x800000 }, { "silver", 0xc0c0c0 }, { "gold", 0xffd700 }, { "indigo", 0x4b0082 },
            { "violet", 0xee82ee }, { "coral", 0xff7f50 }, { "salmon", 0xfa8072 }, { "tomato", 0xff6347 },
            { "crimson", 0xdc143c }, { "khaki", 0xf0e68c }, { "lavender", 0xe6e6fa }, { "beige", 0xf5f5dc },
            { "ivory", 0xfffff0 }, { "tan", 0xd2b48c }, { "orchid", 0xda70d6 }, { "plum", 0xdda0dd },
            { "turquoise", 0x40e0d0 }, { "skyblue", 0x87ceeb }, { "steelblue", 0x4682b4 },
            { "royalblue", 0x4169e1 }, { "lightblue", 0xadd8e6 }, { "lightgreen", 0x90ee90 },
            { "lightgray", 0xd3d3d3 }, { "lightgrey", 0xd3d3d3 }, { "lightyellow", 0xffffe0 },
            { "lightpink", 0xffb6c1 }, { "darkblue", 0x00008b }, { "darkgreen", 0x006400 },
            { "darkred", 0x8b0000 }, { "darkgray", 0xa9a9a9 }, { "darkgrey", 0xa9a9a9 },
            { "darkorange", 0xff8c00 }, { "darkviolet", 0x9400d3 }, { "forestgreen", 0x228b22 },
            { "seagreen", 0x2e8b57 }, { "limegreen", 0x32cd32 }, { "dodgerblue", 0x1e90ff },
            { "deepskyblue", 0x00bfff }, { "slategray", 0x708090 }, { "whitesmoke", 0xf5f5f5 },
            { "gainsboro", 0xdcdcdc }, { "chocolate", 0xd2691e }, { "firebrick", 0xb22222 },
            { "hotpink", 0xff69b4 }, { "deeppink", 0xff1493 }, { "mintcream", 0xf5fffa },
            { "honeydew", 0xf0fff0 }, { "aliceblue", 0xf0f8ff }, { "azure", 0xf0ffff },
            { "wheat", 0xf5deb3 }, { "peru", 0xcd853f }, { "sienna", 0xa0522d }
        };

        /* Parses a CSS color into 0xRRGGBBAA. */
        internal bool parse_color (string value, out uint32 rgba) {
            string v = value.strip ().down ();
            rgba = 0;
            if (v == "transparent" || v == "none") {
                rgba = 0;
                return true;
            }
            if (v.has_prefix ("#")) {
                string hex = v.substring (1);
                foreach (char c in hex.to_utf8 ()) {
                    if (!c.isxdigit ()) {
                        return false;
                    }
                }
                switch (hex.length) {
                case 3:
                case 4: {
                    var sb = new StringBuilder ();
                    foreach (char c in hex.to_utf8 ()) {
                        sb.append_c (c);
                        sb.append_c (c);
                    }
                    hex = sb.str;
                    break;
                }
                case 6:
                case 8:
                    break;
                default:
                    return false;
                }
                if (hex.length == 6) {
                    hex += "ff";
                }
                rgba = (uint32) ulong.parse (hex, 16);
                return true;
            }
            if (v.has_prefix ("rgb")) {
                int open = v.index_of_char ('('), close = v.index_of_char (')');
                if (open < 0 || close < open) {
                    return false;
                }
                string[] parts = v.substring (open + 1, close - open - 1).replace ("/", ",").replace (" ", ",").split (",");
                double[] n = {};
                foreach (unowned string p in parts) {
                    string t = p.strip ();
                    if (t == "") {
                        continue;
                    }
                    double d;
                    bool percent = t.has_suffix ("%");
                    if (!double.try_parse (percent ? t.substring (0, t.length - 1) : t, out d)) {
                        return false;
                    }
                    n += percent ? d * (n.length < 3 ? 2.55 : 0.01) : d;
                }
                if (n.length < 3) {
                    return false;
                }
                double a = n.length > 3 ? n[3] : 1;
                rgba = ((uint32) clamp_byte (n[0]) << 24) | ((uint32) clamp_byte (n[1]) << 16)
                    | ((uint32) clamp_byte (n[2]) << 8) | (uint32) clamp_byte (a * 255);
                return true;
            }
            foreach (var named in NAMED) {
                if (named.name == v) {
                    rgba = (named.rgb << 8) | 0xff;
                    return true;
                }
            }
            return false;
        }

        int clamp_byte (double d) {
            return (int) Math.round (double.max (0, double.min (255, d)));
        }
    }
}
