/* Selects text across the blocks of a rendered note.
 *
 * A GtkLabel selects only within itself, and drops its selection as soon as
 * another label takes the primary selection, so a selection can't run from
 * one paragraph into the next. The preview handles selection itself instead:
 * the labels and code views of a note are segments of one text, and this
 * layer, placed above them in an overlay, tracks a range through the segments
 * and draws it. */

/* A run of selectable text in a rendered note: a Gtk.Label or a Gtk.TextView. */
public class Notes.TextSegment : Object {
    public Gtk.Widget widget { get; construct; }

    /* What goes between this segment and the one before it when copied. */
    public string separator { get; set; }

    public TextSegment (Gtk.Widget widget, string separator) {
        Object (widget: widget, separator: separator);
    }

    public string text {
        owned get {
            var label = widget as Gtk.Label;
            return label != null ? label.get_layout ().get_text () : ((Gtk.TextView) widget).buffer.text;
        }
    }
}

public class Notes.TextSelection : Gtk.Widget {
    struct Position {
        int segment;
        int offset;

        public int compare (Position other) {
            return segment != other.segment ? segment - other.segment : offset - other.offset;
        }
    }

    Gtk.Overlay area;
    Gtk.ScrolledWindow scroller;
    GenericArray<TextSegment> segments = new GenericArray<TextSegment> ();
    GenericArray<Gtk.Adjustment> code_adjustments = new GenericArray<Gtk.Adjustment> ();

    /* The selection runs from `anchor`, where it started, to `head`, where it ends now. */
    Position anchor;
    Position head;

    Gtk.GestureDrag drag;
    double drag_x;
    double drag_y;
    bool dragging;

    /* While dragging past the top or bottom edge, the preview scrolls. */
    double pointer_x;
    double pointer_y;
    uint autoscroll_source;

    Gtk.PopoverMenu menu;
    SimpleAction copy_action;

    public TextSelection (Gtk.Overlay area, Gtk.ScrolledWindow scroller) {
        this.area = area;
        this.scroller = scroller;
        can_target = false;
        add_css_class ("text-selection");
        area.add_overlay (this);
        // Takes focus on click so that Ctrl+C and Ctrl+A reach the shortcuts below.
        area.focusable = true;

        var click = new Gtk.GestureClick ();
        click.propagation_phase = Gtk.PropagationPhase.CAPTURE;
        click.pressed.connect ((n, x, y) => on_pressed (click, n, x, y));
        area.add_controller (click);

        drag = new Gtk.GestureDrag ();
        drag.propagation_phase = Gtk.PropagationPhase.CAPTURE;
        drag.drag_begin.connect (on_drag_begin);
        drag.drag_update.connect (on_drag_update);
        drag.drag_end.connect (on_drag_end);
        area.add_controller (drag);

        var secondary = new Gtk.GestureClick ();
        secondary.button = Gdk.BUTTON_SECONDARY;
        secondary.propagation_phase = Gtk.PropagationPhase.CAPTURE;
        secondary.pressed.connect ((n, x, y) => on_menu_pressed (secondary, x, y));
        area.add_controller (secondary);

        var keys = new Gtk.ShortcutController ();
        keys.propagation_phase = Gtk.PropagationPhase.CAPTURE;
        keys.add_shortcut (new Gtk.Shortcut (Gtk.ShortcutTrigger.parse_string ("<Control>c"),
                                             new Gtk.CallbackAction (() => {
            if (!has_selection ()) {
                return false;
            }
            copy ();
            return true;
        })));
        keys.add_shortcut (new Gtk.Shortcut (Gtk.ShortcutTrigger.parse_string ("<Control>a"),
                                             new Gtk.CallbackAction (() => {
            select_all ();
            return true;
        })));
        area.add_controller (keys);

        var actions = new SimpleActionGroup ();
        copy_action = new SimpleAction ("copy", null);
        copy_action.activate.connect (copy);
        actions.add_action (copy_action);
        var select_all_action = new SimpleAction ("select-all", null);
        select_all_action.activate.connect (select_all);
        actions.add_action (select_all_action);
        insert_action_group ("text", actions);

        var model = new Menu ();
        model.append (_("Copy"), "text.copy");
        model.append (_("Select All"), "text.select-all");
        menu = new Gtk.PopoverMenu.from_model (model);
        menu.has_arrow = false;
        menu.halign = Gtk.Align.START;
        menu.set_parent (this);
    }


    public override void dispose () {
        stop_autoscroll ();
        if (menu != null) {
            menu.unparent ();
            menu = null;
        }
        base.dispose ();
    }

    public override void size_allocate (int width, int height, int baseline) {
        menu.present ();
    }

    /* All of the note's text is about to be selected. */
    public signal void select_all_requested ();

    /* The text of a newly rendered note. Clears the selection, unless `keep`
     * says that the segments it was in are still the first ones. */
    public void set_segments (GenericArray<TextSegment>? list, bool keep = false) {
        // The same code views can come back when only part of the note changed.
        foreach (var adjustment in code_adjustments) {
            adjustment.value_changed.disconnect (queue_draw);
        }
        code_adjustments = new GenericArray<Gtk.Adjustment> ();
        segments = list ?? new GenericArray<TextSegment> ();
        if (!keep) {
            anchor = Position ();
            head = anchor;
        }
        foreach (var segment in segments) {
            // Code views scroll sideways under the selection.
            var code_scroller = segment.widget.get_ancestor (typeof (Gtk.ScrolledWindow)) as Gtk.ScrolledWindow;
            if (segment.widget is Gtk.TextView && code_scroller != null) {
                code_scroller.hadjustment.value_changed.connect (queue_draw);
                code_adjustments.add (code_scroller.hadjustment);
            }
        }
        selection_changed ();
    }

    public bool has_selection () {
        return anchor.compare (head) != 0;
    }

    public void select_all () {
        select_all_requested ();
        if (segments.length == 0) {
            return;
        }
        anchor = Position () { segment = 0, offset = 0 };
        int last = (int) segments.length - 1;
        head = Position () { segment = last, offset = segments[last].text.char_count () };
        selection_changed ();
        update_primary ();
    }

    public void copy () {
        if (has_selection ()) {
            area.get_clipboard ().set_text (selected_text ());
        }
    }

    public string selected_text () {
        Position start, end;
        ordered (out start, out end);
        var sb = new StringBuilder ();
        for (int i = start.segment; i <= end.segment && i < segments.length; i++) {
            var segment = segments[i];
            if (!segment.widget.is_drawable ()) {
                continue;  // inside a collapsed <details>
            }
            string text = segment.text;
            int from = i == start.segment ? start.offset : 0;
            int to = i == end.segment ? end.offset : text.char_count ();
            if (sb.len > 0) {
                sb.append (segment.separator);
            }
            sb.append (slice (text, from, to));
        }
        return sb.str;
    }

    void ordered (out Position start, out Position end) {
        bool forward = anchor.compare (head) <= 0;
        start = forward ? anchor : head;
        end = forward ? head : anchor;
    }

    void selection_changed () {
        copy_action.set_enabled (has_selection ());
        queue_draw ();
    }

    /* Middle-click pastes what was selected last, as elsewhere on the desktop. */
    void update_primary () {
        if (has_selection ()) {
            area.get_primary_clipboard ().set_text (selected_text ());
        }
    }

    /* ---- Input ---- */

    /* Touch drags scroll, and scrollbars keep working as usual. The menu is
     * inside the preview, so its clicks pass through here too. */
    bool ignores (Gtk.EventController controller, double x, double y) {
        if (menu.visible) {
            return true;
        }
        var device = controller.get_current_event_device ();
        if (device != null && device.source == Gdk.InputSource.TOUCHSCREEN) {
            return true;
        }
        var picked = area.pick (x, y, Gtk.PickFlags.DEFAULT);
        return picked != null && (picked is Gtk.Scrollbar || picked.get_ancestor (typeof (Gtk.Scrollbar)) != null);
    }

    void on_pressed (Gtk.GestureClick click, int n_press, double x, double y) {
        if (ignores (click, x, y)) {
            return;
        }
        area.grab_focus ();
        Position position;
        if (!locate (x, y, out position)) {
            anchor = Position ();
            head = anchor;
            selection_changed ();
            return;
        }
        var mods = click.get_current_event_state () & Gtk.accelerator_get_default_mod_mask ();
        if (n_press == 1 && mods == Gdk.ModifierType.SHIFT_MASK) {
            head = position;
        } else if (n_press == 1) {
            anchor = position;
            head = anchor;
        } else if (n_press == 2) {
            select_word (position);
            update_primary ();
        } else {
            anchor = Position () { segment = position.segment, offset = 0 };
            head = Position () { segment = position.segment, offset = segments[position.segment].text.char_count () };
            update_primary ();
        }
        selection_changed ();
    }

    void on_drag_begin (double x, double y) {
        dragging = false;
        if (ignores (drag, x, y)) {
            drag.set_state (Gtk.EventSequenceState.DENIED);
            return;
        }
        drag_x = x;
        drag_y = y;
    }

    void on_drag_update (double dx, double dy) {
        if (!dragging) {
            // A short wobble is still a click, so links and buttons work.
            int threshold = get_settings ().gtk_dnd_drag_threshold;
            if (dx * dx + dy * dy < threshold * threshold) {
                return;
            }
            dragging = true;
            drag.set_state (Gtk.EventSequenceState.CLAIMED);
        }
        Graphene.Point point;
        area.compute_point (scroller, Graphene.Point () { x = (float) (drag_x + dx), y = (float) (drag_y + dy) },
                            out point);
        pointer_x = point.x;
        pointer_y = point.y;
        extend_to_pointer ();
        if (autoscroll_source == 0 && autoscroll_speed () != 0) {
            autoscroll_source = Timeout.add (16, autoscroll_step);
        }
    }

    void on_drag_end (double dx, double dy) {
        stop_autoscroll ();
        if (dragging) {
            dragging = false;
            update_primary ();
        }
    }

    /* Moves the end of the selection to the pointer, given relative to the scroller. */
    void extend_to_pointer () {
        Graphene.Point point;
        scroller.compute_point (area, Graphene.Point () { x = (float) pointer_x, y = (float) pointer_y }, out point);
        Position position;
        if (locate (point.x, point.y, out position)) {
            head = position;
            selection_changed ();
        }
    }

    /* Pixels to scroll per step: faster the further the pointer is past the
     * edge. Scrolling starts a little before it, for maximized windows. */
    double autoscroll_speed () {
        const double EDGE = 16;
        double height = scroller.get_height ();
        double past = pointer_y < EDGE ? pointer_y - EDGE : pointer_y > height - EDGE ? pointer_y - height + EDGE : 0;
        return past.clamp (-80, 80) / 2;
    }

    bool autoscroll_step () {
        double speed = autoscroll_speed ();
        if (!dragging || speed == 0) {
            autoscroll_source = 0;
            return Source.REMOVE;
        }
        var adj = scroller.vadjustment;
        adj.value = (adj.value + speed).clamp (adj.lower, adj.upper - adj.page_size);
        extend_to_pointer ();
        return Source.CONTINUE;
    }

    void stop_autoscroll () {
        if (autoscroll_source != 0) {
            Source.remove (autoscroll_source);
            autoscroll_source = 0;
        }
    }

    void on_menu_pressed (Gtk.GestureClick click, double x, double y) {
        // Links keep their own menu, with Copy Link Address.
        var label = area.pick (x, y, Gtk.PickFlags.DEFAULT) as Gtk.Label;
        if (label != null && label.get_current_uri () != null) {
            return;
        }
        click.set_state (Gtk.EventSequenceState.CLAIMED);
        area.grab_focus ();
        menu.pointing_to = Gdk.Rectangle () { x = (int) x, y = (int) y, width = 1, height = 1 };
        menu.popup ();
    }

    /* ---- Geometry ---- */

    /* The text position under a point in the preview. Points between blocks
     * go to the nearest block edge, so the selection can be dragged through
     * margins and gaps. */
    bool locate (double x, double y, out Position position) {
        position = Position ();
        bool found = false;
        for (int i = 0; i < segments.length; i++) {
            var widget = segments[i].widget;
            if (!widget.is_drawable ()) {
                continue;
            }
            Graphene.Rect bounds;
            if (!widget.compute_bounds (area, out bounds)) {
                continue;
            }
            float top = bounds.origin.y;
            float left = bounds.origin.x;
            if (y < top) {
                if (!found) {
                    position = Position () { segment = i, offset = 0 };
                }
                return true;
            }
            if (y <= top + bounds.size.height && x <= left + bounds.size.width) {
                position = Position () { segment = i, offset = x < left ? 0 : offset_at (widget, x, y) };
                return true;
            }
            // Past this segment, below or to its right (the next table cell).
            position = Position () { segment = i, offset = segments[i].text.char_count () };
            found = true;
        }
        return found;
    }

    int offset_at (Gtk.Widget widget, double x, double y) {
        Graphene.Point point;
        area.compute_point (widget, Graphene.Point () { x = (float) x, y = (float) y }, out point);

        var label = widget as Gtk.Label;
        if (label != null) {
            int lx, ly;
            label.get_layout_offsets (out lx, out ly);
            var layout = label.get_layout ();
            int index, trailing;
            layout.xy_to_index ((int) ((point.x - lx) * Pango.SCALE), (int) ((point.y - ly) * Pango.SCALE),
                                out index, out trailing);
            string text = layout.get_text ();
            return (text.char_count (index) + trailing).clamp (0, text.char_count ());
        }

        var view = (Gtk.TextView) widget;
        int bx, by;
        view.window_to_buffer_coords (Gtk.TextWindowType.WIDGET, (int) point.x, (int) point.y, out bx, out by);
        Gtk.TextIter iter;
        view.get_iter_at_location (out iter, bx, by);
        return iter.get_offset ();
    }

    static bool is_word_char (unichar c) {
        return c.isalnum () || c == '_' || c == '\'' || c == '-';
    }

    void select_word (Position at) {
        string text = segments[at.segment].text;
        int length = text.char_count ();
        int start = at.offset.clamp (0, length);
        int end = start;
        if (start < length && is_word_char (char_at (text, start))) {
            while (start > 0 && is_word_char (char_at (text, start - 1))) {
                start--;
            }
            while (end < length && is_word_char (char_at (text, end))) {
                end++;
            }
        } else if (start < length) {
            end = start + 1;
        }
        anchor = Position () { segment = at.segment, offset = start };
        head = Position () { segment = at.segment, offset = end };
    }

    static unichar char_at (string text, int offset) {
        return text.get_char (text.index_of_nth_char (offset));
    }

    static string slice (string text, int from, int to) {
        if (to <= from) {
            return "";
        }
        int a = text.index_of_nth_char (from);
        return text.substring (a, text.index_of_nth_char (to) - a);
    }

    /* ---- Drawing ---- */

    public override void snapshot (Gtk.Snapshot snapshot) {
        if (!has_selection ()) {
            return;
        }
        Position start, end;
        ordered (out start, out end);
        var color = get_color ();
        for (int i = start.segment; i <= end.segment && i < segments.length; i++) {
            var segment = segments[i];
            if (!segment.widget.is_drawable ()) {
                continue;
            }
            int from = i == start.segment ? start.offset : 0;
            int to = i == end.segment ? end.offset : segment.text.char_count ();
            if (to <= from) {
                continue;
            }
            if (segment.widget is Gtk.Label) {
                draw_label_range (snapshot, (Gtk.Label) segment.widget, from, to, color);
            } else {
                draw_view_range (snapshot, (Gtk.TextView) segment.widget, from, to, i < end.segment, color);
            }
        }
    }

    static Graphene.Rect rect (float x, float y, float width, float height) {
        return Graphene.Rect () {
            origin = Graphene.Point () { x = x, y = y },
            size = Graphene.Size () { width = width, height = height },
        };
    }

    void draw_label_range (Gtk.Snapshot snapshot, Gtk.Label label, int from, int to, Gdk.RGBA color) {
        Graphene.Point origin;
        if (!label.compute_point (this, Graphene.Point (), out origin)) {
            return;
        }
        int lx, ly;
        label.get_layout_offsets (out lx, out ly);
        var layout = label.get_layout ();
        string text = layout.get_text ();
        int[] range = { text.index_of_nth_char (from), text.index_of_nth_char (to) };
        var region = layout_clip_region (layout, lx, ly, range, 1);
        for (int k = 0; k < region.num_rectangles (); k++) {
            Cairo.RectangleInt r = region.get_rectangle (k);
            snapshot.append_color (color, rect (origin.x + r.x, origin.y + r.y, r.width, r.height));
        }
    }

    void draw_view_range (Gtk.Snapshot snapshot, Gtk.TextView view, int from, int to, bool continues,
                          Gdk.RGBA color) {
        // Code views scroll sideways, so clip the highlight to what's visible.
        var code_scroller = view.get_ancestor (typeof (Gtk.ScrolledWindow));
        if (code_scroller == null) {
            return;
        }
        Graphene.Rect clip;
        if (!code_scroller.compute_bounds (this, out clip)) {
            return;
        }
        snapshot.push_clip (clip);

        Gtk.TextIter iter, end;
        view.buffer.get_iter_at_offset (out iter, from);
        view.buffer.get_iter_at_offset (out end, to);
        while (iter.compare (end) < 0) {
            Gtk.TextIter line_end = iter;
            if (!line_end.ends_line ()) {
                line_end.forward_to_line_end ();
            }
            Gtk.TextIter stop = line_end.compare (end) < 0 ? line_end : end;
            Gdk.Rectangle first, last;
            view.get_iter_location (iter, out first);
            view.get_iter_location (stop, out last);
            int y, height;
            view.get_line_yrange (iter, out y, out height);
            // A selected line break shows as a little extra width.
            int width = last.x - first.x + (stop.equal (line_end) && (line_end.compare (end) < 0 || continues) ? height / 2 : 0);

            int wx, wy;
            view.buffer_to_window_coords (Gtk.TextWindowType.WIDGET, first.x, y, out wx, out wy);
            Graphene.Point origin;
            if (view.compute_point (this, Graphene.Point () { x = wx, y = wy }, out origin)) {
                snapshot.append_color (color, rect (origin.x, origin.y, width, height));
            }
            iter = line_end;
            if (!iter.forward_line ()) {
                break;
            }
        }
        snapshot.pop ();
    }
}

/* The Vala binding passes the array length where GDK wants the number of ranges. */
[CCode (cname = "gdk_pango_layout_get_clip_region", cheader_filename = "gtk/gtk.h")]
extern Cairo.Region layout_clip_region (Pango.Layout layout, int x_origin, int y_origin,
                                        [CCode (array_length = false)] int[] index_ranges, int n_ranges);
