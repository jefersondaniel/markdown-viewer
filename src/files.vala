/* Small helpers for Markdown files on disk. */

namespace Notes.Files {

    public bool is_markdown_name (string name) {
        string low = name.down ();
        return low.has_suffix (".md") || low.has_suffix (".markdown") || low.has_suffix (".mdown")
            || low.has_suffix (".mkd");
    }

    public string stem_of (string name) {
        int dot = name.last_index_of_char ('.');
        return dot > 0 ? name.substring (0, dot) : name;
    }

    public string ext_of (string name) {
        int dot = name.last_index_of_char ('.');
        return dot > 0 ? name.substring (dot) : ".md";
    }

    /* "Untitled", "Untitled 2", ...: names given to new notes. */
    public bool is_untitled (string stem) {
        string base_name = _("Untitled");
        if (stem == base_name) {
            return true;
        }
        if (!stem.has_prefix (base_name + " ")) {
            return false;
        }
        string rest = stem.substring (base_name.length + 1);
        for (int k = 0; k < rest.length; k++) {
            if (!rest[k].isdigit ()) {
                return false;
            }
        }
        return rest.length > 0;
    }

    /* Makes `name` safe to use as a file name. */
    public string sanitize_name (string name) {
        var sb = new StringBuilder ();
        int idx = 0;
        unichar ch;
        while (name.get_next_char (ref idx, out ch)) {
            if ("/\\:*?\"<>|".index_of_char (ch) >= 0 || ch < 32) {
                sb.append_c ('-');
            } else {
                sb.append_unichar (ch);
            }
        }
        string s = sb.str.strip ();
        while (s.has_prefix (".")) {
            s = s.substring (1);
        }
        if (s.char_count () > 80) {
            s = s.substring (0, s.index_of_nth_char (80)).strip ();
        }
        return s;
    }

    /* The first meaningful line of a document, without Markdown syntax. */
    public string derive_title (string text, string fallback) {
        string[] lines = text.split ("\n", 40);
        int k = 0;
        if (lines.length > 0 && lines[0].strip () == "---") {
            for (k = 1; k < lines.length; k++) {
                string l = lines[k].strip ();
                if (l == "---" || l == "...") {
                    k++;
                    break;
                }
            }
            if (k >= lines.length) {
                k = 0;
            }
        }
        for (; k < lines.length; k++) {
            string l = lines[k].strip ();
            if (l == "" || l.has_prefix ("<!--") || l.has_prefix ("```") || l.has_prefix ("---")) {
                continue;
            }
            try {
                l = /<[^>]+>/.replace (l, -1, 0, "");
                l = /^(#{1,6}\s+|>\s*|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+)/.replace (l, -1, 0, "");
                l = /!?\[([^\]]*)\]\([^)]*\)/.replace (l, -1, 0, "\\1");
                l = /[*_`~]/.replace (l, -1, 0, "");
                l = /\s#+$/.replace (l, -1, 0, "");
            } catch (RegexError e) {
            }
            l = l.strip ();
            if (l != "") {
                return l;
            }
        }
        return fallback;
    }

    /* `dir/stem.ext`, or `dir/stem 2.ext` and so on if that already exists. */
    public File unique_child (File dir, string stem, string ext) {
        File f = dir.get_child (stem + ext);
        for (int k = 2; f.query_exists (); k++) {
            f = dir.get_child ("%s %d%s".printf (stem, k, ext));
        }
        return f;
    }

    public string? read_text (File file) {
        try {
            uint8[] data;
            file.load_contents (null, out data, null);
            string text = (string) data;
            return text.validate () ? text : null;
        } catch (Error e) {
            return null;
        }
    }

    /* A path for display, with the home folder shown as "~". */
    public string pretty_path (File? file) {
        if (file == null) {
            return "";
        }
        string path = file.get_path () ?? file.get_uri ();
        string home = Environment.get_home_dir ();
        if (path == home) {
            return "~";
        }
        if (path.has_prefix (home + "/")) {
            path = "~" + path.substring (home.length);
        }
        return path;
    }
}
