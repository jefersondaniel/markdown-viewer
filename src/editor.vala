/* The Markdown source editor: GtkSourceView with a centered text column and a
 * few writing conveniences (list continuation, bold/italic/link shortcuts). */

public class Notes.Editor : GtkSource.View {
    const int COLUMN_WIDTH = 760;

    /* The text zoom, which widens the column along with the text. */
    double _zoom = 1.0;
    public double zoom {
        get { return _zoom; }
        set {
            _zoom = value;
            queue_resize ();
        }
    }

    public GtkSource.Buffer source_buffer {
        get { return (GtkSource.Buffer) buffer; }
    }

    public Editor () {
        Object (buffer: new GtkSource.Buffer (null));

        source_buffer.language = GtkSource.LanguageManager.get_default ().get_language ("markdown");
        source_buffer.highlight_syntax = true;
        source_buffer.highlight_matching_brackets = false;

        wrap_mode = Gtk.WrapMode.WORD_CHAR;
        monospace = true;
        top_margin = 28;
        bottom_margin = 200;
        pixels_below_lines = 3;
        pixels_inside_wrap = 2;
        auto_indent = true;
        insert_spaces_instead_of_tabs = true;
        tab_width = 4;
        smart_home_end = GtkSource.SmartHomeEndType.BEFORE;
        add_css_class ("note-editor");

        var keys = new Gtk.EventControllerKey ();
        keys.propagation_phase = Gtk.PropagationPhase.CAPTURE;
        keys.key_pressed.connect (on_key_pressed);
        add_controller (keys);
    }

    public void set_dark (bool dark) {
        source_buffer.style_scheme = GtkSource.StyleSchemeManager.get_default ()
            .get_scheme (dark ? "Adwaita-dark" : "Adwaita");
    }

    /* Keep the text in a comfortable reading column, centered in the view. */
    public override void size_allocate (int width, int height, int baseline) {
        int margin = int.max (24, (width - (int) (COLUMN_WIDTH * zoom)) / 2);
        if (left_margin != margin) {
            left_margin = margin;
            right_margin = margin;
        }
        base.size_allocate (width, height, baseline);
    }

    bool on_key_pressed (uint keyval, uint keycode, Gdk.ModifierType state) {
        if (!editable) {
            return false;
        }
        var mods = state & Gtk.accelerator_get_default_mod_mask ();
        if (mods == 0 && (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter)) {
            return continue_list ();
        }
        if (mods == Gdk.ModifierType.CONTROL_MASK) {
            switch (keyval) {
            case Gdk.Key.b:
                wrap_selection ("**", "**");
                return true;
            case Gdk.Key.i:
                wrap_selection ("*", "*");
                return true;
            case Gdk.Key.k:
                wrap_selection ("[", "](https://)");
                return true;
            default:
                break;
            }
        }
        return false;
    }

    /* Enter on a list item starts the next item; Enter on an empty item ends the list. */
    bool continue_list () {
        if (buffer.has_selection) {
            return false;
        }
        Gtk.TextIter cursor;
        buffer.get_iter_at_mark (out cursor, buffer.get_insert ());
        Gtk.TextIter line_start = cursor;
        line_start.set_line_offset (0);
        string before = buffer.get_text (line_start, cursor, false);

        MatchInfo mi;
        if (!/^(\s*)([-*+]|\d{1,9}[.)]|>)(\s+)(\[[ xX]\]\s+)?(.*)$/.match (before, 0, out mi)) {
            return false;
        }
        string indent = mi.fetch (1);
        string marker = mi.fetch (2);
        string space = mi.fetch (3);
        string task = mi.fetch (4) ?? "";
        string rest = mi.fetch (5) ?? "";

        buffer.begin_user_action ();
        if (rest.strip () == "") {
            buffer.delete (ref line_start, ref cursor);
        } else {
            if (marker[0].isdigit ()) {
                char delim = marker[marker.length - 1];
                int number = int.parse (marker.substring (0, marker.length - 1));
                marker = "%d%c".printf (number + 1, delim);
            }
            string next = "\n" + indent + marker + space + (task != "" ? "[ ] " : "");
            buffer.insert (ref cursor, next, -1);
        }
        buffer.end_user_action ();
        scroll_mark_onscreen (buffer.get_insert ());
        return true;
    }

    void wrap_selection (string open, string close) {
        Gtk.TextIter start, end;
        buffer.begin_user_action ();
        if (buffer.get_selection_bounds (out start, out end)) {
            string text = buffer.get_text (start, end, false);
            buffer.delete (ref start, ref end);
            buffer.insert (ref start, open + text + close, -1);
        } else {
            buffer.insert_at_cursor (open + close, -1);
            Gtk.TextIter cursor;
            buffer.get_iter_at_mark (out cursor, buffer.get_insert ());
            cursor.backward_chars (close.char_count ());
            buffer.place_cursor (cursor);
        }
        buffer.end_user_action ();
    }
}
