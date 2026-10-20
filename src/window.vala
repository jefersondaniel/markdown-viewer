namespace Notes {

    enum Mode {
        VIEW,
        EDIT,
    }

    [GtkTemplate (ui = "/io/github/jefersondaniel/MarkdownViewer/window.ui")]
    public class Window : Adw.ApplicationWindow {
        [GtkChild] unowned Adw.ToastOverlay toast_overlay;
        [GtkChild] unowned Adw.OverlaySplitView split_view;
        [GtkChild] unowned Adw.WindowTitle sidebar_title;
        [GtkChild] unowned Gtk.Stack sidebar_stack;
        [GtkChild] unowned Gtk.SearchEntry search_entry;
        [GtkChild] unowned FileTree file_tree;
        [GtkChild] unowned Adw.WindowTitle window_title;
        [GtkChild] unowned Gtk.SearchBar find_bar;
        [GtkChild] unowned Gtk.SearchEntry find_entry;
        [GtkChild] unowned Gtk.Label find_count;
        [GtkChild] unowned Gtk.Stack content_stack;
        [GtkChild] unowned Adw.StatusPage empty_page;
        [GtkChild] unowned Gtk.Button empty_button;
        [GtkChild] unowned Gtk.Paned paned;
        [GtkChild] unowned Gtk.ScrolledWindow editor_scroller;
        [GtkChild] unowned Gtk.ScrolledWindow preview_scroller;
        [GtkChild] unowned Adw.Clamp preview_clamp;
        [GtkChild] unowned Gtk.Button zoom_button;

        const ActionEntry[] ACTIONS = {
            { "new-note", on_new_note },
            { "new-folder", on_new_folder },
            { "open-folder", on_open_folder },
            { "open", on_open },
            { "guide", on_guide },
            { "save", on_save },
            { "go-back", on_go_back },
            { "toggle-mode", on_toggle_mode },
            { "find", on_find },
            { "toggle-sidebar", on_toggle_sidebar },
            { "keyboard-shortcuts", on_keyboard_shortcuts },
            { "rename-note", on_rename_current },
            { "trash-note", on_trash_current },
            { "copy-markdown", on_copy_markdown },
            { "save-copy", on_save_copy },
            { "show-in-files", on_show_in_files },
            { "new-note-in", on_new_note_in, "s" },
            { "new-folder-in", on_new_folder_in, "s" },
            { "file-rename", on_file_rename, "s" },
            { "file-show", on_file_show, "s" },
            { "file-trash", on_file_trash, "s" },
            { "mode", null, "s", "'view'", on_mode_changed },
            { "split", null, null, "false", on_split_changed },
            { "zoom-in", on_zoom_in },
            { "zoom-out", on_zoom_out },
            { "zoom-reset", on_zoom_reset },
        };

        /* Text sizes offered by Zoom In and Zoom Out, in percent. */
        const int[] ZOOM_LEVELS = { 80, 90, 100, 110, 120, 135, 150, 175, 200 };

        const string GUIDE_URI = "resource:///io/github/jefersondaniel/MarkdownViewer/guide.md";

        State state;
        Editor editor;
        Markdown.Renderer? renderer;
        Gtk.Overlay preview_overlay = new Gtk.Overlay ();
        TextSelection selection;
        GtkSource.SearchSettings search_settings;
        GtkSource.SearchContext search_context;

        /* The folder shown in the sidebar. */
        File? folder;

        /* The open document. It may live outside `folder`, or be the read-only guide. */
        File? doc_file;
        bool doc_read_only;
        FileMonitor? doc_monitor;
        string saved_text = "";
        GenericArray<File> history = new GenericArray<File> ();

        Mode mode = Mode.VIEW;
        bool split;
        bool loading;
        bool preview_dirty = true;
        int match_index = -1;
        uint save_source;
        uint render_source;
        uint disk_check_source;

        int zoom = 100;
        Gtk.CssProvider zoom_css = new Gtk.CssProvider ();
        int clamp_size;
        int clamp_threshold;
        double zoom_scroll;

        class construct {
            typeof (FileTree).ensure ();
        }

        public Window (Application app, State state) {
            Object (application: app);
            this.state = state;

            setup_editor ();
            setup_preview ();
            add_action_entries (ACTIONS, this);
            setup_sidebar ();
            setup_find ();
            setup_drop ();
            setup_zoom ();
            restore_state ();

            var style = Adw.StyleManager.get_default ();
            editor.set_dark (style.dark);
            style.notify["dark"].connect (() => {
                editor.set_dark (style.dark);
                preview_dirty = true;
                render_preview (true);
            });

            string saved_folder = state.get_string ("folder");
            if (saved_folder != "" && FileUtils.test (saved_folder, FileTest.IS_DIR)) {
                open_folder (File.new_for_path (saved_folder));
            } else {
                show_folder (null);
            }
            string last = state.get_string ("last-file");
            if (last != "" && FileUtils.test (last, FileTest.EXISTS)) {
                open_file (File.new_for_path (last), false);
            } else {
                close_document ();
            }
        }

        /* ---- Setup ---- */

        void setup_editor () {
            editor = new Editor ();
            editor_scroller.child = editor;
            editor.buffer.changed.connect (() => {
                if (loading) {
                    return;
                }
                schedule_save ();
                schedule_render ();
            });
        }

        void setup_preview () {
            preview_clamp.child = preview_overlay;
            selection = new TextSelection (preview_overlay, preview_scroller);
        }

        void setup_sidebar () {
            file_tree.file_activated.connect ((file) => open_file (file));
            file_tree.context_menu.connect (show_tree_menu);
            search_entry.search_changed.connect (() => file_tree.search (search_entry.text.strip ()));
        }

        void setup_find () {
            search_settings = new GtkSource.SearchSettings ();
            search_settings.case_sensitive = false;
            search_settings.wrap_around = true;
            search_context = new GtkSource.SearchContext (editor.source_buffer, search_settings);
            search_context.notify["occurrences-count"].connect (update_find_count);

            find_bar.notify["search-mode-enabled"].connect (() => {
                if (find_bar.search_mode_enabled) {
                    find_entry.grab_focus ();
                    run_find ();
                } else {
                    search_settings.search_text = null;
                    preview_dirty = true;
                    render_preview (true);
                }
            });
            find_entry.search_changed.connect (run_find);
            find_entry.activate.connect (() => find_step (true));
            find_entry.next_match.connect (() => find_step (true));
            find_entry.previous_match.connect (() => find_step (false));
            find_entry.stop_search.connect (() => find_bar.search_mode_enabled = false);
        }

        void setup_drop () {
            var drop = new Gtk.DropTarget (typeof (Gdk.FileList), Gdk.DragAction.COPY);
            drop.drop.connect ((value, x, y) => {
                var list = (Gdk.FileList) value.get_boxed ();
                foreach (unowned File file in list.get_files ()) {
                    if (file.query_file_type (FileQueryInfoFlags.NONE) == FileType.DIRECTORY) {
                        open_folder (file);
                        return true;
                    }
                    string? name = file.get_basename ();
                    if (name != null && Files.is_markdown_name (name)) {
                        open_file (file);
                        return true;
                    }
                }
                return false;
            });
            content_stack.add_controller (drop);
        }

        void setup_zoom () {
            add_provider_for_display (get_display (), zoom_css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 2);
            clamp_size = preview_clamp.maximum_size;
            clamp_threshold = preview_clamp.tightening_threshold;

            // Control and the scroll wheel or touchpad zoom too.
            var scroll = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.VERTICAL);
            scroll.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            scroll.scroll_begin.connect (() => zoom_scroll = 0);
            scroll.scroll.connect ((dx, dy) => {
                var mods = scroll.get_current_event_state () & Gtk.accelerator_get_default_mod_mask ();
                if (mods != Gdk.ModifierType.CONTROL_MASK) {
                    return false;
                }
                // A wheel reports steps; a touchpad reports pixels.
                double step = scroll.get_unit () == Gdk.ScrollUnit.SURFACE ? 40 : 1;
                zoom_scroll += dy;
                while (zoom_scroll <= -step) {
                    zoom_scroll += step;
                    on_zoom_in ();
                }
                while (zoom_scroll >= step) {
                    zoom_scroll -= step;
                    on_zoom_out ();
                }
                return true;
            });
            paned.add_controller (scroll);
        }

        void restore_state () {
            set_default_size (state.get_int ("width", 1180), state.get_int ("height", 820));
            if (state.get_bool ("maximized", false)) {
                maximize ();
            }
            split_view.show_sidebar = state.get_bool ("sidebar", true);
            split = state.get_bool ("split", false);
            mode = state.get_string ("mode", "view") == "edit" ? Mode.EDIT : Mode.VIEW;
            set_zoom (state.get_int ("zoom", 100));
            lookup ("split").set_state (new Variant.boolean (split));
            sync_mode_buttons ();
            apply_mode (false);
        }

        new SimpleAction lookup (string name) {
            return (SimpleAction) lookup_action (name);
        }

        protected override bool close_request () {
            leave_document ();
            int width, height;
            get_default_size (out width, out height);
            state.set_int ("width", width);
            state.set_int ("height", height);
            state.set_bool ("maximized", maximized);
            state.set_bool ("sidebar", split_view.show_sidebar);
            state.set_bool ("split", split);
            state.set_string ("mode", mode == Mode.EDIT ? "edit" : "view");
            state.set_int ("zoom", zoom);
            state.set_string ("last-file", doc_file != null && !doc_read_only ? doc_file.get_path () : "");
            state.save ();
            return false;
        }

        /* ---- Folder ---- */

        public void open_folder (File dir) {
            show_folder (dir);
            state.set_string ("folder", dir.get_path ());
            state.save ();
        }

        void show_folder (File? dir) {
            folder = dir;
            search_entry.text = "";
            file_tree.load (dir);
            if (dir != null) {
                sidebar_title.title = dir.get_basename ();
                sidebar_title.subtitle = Files.pretty_path (dir.get_parent ());
                sidebar_stack.visible_child_name = "folder";
                if (doc_file != null) {
                    file_tree.select_file (doc_file);
                }
            } else {
                sidebar_title.title = _("Markdown Viewer");
                sidebar_title.subtitle = "";
                sidebar_stack.visible_child_name = "no-folder";
            }
            update_empty_page ();
            update_actions ();
        }

        void show_tree_menu (File file, bool is_dir, double x, double y) {
            string path = file.get_path ();
            var menu = new Menu ();
            if (is_dir) {
                var create = new Menu ();
                create.append (_("New Note"), Action.print_detailed_name ("win.new-note-in", path));
                create.append (_("New Folder…"), Action.print_detailed_name ("win.new-folder-in", path));
                menu.append_section (null, create);
            }
            var manage = new Menu ();
            manage.append (_("Rename…"), Action.print_detailed_name ("win.file-rename", path));
            manage.append (_("Show in Files"), Action.print_detailed_name ("win.file-show", path));
            menu.append_section (null, manage);
            var danger = new Menu ();
            danger.append (_("Move to Trash"), Action.print_detailed_name ("win.file-trash", path));
            menu.append_section (null, danger);
            file_tree.popup_menu (menu, x, y);
        }

        /* Where new notes and folders go: the folder selected in the sidebar, or the open folder. */
        File? target_dir () {
            return file_tree.selected_dir () ?? folder;
        }

        /* ---- Documents ---- */

        public void open_file (File file, bool push_history = true) {
            if (doc_file != null && doc_file.equal (file)) {
                if (split_view.collapsed) {
                    split_view.show_sidebar = false;
                }
                return;
            }

            string? text = Files.read_text (file);
            if (text == null) {
                toast (_("Could not open “%s”").printf (file.get_basename ()));
                return;
            }

            File? previous = leave_document ();
            if (push_history && previous != null) {
                history.add (previous);
            }

            doc_file = file;
            doc_read_only = file.get_uri () == GUIDE_URI;
            reload_buffer (text);
            Gtk.TextIter start;
            editor.buffer.get_start_iter (out start);
            editor.buffer.place_cursor (start);
            editor.editable = !doc_read_only;
            content_stack.visible_child_name = "document";
            editor_scroller.vadjustment.value = 0;
            watch_document ();

            update_header ();
            update_actions ();
            preview_dirty = true;
            render_preview (false);
            if (find_bar.search_mode_enabled) {
                run_find ();
            }
            file_tree.select_file (doc_read_only ? null : doc_file);
            if (!doc_read_only) {
                state.set_string ("last-file", file.get_path ());
            }
            if (split_view.collapsed) {
                split_view.show_sidebar = false;
            }
        }

        void reload_buffer (string text) {
            var buffer = editor.buffer;
            Gtk.TextIter cursor;
            buffer.get_iter_at_mark (out cursor, buffer.get_insert ());
            int offset = cursor.get_offset ();

            loading = true;
            buffer.begin_irreversible_action ();
            buffer.text = text;
            buffer.end_irreversible_action ();
            loading = false;
            saved_text = text;

            buffer.get_iter_at_offset (out cursor, offset);
            buffer.place_cursor (cursor);
            preview_dirty = true;
            render_preview (true);
        }

        /* Saves the current document and names untitled notes after their first
         * line. Returns the document's final location. */
        File? leave_document () {
            if (doc_file == null) {
                return null;
            }
            save_now ();
            if (!doc_read_only && Files.is_untitled (Files.stem_of (doc_file.get_basename ()))) {
                string name = Files.sanitize_name (Files.derive_title (saved_text, ""));
                if (name != "") {
                    File target = Files.unique_child (doc_file.get_parent (), name, Files.ext_of (doc_file.get_basename ()));
                    try {
                        doc_file.move (target, FileCopyFlags.NONE);
                        replace_in_history (doc_file, target);
                        doc_file = target;
                    } catch (Error e) {
                        warning ("Could not rename %s: %s", doc_file.get_basename (), e.message);
                    }
                }
            }
            return doc_file;
        }

        void replace_in_history (File old_file, File new_file) {
            for (int k = 0; k < history.length; k++) {
                if (history[k].equal (old_file)) {
                    history[k] = new_file;
                }
            }
        }

        void close_document () {
            if (doc_monitor != null) {
                doc_monitor.cancel ();
                doc_monitor = null;
            }
            doc_file = null;
            doc_read_only = false;
            loading = true;
            editor.buffer.text = "";
            loading = false;
            saved_text = "";
            preview_overlay.child = null;
            selection.set_segments (null);
            renderer = null;
            content_stack.visible_child_name = "empty";
            update_header ();
            update_actions ();
            update_empty_page ();
            file_tree.select_file (null);
        }

        /* Notice when another program changes, moves or deletes the open file. */
        void watch_document () {
            if (doc_monitor != null) {
                doc_monitor.cancel ();
                doc_monitor = null;
            }
            if (doc_file == null || doc_read_only) {
                return;
            }
            try {
                doc_monitor = doc_file.monitor_file (FileMonitorFlags.WATCH_MOVES);
                doc_monitor.changed.connect (() => {
                    if (disk_check_source != 0) {
                        Source.remove (disk_check_source);
                    }
                    disk_check_source = Timeout.add (250, () => {
                        disk_check_source = 0;
                        check_document_on_disk ();
                        return Source.REMOVE;
                    });
                });
            } catch (Error e) {
                warning ("Could not watch %s: %s", doc_file.get_basename (), e.message);
            }
        }

        void check_document_on_disk () {
            if (doc_file == null || doc_read_only) {
                return;
            }
            if (!doc_file.query_exists ()) {
                string name = doc_file.get_basename ();
                close_document ();
                toast (_("“%s” was moved or deleted").printf (name));
                return;
            }
            // Pick up changes made elsewhere, unless there are unsaved edits here.
            string? text = Files.read_text (doc_file);
            if (text != null && text != saved_text && editor.buffer.text == saved_text) {
                reload_buffer (text);
            }
        }

        void update_header () {
            if (doc_file == null) {
                window_title.title = folder != null ? folder.get_basename () : _("Markdown Viewer");
                window_title.subtitle = "";
                title = _("Markdown Viewer");
                return;
            }
            if (doc_read_only) {
                window_title.title = _("Markdown Guide");
                window_title.subtitle = _("Read only");
            } else {
                window_title.title = Files.stem_of (doc_file.get_basename ());
                window_title.subtitle = location_of (doc_file.get_parent ());
            }
            title = window_title.title;
        }

        /* "Folder/Sub" for files in the open folder, a full path otherwise. */
        string location_of (File? dir) {
            if (dir != null && folder != null) {
                if (dir.equal (folder)) {
                    return folder.get_basename ();
                }
                string? rel = folder.get_relative_path (dir);
                if (rel != null) {
                    return folder.get_basename () + "/" + rel;
                }
            }
            return Files.pretty_path (dir);
        }

        void update_empty_page () {
            if (folder == null) {
                empty_page.title = _("No Folder Open");
                empty_page.description = _("Open a folder to browse and edit its Markdown files");
                empty_button.label = _("Open Folder…");
                empty_button.action_name = "win.open-folder";
            } else {
                empty_page.title = _("No File Open");
                empty_page.description = _("Choose a Markdown file from the sidebar, or start a new one");
                empty_button.label = _("New Note");
                empty_button.action_name = "win.new-note";
            }
        }

        void update_actions () {
            bool has_doc = doc_file != null;
            bool editable_doc = has_doc && !doc_read_only;
            lookup ("new-note").set_enabled (folder != null);
            lookup ("new-folder").set_enabled (folder != null);
            lookup ("save").set_enabled (editable_doc);
            lookup ("rename-note").set_enabled (editable_doc);
            lookup ("trash-note").set_enabled (editable_doc);
            lookup ("show-in-files").set_enabled (editable_doc);
            lookup ("copy-markdown").set_enabled (has_doc);
            lookup ("save-copy").set_enabled (has_doc);
            lookup ("find").set_enabled (has_doc);
            lookup ("go-back").set_enabled (history.length > 0);
        }

        void schedule_save () {
            if (save_source != 0) {
                Source.remove (save_source);
            }
            save_source = Timeout.add (700, () => {
                save_source = 0;
                save_now ();
                return Source.REMOVE;
            });
        }

        bool save_now () {
            if (save_source != 0) {
                Source.remove (save_source);
                save_source = 0;
            }
            if (doc_file == null || doc_read_only) {
                return true;
            }
            string text = editor.buffer.text;
            if (text == saved_text) {
                return true;
            }
            try {
                doc_file.replace_contents (text.data, null, false, FileCreateFlags.NONE, null);
                saved_text = text;
                return true;
            } catch (Error e) {
                toast (_("Could not save: %s").printf (e.message));
                return false;
            }
        }

        /* ---- Preview ---- */

        void schedule_render () {
            preview_dirty = true;
            if (!preview_scroller.visible) {
                return;
            }
            if (render_source != 0) {
                Source.remove (render_source);
            }
            render_source = Timeout.add (150, () => {
                render_source = 0;
                render_preview (true);
                return Source.REMOVE;
            });
        }

        void render_preview (bool keep_scroll) {
            if (doc_file == null || !preview_scroller.visible || !preview_dirty) {
                return;
            }
            preview_dirty = false;

            var doc = new Markdown.Parser ().parse (editor.buffer.text);
            var r = new Markdown.Renderer ();
            r.base_dir = doc_file.get_parent ();
            r.dark = Adw.StyleManager.get_default ().dark;
            r.read_only = doc_read_only;
            r.highlight = find_bar.search_mode_enabled ? find_entry.text : "";
            r.link_activated.connect (on_link_activated);
            r.task_toggled.connect (on_task_toggled);

            var content = r.render (doc);
            content.margin_start = 32;
            content.margin_end = 32;
            content.margin_top = 20;
            content.margin_bottom = 64;

            var adj = preview_scroller.vadjustment;
            double position = adj.value;
            preview_overlay.child = content;
            selection.set_segments (r.segments);
            renderer = r;
            match_index = -1;

            if (keep_scroll) {
                // Restore the position once the new content has been measured.
                ulong handler = adj.notify["upper"].connect (() => adj.value = position);
                Timeout.add (250, () => {
                    adj.disconnect (handler);
                    return Source.REMOVE;
                });
            } else {
                adj.value = 0;
            }
            update_find_count ();
        }

        void on_link_activated (string uri) {
            if (uri.has_prefix ("#")) {
                scroll_to_anchor (uri.substring (1));
                return;
            }
            string? scheme = Uri.peek_scheme (uri);
            if (scheme != null && scheme != "file") {
                launch_uri.begin (uri);
                return;
            }

            string path = uri;
            string fragment = "";
            int hash = path.index_of_char ('#');
            if (hash >= 0) {
                fragment = path.substring (hash + 1);
                path = path.substring (0, hash);
            }
            File target;
            if (scheme == "file") {
                target = File.new_for_uri (path);
            } else {
                path = Uri.unescape_string (path) ?? path;
                target = path.has_prefix ("/") ? File.new_for_path (path) : doc_file.get_parent ().resolve_relative_path (path);
            }

            if (Files.is_markdown_name (target.get_basename ())) {
                open_file (target);
                if (fragment != "") {
                    Idle.add (() => {
                        scroll_to_anchor (fragment);
                        return Source.REMOVE;
                    });
                }
            } else {
                launch_file.begin (target);
            }
        }

        async void launch_uri (string uri) {
            try {
                yield new Gtk.UriLauncher (uri).launch (this, null);
            } catch (Error e) {
                toast (_("Could not open the link"));
            }
        }

        async void launch_file (File file) {
            try {
                yield new Gtk.FileLauncher (file).launch (this, null);
            } catch (Error e) {
                toast (_("Could not open “%s”").printf (file.get_basename ()));
            }
        }

        void scroll_to_anchor (string slug) {
            if (renderer == null) {
                return;
            }
            var widget = renderer.get_anchor (Uri.unescape_string (slug) ?? slug);
            if (widget != null) {
                scroll_to_widget (widget);
            }
        }

        void scroll_to_widget (Gtk.Widget widget) {
            Graphene.Point point;
            if (widget.compute_point (preview_clamp, Graphene.Point () { x = 0, y = 0 }, out point)) {
                preview_scroller.vadjustment.value = point.y - 16;
            }
        }

        /* Checking a box in the preview edits the matching "[ ]" in the source. */
        void on_task_toggled (int line, bool active) {
            var buffer = editor.buffer;
            Gtk.TextIter start;
            if (!buffer.get_iter_at_line (out start, line)) {
                return;
            }
            Gtk.TextIter end = start;
            if (!end.ends_line ()) {
                end.forward_to_line_end ();
            }
            string text = buffer.get_text (start, end, false);
            MatchInfo mi;
            if (!/\[[ xX]\]/.match (text, 0, out mi)) {
                return;
            }
            int s, e;
            mi.fetch_pos (0, out s, out e);
            Gtk.TextIter a = start;
            a.forward_chars (text.substring (0, s).char_count () + 1);
            Gtk.TextIter b = a;
            b.forward_char ();
            buffer.begin_user_action ();
            buffer.delete (ref a, ref b);
            buffer.insert (ref a, active ? "x" : " ", -1);
            buffer.end_user_action ();
        }

        /* ---- Modes ---- */

        void apply_mode (bool focus) {
            editor_scroller.visible = split || mode == Mode.EDIT;
            preview_scroller.visible = split || mode == Mode.VIEW;
            if (split) {
                int width = paned.get_width ();
                paned.position = width > 0 ? width / 2 : 560;
            }
            render_preview (true);
            if (focus && editor_scroller.visible && doc_file != null) {
                editor.grab_focus ();
            }
            if (find_bar.search_mode_enabled) {
                run_find ();
            }
        }

        void on_mode_changed (SimpleAction action, Variant value) {
            action.set_state (value);
            mode = value.get_string () == "edit" ? Mode.EDIT : Mode.VIEW;
            if (split) {
                // Picking View or Edit leaves side-by-side mode.
                split = false;
                lookup ("split").set_state (new Variant.boolean (false));
            }
            apply_mode (true);
        }

        void on_split_changed (SimpleAction action, Variant value) {
            action.set_state (value);
            split = value.get_boolean ();
            sync_mode_buttons ();
            apply_mode (true);
        }

        /* In side-by-side mode neither View nor Edit shows as pressed. */
        void sync_mode_buttons () {
            string state = split ? "split" : mode == Mode.EDIT ? "edit" : "view";
            lookup ("mode").set_state (new Variant.string (state));
        }

        /* ---- Zoom ---- */

        /* Scales the text of the editor and the preview. The reading column grows
         * with it, so lines keep about the same number of words. */
        void set_zoom (int level) {
            zoom = level.clamp (ZOOM_LEVELS[0], ZOOM_LEVELS[ZOOM_LEVELS.length - 1]);
            zoom_css.load_from_string ("paned.document { font-size: %d%%; }".printf (zoom));
            double scale = zoom / 100.0;
            preview_clamp.maximum_size = (int) (clamp_size * scale);
            preview_clamp.tightening_threshold = (int) (clamp_threshold * scale);
            editor.zoom = scale;
            zoom_button.label = "%d%%".printf (zoom);
            lookup ("zoom-in").set_enabled (zoom < ZOOM_LEVELS[ZOOM_LEVELS.length - 1]);
            lookup ("zoom-out").set_enabled (zoom > ZOOM_LEVELS[0]);
        }

        void on_zoom_in () {
            foreach (int level in ZOOM_LEVELS) {
                if (level > zoom) {
                    set_zoom (level);
                    return;
                }
            }
        }

        void on_zoom_out () {
            for (int i = ZOOM_LEVELS.length - 1; i >= 0; i--) {
                if (ZOOM_LEVELS[i] < zoom) {
                    set_zoom (ZOOM_LEVELS[i]);
                    return;
                }
            }
        }

        void on_zoom_reset () {
            set_zoom (100);
        }

        void on_toggle_mode () {
            activate_action_variant ("win.mode", new Variant.string (mode == Mode.VIEW ? "edit" : "view"));
        }

        /* ---- Find ---- */

        void run_find () {
            string query = find_entry.text;
            search_settings.search_text = query != "" ? query : null;
            preview_dirty = true;
            render_preview (true);
            update_find_count ();
        }

        void update_find_count () {
            if (find_entry.text == "") {
                find_count.label = "";
                return;
            }
            bool in_editor = editor_scroller.visible && !preview_scroller.visible;
            int count = in_editor ? search_context.occurrences_count : (renderer != null ? renderer.match_count : 0);
            if (count < 0) {
                return;  // still counting
            }
            find_count.label = count == 0 ? _("No results") : ngettext ("%d match", "%d matches", count).printf (count);
        }

        void find_step (bool forward) {
            if (editor_scroller.visible) {
                var buffer = editor.buffer;
                Gtk.TextIter sel_start, sel_end, match_start, match_end;
                buffer.get_selection_bounds (out sel_start, out sel_end);
                bool wrapped;
                bool found = forward
                    ? search_context.forward (sel_end, out match_start, out match_end, out wrapped)
                    : search_context.backward (sel_start, out match_start, out match_end, out wrapped);
                if (found) {
                    buffer.select_range (match_start, match_end);
                    editor.scroll_to_mark (buffer.get_insert (), 0.2, false, 0, 0);
                }
            }
            if (preview_scroller.visible && renderer != null && renderer.match_widgets.length > 0) {
                int n = (int) renderer.match_widgets.length;
                match_index = ((match_index + (forward ? 1 : -1)) % n + n) % n;
                scroll_to_widget (renderer.match_widgets[match_index]);
            }
        }

        [GtkCallback]
        void on_find_next () {
            find_step (true);
        }

        [GtkCallback]
        void on_find_previous () {
            find_step (false);
        }

        void on_find () {
            find_bar.search_mode_enabled = !find_bar.search_mode_enabled;
        }

        /* ---- Actions ---- */

        void on_new_note () {
            File? dir = target_dir ();
            if (dir != null) {
                create_note_in (dir);
            }
        }

        void on_new_note_in (SimpleAction action, Variant? param) {
            create_note_in (File.new_for_path (param.get_string ()));
        }

        void create_note_in (File dir) {
            leave_document ();
            File file = Files.unique_child (dir, _("Untitled"), ".md");
            try {
                file.create (FileCreateFlags.NONE).close ();
            } catch (Error e) {
                toast (_("Could not create the note: %s").printf (e.message));
                return;
            }
            open_file (file);
            activate_action_variant ("win.mode", new Variant.string ("edit"));
            editor.grab_focus ();
        }

        void on_new_folder () {
            File? dir = target_dir ();
            if (dir != null) {
                create_folder_in (dir);
            }
        }

        void on_new_folder_in (SimpleAction action, Variant? param) {
            create_folder_in (File.new_for_path (param.get_string ()));
        }

        void create_folder_in (File dir) {
            ask_name.begin (_("New Folder"), "", _("Create"), (obj, res) => {
                string? name = ask_name.end (res);
                if (name == null) {
                    return;
                }
                try {
                    dir.get_child (Files.sanitize_name (name)).make_directory ();
                } catch (Error e) {
                    toast (_("Could not create the folder: %s").printf (e.message));
                }
            });
        }

        void on_open_folder () {
            open_folder_dialog.begin ();
        }

        async void open_folder_dialog () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Open Folder");
            if (folder != null) {
                dialog.initial_folder = folder;
            }
            try {
                File dir = yield dialog.select_folder (this, null);
                open_folder (dir);
            } catch (Error e) {
                // Cancelled.
            }
        }

        void on_open () {
            open_file_dialog.begin ();
        }

        async void open_file_dialog () {
            var markdown = new Gtk.FileFilter ();
            markdown.name = _("Markdown");
            markdown.add_mime_type ("text/markdown");
            markdown.add_suffix ("md");
            markdown.add_suffix ("markdown");
            var all = new Gtk.FileFilter ();
            all.name = _("All Files");
            all.add_pattern ("*");
            var filters = new ListStore (typeof (Gtk.FileFilter));
            filters.append (markdown);
            filters.append (all);

            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Open Markdown File");
            dialog.filters = filters;
            dialog.default_filter = markdown;
            if (folder != null) {
                dialog.initial_folder = folder;
            }
            try {
                File file = yield dialog.open (this, null);
                open_file (file);
            } catch (Error e) {
                // Cancelled.
            }
        }

        void on_guide () {
            open_file (File.new_for_uri (GUIDE_URI));
            activate_action_variant ("win.mode", new Variant.string ("view"));
        }

        void on_save () {
            if (save_now ()) {
                toast (_("Saved"));
            }
        }

        void on_go_back () {
            while (history.length > 0) {
                File file = history[history.length - 1];
                history.remove_index (history.length - 1);
                if (file.query_exists ()) {
                    open_file (file, false);
                    break;
                }
            }
            update_actions ();
        }

        void on_toggle_sidebar () {
            split_view.show_sidebar = !split_view.show_sidebar;
        }

        void on_keyboard_shortcuts () {
            var builder = new Gtk.Builder.from_resource (Config.RESOURCE_PATH + "/shortcuts.ui");
#if ADW_1_8
            ((Adw.ShortcutsDialog) builder.get_object ("shortcuts")).present (this);
#else
            var window = (Gtk.ShortcutsWindow) builder.get_object ("shortcuts");
            window.transient_for = this;
            window.present ();
#endif
        }

        void on_rename_current () {
            if (doc_file != null && !doc_read_only) {
                rename_file (doc_file);
            }
        }

        void on_file_rename (SimpleAction action, Variant? param) {
            rename_file (File.new_for_path (param.get_string ()));
        }

        void rename_file (File file) {
            bool is_dir = file.query_file_type (FileQueryInfoFlags.NONE) == FileType.DIRECTORY;
            string name = file.get_basename ();
            if (doc_file != null && doc_file.equal (file)) {
                save_now ();
            }
            ask_name.begin (is_dir ? _("Rename Folder") : _("Rename File"), is_dir ? name : Files.stem_of (name),
                            _("Rename"), (obj, res) => {
                string? new_name = ask_name.end (res);
                if (new_name == null) {
                    return;
                }
                string clean = Files.sanitize_name (new_name);
                if (clean == "") {
                    toast (_("That name can't be used"));
                    return;
                }
                try {
                    File renamed = file.set_display_name (is_dir ? clean : clean + Files.ext_of (name));
                    relocate_document (file, renamed);
                } catch (Error e) {
                    toast (_("Could not rename: %s").printf (e.message));
                }
            });
        }

        /* Keeps the open document (and history) pointing at the right place after
         * it, or a folder containing it, was renamed. */
        void relocate_document (File old_file, File new_file) {
            replace_in_history (old_file, new_file);
            if (doc_file == null) {
                return;
            }
            if (doc_file.equal (old_file)) {
                doc_file = new_file;
            } else if (doc_file.has_prefix (old_file)) {
                doc_file = new_file.resolve_relative_path (old_file.get_relative_path (doc_file));
            } else {
                return;
            }
            watch_document ();
            update_header ();
            file_tree.select_file (doc_file);
        }

        void on_trash_current () {
            if (doc_file != null && !doc_read_only) {
                trash_file (doc_file);
            }
        }

        void on_file_trash (SimpleAction action, Variant? param) {
            trash_file (File.new_for_path (param.get_string ()));
        }

        void trash_file (File file) {
            bool was_open = doc_file != null && (doc_file.equal (file) || doc_file.has_prefix (file));
            File? reopen = was_open ? doc_file : null;
            if (was_open) {
                save_now ();
            }
            try {
                file.trash ();
            } catch (Error e) {
                toast (_("Could not move to the Trash: %s").printf (e.message));
                return;
            }
            if (was_open) {
                close_document ();
            }
            var t = new Adw.Toast (_("“%s” moved to the Trash").printf (file.get_basename ()));
            t.button_label = _("Undo");
            t.button_clicked.connect (() => restore_from_trash.begin (file, reopen));
            toast_overlay.add_toast (t);
        }

        /* Moves the most recently trashed item that came from `original` back. */
        async void restore_from_trash (File original, File? reopen) {
            var trash = File.new_for_uri ("trash:///");
            File? best = null;
            DateTime? best_date = null;
            try {
                var enumerator = yield trash.enumerate_children_async (
                    "standard::name,trash::orig-path,trash::deletion-date", FileQueryInfoFlags.NONE, Priority.DEFAULT, null);
                while (true) {
                    var infos = yield enumerator.next_files_async (64, Priority.DEFAULT, null);
                    if (infos.length () == 0) {
                        break;
                    }
                    foreach (unowned FileInfo info in infos) {
                        if (info.get_attribute_byte_string ("trash::orig-path") != original.get_path ()) {
                            continue;
                        }
                        DateTime? date = info.get_deletion_date ();
                        if (best == null || (date != null && best_date != null && date.compare (best_date) > 0)) {
                            best = trash.get_child (info.get_name ());
                            best_date = date;
                        }
                    }
                }
                if (best == null) {
                    throw new IOError.NOT_FOUND (_("It is no longer in the Trash"));
                }
                best.move (original, FileCopyFlags.NONE);
                if (reopen != null) {
                    open_file (reopen, false);
                }
            } catch (Error e) {
                toast (_("Could not restore “%s”: %s").printf (original.get_basename (), e.message));
            }
        }

        void on_copy_markdown () {
            get_clipboard ().set_text (editor.buffer.text);
            toast (_("Copied to clipboard"));
        }

        void on_save_copy () {
            save_copy.begin ();
        }

        async void save_copy () {
            if (doc_file == null) {
                return;
            }
            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Save a Copy");
            dialog.initial_name = doc_file.get_basename ();
            try {
                File file = yield dialog.save (this, null);
                file.replace_contents (editor.buffer.text.data, null, false, FileCreateFlags.NONE, null);
                toast (_("Saved a copy to %s").printf (Files.pretty_path (file.get_parent ())));
            } catch (Gtk.DialogError.DISMISSED e) {
            } catch (Error e) {
                toast (_("Could not save: %s").printf (e.message));
            }
        }

        void on_show_in_files () {
            if (doc_file != null && !doc_read_only) {
                new Gtk.FileLauncher (doc_file).open_containing_folder.begin (this, null);
            }
        }

        void on_file_show (SimpleAction action, Variant? param) {
            new Gtk.FileLauncher (File.new_for_path (param.get_string ())).open_containing_folder.begin (this, null);
        }

        /* ---- Helpers ---- */

        async string? ask_name (string heading, string initial, string confirm) {
            var dialog = new Adw.AlertDialog (heading, null);
            var entry = new Gtk.Entry ();
            entry.text = initial;
            entry.activates_default = true;
            dialog.extra_child = entry;
            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("ok", confirm);
            dialog.set_response_appearance ("ok", Adw.ResponseAppearance.SUGGESTED);
            dialog.default_response = "ok";
            dialog.close_response = "cancel";
            dialog.set_response_enabled ("ok", initial.strip () != "");
            entry.changed.connect (() => dialog.set_response_enabled ("ok", entry.text.strip () != ""));

            string response = yield dialog.choose (this, null);
            return response == "ok" ? entry.text.strip () : null;
        }

        void toast (string message) {
            toast_overlay.add_toast (new Adw.Toast (message));
        }
    }
}
