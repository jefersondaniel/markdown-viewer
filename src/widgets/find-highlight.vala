/* Highlights the search matches in a rendered note.
 *
 * Changing the text or the attributes of a label makes GTK measure it again,
 * which takes seconds when every paragraph of a long note matches. Like
 * Notes.TextSelection, this layer sits above the labels in an overlay and
 * draws the highlight itself: the background of each match, and the matched
 * text again on top of it, so it reads well in the light and dark styles. */

public class Notes.FindHighlight : Gtk.Widget {
    class Match {
        public Gtk.Label label;
        /* Start and end byte of each match in the label's text. */
        public int[] ranges = {};

        public Match (Gtk.Label label) {
            this.label = label;
        }
    }

    GenericArray<Gtk.Label> labels = new GenericArray<Gtk.Label> ();
    GenericArray<Match> matches = new GenericArray<Match> ();
    Regex? pattern;
    string _query = "";

    /* What to look for, case-insensitively. Empty for nothing. */
    public string query {
        get {
            return _query;
        }
        set {
            if (_query == value) {
                return;
            }
            _query = value;
            pattern = null;
            if (value != "") {
                try {
                    pattern = new Regex (Regex.escape_string (value), RegexCompileFlags.CASELESS);
                } catch (RegexError e) {
                }
            }
            search ();
        }
    }

    /* The number of matches. */
    public int count { get; private set; }

    public FindHighlight (Gtk.Overlay area) {
        can_target = false;
        area.add_overlay (this);
    }

    /* The labels of the note, in reading order. */
    public void set_labels (GenericArray<Gtk.Label>? list) {
        labels = list ?? new GenericArray<Gtk.Label> ();
        search ();
    }

    /* The labels with a match, in reading order. */
    public Gtk.Label? matched_label (int index) {
        return index >= 0 && index < matches.length ? matches[index].label : null;
    }

    public int matched_labels {
        get {
            return (int) matches.length;
        }
    }

    void search () {
        matches = new GenericArray<Match> ();
        int total = 0;
        if (pattern != null) {
            foreach (var label in labels) {
                Match? match = null;
                MatchInfo info;
                if (!pattern.match (label.get_text (), 0, out info)) {
                    continue;
                }
                try {
                    do {
                        int start, end;
                        info.fetch_pos (0, out start, out end);
                        if (end <= start) {
                            break;
                        }
                        if (match == null) {
                            match = new Match (label);
                            matches.add (match);
                        }
                        match.ranges += start;
                        match.ranges += end;
                        total++;
                    } while (info.next ());
                } catch (RegexError e) {
                }
            }
        }
        count = total;
        queue_draw ();
    }

    public override void snapshot (Gtk.Snapshot snapshot) {
        if (matches.length == 0) {
            return;
        }
        var background = Gdk.RGBA () { red = 0xf6 / 255f, green = 0xd3 / 255f, blue = 0x2d / 255f, alpha = 1 };
        var foreground = Gdk.RGBA () { red = 0x1e / 255f, green = 0x1e / 255f, blue = 0x1e / 255f, alpha = 1 };
        foreach (var match in matches) {
            var label = match.label;
            if (!label.is_drawable ()) {
                continue;  // inside a collapsed <details>
            }
            Graphene.Point at;
            if (!label.compute_point (this, Graphene.Point (), out at)) {
                continue;
            }
            int lx, ly;
            label.get_layout_offsets (out lx, out ly);
            var layout = label.get_layout ();
            var region = layout_clip_region (layout, lx, ly, match.ranges, match.ranges.length / 2);
            for (int k = 0; k < region.num_rectangles (); k++) {
                Cairo.RectangleInt r = region.get_rectangle (k);
                var area = Graphene.Rect () {
                    origin = Graphene.Point () { x = at.x + r.x, y = at.y + r.y },
                    size = Graphene.Size () { width = r.width, height = r.height },
                };
                snapshot.append_color (background, area);
                snapshot.push_clip (area);
                snapshot.save ();
                snapshot.translate (Graphene.Point () { x = at.x + lx, y = at.y + ly });
                snapshot.append_layout (layout, foreground);
                snapshot.restore ();
                snapshot.pop ();
            }
        }
    }
}
