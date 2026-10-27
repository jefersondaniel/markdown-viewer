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
        [GtkChild] unowned Adw.Banner disk_banner;
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
            { "save-draft", on_save },
            { "discard-draft", on_discard_draft },
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

        /* A new note that exists only in memory until it is saved. `doc_file` is
         * null meanwhile, and `draft_dir` is where saving it suggests. */
        bool draft;
        File? draft_dir;
        bool close_confirmed;
        FileMonitor? doc_monitor;
        /* Where another program renamed the open file to, until it is checked. */
        File? doc_moved_to;
        /* The file changed on disk while there were unsaved edits here. Nothing is
         * saved until the user picks which version to keep. */
        bool disk_conflict;
        /* The text of the document as last read from or written to disk. */
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
        uint scroll_restore_source;
        ulong scroll_restore_handler;

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
            if (!close_confirmed && must_confirm_leave ()) {
                confirm_leave.begin ((obj, res) => {
                    if (confirm_leave.end (res)) {
                        close_confirmed = true;
                        close ();
                    }
                });
                return true;
            }
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

            if (must_confirm_leave ()) {
                confirm_leave.begin ((obj, res) => {
                    if (confirm_leave.end (res)) {
                        open_file (file, push_history);
                    } else {
                        file_tree.select_file (doc_file);
                    }
                });
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
            draft = false;
            reload_buffer (text, false);
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
            file_tree.select_file (doc_read_only ? null : doc_file);
            if (!doc_read_only) {
                state.set_string ("last-file", file.get_path ());
            }
            if (split_view.collapsed) {
                split_view.show_sidebar = false;
            }
        }

        /* Shows `text` in the editor as the saved version of the note. The
         * preview is rendered again unless the caller does it itself. */
        void reload_buffer (string text, bool render = true) {
            var buffer = editor.buffer;
            loading = true;
            buffer.begin_irreversible_action ();
            replace_changed_text (buffer, text);
            buffer.end_irreversible_action ();
            loading = false;
            saved_text = text;
            set_disk_conflict (false);

            preview_dirty = true;
            if (render) {
                render_preview (true);
            }
        }

        /* Replaces only the part that differs. Setting the whole text would move
         * the editor back to the top and the cursor away from where it was. */
        static void replace_changed_text (Gtk.TextBuffer buffer, string text) {
            string old = buffer.text;
            int max = int.min (old.length, text.length);
            int prefix = 0;
            while (prefix < max && old[prefix] == text[prefix]) {
                prefix++;
            }
            // Don't split a multibyte character.
            while (prefix > 0 && prefix < text.length && (text[prefix] & 0xC0) == 0x80) {
                prefix--;
            }
            int suffix = 0;
            while (suffix < max - prefix && old[old.length - 1 - suffix] == text[text.length - 1 - suffix]) {
                suffix++;
            }
            while (suffix > 0 && (text[text.length - suffix] & 0xC0) == 0x80) {
                suffix--;
            }
            if (prefix == old.length && prefix == text.length) {
                return;
            }

            Gtk.TextIter start, end;
            buffer.get_iter_at_offset (out start, (int) old.char_count (prefix));
            buffer.get_iter_at_offset (out end, (int) old.char_count (old.length - suffix));
            buffer.delete (ref start, ref end);
            buffer.insert (ref start, text.substring (prefix, text.length - suffix - prefix), -1);
        }

        /* Saves the current document and returns it, or null for a draft. */
        File? leave_document () {
            save_now ();
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
            stop_watching ();
            set_disk_conflict (false);
            doc_file = null;
            doc_read_only = false;
            draft = false;
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

        /* Notice when another program changes, moves or deletes the open file. The
         * monitor also sees editors that save by writing a new file and renaming it
         * over the old one. */
        void watch_document () {
            stop_watching ();
            if (doc_file == null || doc_read_only) {
                return;
            }
            try {
                doc_monitor = doc_file.monitor_file (FileMonitorFlags.WATCH_MOVES);
                doc_monitor.changed.connect ((file, other, event) => {
                    if (event == FileMonitorEvent.RENAMED && other != null && doc_file != null
                        && file.equal (doc_file)) {
                        doc_moved_to = other;
                    }
                    schedule_disk_check ();
                });
            } catch (Error e) {
                warning ("Could not watch %s: %s", doc_file.get_basename (), e.message);
            }
        }

        void stop_watching () {
            if (doc_monitor != null) {
                doc_monitor.cancel ();
                doc_monitor = null;
            }
            if (disk_check_source != 0) {
                Source.remove (disk_check_source);
                disk_check_source = 0;
            }
            doc_moved_to = null;
        }

        /* Changes usually come in bursts, so look at the file once they settle. */
        void schedule_disk_check () {
            if (disk_check_source != 0) {
                Source.remove (disk_check_source);
            }
            disk_check_source = Timeout.add (250, () => {
                disk_check_source = 0;
                check_document_on_disk ();
                return Source.REMOVE;
            });
        }

        /* Runs a check that is still waiting, so decisions use what is on disk now. */
        void flush_disk_check () {
            if (disk_check_source != 0) {
                Source.remove (disk_check_source);
                disk_check_source = 0;
                check_document_on_disk ();
            }
        }

        void check_document_on_disk () {
            if (doc_file == null || doc_read_only) {
                return;
            }
            File? moved_to = doc_moved_to;
            doc_moved_to = null;
            if (!doc_file.query_exists ()) {
                if (moved_to != null && moved_to.query_exists ()) {
                    relocate_document (doc_file, moved_to);
                } else {
                    document_removed ();
                }
                return;
            }
            string? text = Files.read_text (doc_file);
            if (text == null) {
                return;
            }
            string current = editor.buffer.text;
            if (text == saved_text) {
                // Our own save, or the other program put back what was saved last.
                if (disk_conflict) {
                    set_disk_conflict (false);
                    schedule_save ();
                }
            } else if (current == saved_text) {
                // Nothing would be lost, so just show the new version.
                reload_buffer (text);
            } else if (current == text) {
                saved_text = text;
                set_disk_conflict (false);
            } else {
                set_disk_conflict (true);
            }
        }

        /* The open file was deleted, or moved somewhere it can't be followed. */
        void document_removed () {
            string name = doc_file.get_basename ();
            if (editor.buffer.text == saved_text) {
                close_document ();
                toast (_("“%s” was moved or deleted").printf (name));
                return;
            }
            // Writing the file back would undo the deletion, so keep the edits as a draft.
            File? dir = doc_file.get_parent ();
            stop_watching ();
            set_disk_conflict (false);
            doc_file = null;
            draft = true;
            draft_dir = dir != null && dir.query_exists () ? dir : null;
            saved_text = "";
            update_header ();
            update_actions ();
            file_tree.select_file (null);
            toast (_("“%s” was moved or deleted, so your changes were kept in a draft").printf (name));
        }

        void set_disk_conflict (bool conflict) {
            disk_conflict = conflict;
            disk_banner.revealed = conflict;
            if (conflict && save_source != 0) {
                Source.remove (save_source);
                save_source = 0;
            }
        }

        [GtkCallback]
        void on_disk_banner_clicked () {
            resolve_disk_conflict.begin ();
        }

        /* Asks which version to keep after the file changed on disk while it had
         * unsaved edits. Returns false if the user chose neither. */
        async bool resolve_disk_conflict () {
            var dialog = new Adw.AlertDialog (
                _("Keep Your Changes?"),
                _("“%s” was changed by another program while you were editing it. Reload it to see those changes, or keep yours and replace them.")
                    .printf (doc_file.get_basename ()));
            dialog.add_response ("cancel", _("_Cancel"));
            dialog.add_response ("reload", _("_Discard and Reload"));
            dialog.add_response ("keep", _("_Keep Changes"));
            dialog.set_response_appearance ("reload", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.set_response_appearance ("keep", Adw.ResponseAppearance.SUGGESTED);
            dialog.default_response = "keep";
            dialog.close_response = "cancel";

            string response = yield dialog.choose (this, null);
            if (!disk_conflict) {
                return false;  // things changed while the dialog was open
            }
            switch (response) {
            case "keep":
                set_disk_conflict (false);
                return save_now (true);
            case "reload":
                string? text = Files.read_text (doc_file);
                if (text != null) {
                    reload_buffer (text);
                    return true;
                }
                check_document_on_disk ();
                return false;
            default:
                return false;
            }
        }

        void update_header () {
            if (draft) {
                window_title.title = _("New Note");
                window_title.subtitle = _("Draft");
                title = window_title.title;
                return;
            }
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
            bool has_doc = has_document ();
            bool editable_doc = doc_file != null && !doc_read_only;
            lookup ("new-folder").set_enabled (folder != null);
            lookup ("save").set_enabled (editable_doc || draft);
            lookup ("save-draft").set_enabled (draft);
            lookup ("discard-draft").set_enabled (draft);
            lookup ("rename-note").set_enabled (editable_doc);
            lookup ("trash-note").set_enabled (editable_doc);
            lookup ("show-in-files").set_enabled (editable_doc);
            lookup ("copy-markdown").set_enabled (has_doc);
            lookup ("save-copy").set_enabled (has_doc);
            lookup ("find").set_enabled (has_doc);
            lookup ("go-back").set_enabled (history.length > 0);
        }

        bool has_document () {
            return doc_file != null || draft;
        }

        /* A draft with something in it, which would be lost on leaving it. */
        bool unsaved_draft () {
            return draft && editor.buffer.text.strip () != "";
        }

        /* Whether leaving the open document needs a decision first, because it is
         * a draft with text or has edits that clash with changes on disk. */
        bool must_confirm_leave () {
            flush_disk_check ();
            return unsaved_draft () || disk_conflict;
        }

        /* Asks what to do before leaving the open document. Returns false to stay. */
        async bool confirm_leave () {
            if (disk_conflict) {
                return yield resolve_disk_conflict ();
            }
            return yield confirm_leave_draft ();
        }

        /* The folder that relative links and images in the document point into. */
        File? doc_dir () {
            return doc_file != null ? doc_file.get_parent () : draft_dir;
        }

        void schedule_save () {
            if (save_source != 0) {
                Source.remove (save_source);
                save_source = 0;
            }
            if (disk_conflict) {
                // Undoing every edit ends the conflict, so look at the file again.
                schedule_disk_check ();
                return;
            }
            save_source = Timeout.add (700, () => {
                save_source = 0;
                save_now ();
                return Source.REMOVE;
            });
        }

        /* Writes the open document. Unless `overwrite` is set, it doesn't replace
         * changes another program made since the last save, and doesn't recreate
         * the file if it was deleted. */
        bool save_now (bool overwrite = false) {
            if (save_source != 0) {
                Source.remove (save_source);
                save_source = 0;
            }
            if (doc_file == null || doc_read_only) {
                return true;
            }
            if (disk_conflict && !overwrite) {
                return false;
            }
            string text = editor.buffer.text;
            if (text == saved_text) {
                return true;
            }
            if (!overwrite) {
                if (!doc_file.query_exists ()) {
                    schedule_disk_check ();
                    return false;
                }
                string? on_disk = Files.read_text (doc_file);
                if (on_disk != saved_text) {
                    if (on_disk == text) {
                        saved_text = text;
                        return true;
                    }
                    set_disk_conflict (true);
                    return false;
                }
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
            if (!has_document () || !preview_scroller.visible || !preview_dirty) {
                return;
            }
            preview_dirty = false;

            var doc = new Markdown.Parser ().parse (editor.buffer.text);
            var r = new Markdown.Renderer ();
            r.base_dir = doc_dir ();
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

            stop_scroll_restore ();
            if (keep_scroll) {
                // Restore the position once the new content has been measured.
                scroll_restore_handler = adj.notify["upper"].connect (() => adj.value = position);
                scroll_restore_source = Timeout.add (250, () => {
                    scroll_restore_source = 0;
                    stop_scroll_restore ();
                    return Source.REMOVE;
                });
            } else {
                adj.value = 0;
            }
            update_find_count ();
        }

        /* A newer render or an explicit scroll replaces a pending restore, which
         * would otherwise put back the old position, even from another note. */
        void stop_scroll_restore () {
            if (scroll_restore_source != 0) {
                Source.remove (scroll_restore_source);
                scroll_restore_source = 0;
            }
            if (scroll_restore_handler != 0) {
                preview_scroller.vadjustment.disconnect (scroll_restore_handler);
                scroll_restore_handler = 0;
            }
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
                File? dir = doc_dir ();
                target = path.has_prefix ("/") || dir == null ? File.new_for_path (path) : dir.resolve_relative_path (path);
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
                stop_scroll_restore ();
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
            if (focus && editor_scroller.visible && has_document ()) {
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
            start_draft (target_dir ());
        }

        void on_new_note_in (SimpleAction action, Variant? param) {
            start_draft (File.new_for_path (param.get_string ()));
        }

        /* Opens a new, unsaved note. Nothing is written until it is saved. */
        void start_draft (File? dir, string text = "") {
            if (must_confirm_leave ()) {
                confirm_leave.begin ((obj, res) => {
                    if (confirm_leave.end (res)) {
                        start_draft (dir, text);
                    }
                });
                return;
            }
            File? previous = leave_document ();
            if (previous != null) {
                history.add (previous);
            }
            stop_watching ();
            doc_file = null;
            doc_read_only = false;
            draft = true;
            draft_dir = dir;
            reload_buffer (text);
            editor.editable = true;
            content_stack.visible_child_name = "document";
            editor_scroller.vadjustment.value = 0;
            update_header ();
            update_actions ();
            file_tree.select_file (null);
            if (split_view.collapsed) {
                split_view.show_sidebar = false;
            }
            activate_action_variant ("win.mode", new Variant.string ("edit"));
            editor.grab_focus ();
        }

        /* Asks what to do with a draft that is about to be left. Returns false to
         * stay on it. */
        async bool confirm_leave_draft () {
            var dialog = new Adw.AlertDialog (_("Save the New Note?"),
                                              _("The note hasn't been saved yet. If you don't save it, its text will be lost."));
            dialog.add_response ("cancel", _("_Cancel"));
            dialog.add_response ("discard", _("_Discard"));
            dialog.add_response ("save", _("_Save…"));
            dialog.set_response_appearance ("discard", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);
            dialog.default_response = "save";
            dialog.close_response = "cancel";

            switch (yield dialog.choose (this, null)) {
            case "save":
                return yield save_draft ();
            case "discard":
                draft = false;
                return true;
            default:
                return false;
            }
        }

        /* Asks where to save the draft and turns it into a regular document. */
        async bool save_draft () {
            string text = editor.buffer.text;
            string name = Files.sanitize_name (Files.derive_title (text, ""));
            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Save Note");
            if (name == "") {
                name = _("Untitled");
            }
            File? dir = draft_dir ?? folder;
            if (dir != null) {
                dialog.initial_folder = dir;
                name = Files.stem_of (Files.unique_child (dir, name, ".md").get_basename ());
            }
            dialog.initial_name = name + ".md";
            File file;
            try {
                file = yield dialog.save (this, null);
            } catch (Error e) {
                return false;  // cancelled
            }
            string? base_name = file.get_basename ();
            if (base_name != null && !base_name.contains (".")) {
                file = file.get_parent ().get_child (base_name + ".md");
            }
            try {
                file.replace_contents (text.data, null, false, FileCreateFlags.NONE, null);
            } catch (Error e) {
                toast (_("Could not save: %s").printf (e.message));
                return false;
            }
            if (!draft) {
                return true;  // the draft was left while the dialog was open
            }
            draft = false;
            doc_file = file;
            saved_text = text;
            watch_document ();
            update_header ();
            update_actions ();
            file_tree.select_file (doc_file);
            state.set_string ("last-file", file.get_path ());
            // Edits made while the dialog was open are saved as usual.
            schedule_save ();
            preview_dirty = true;
            render_preview (true);
            return true;
        }

        void on_discard_draft () {
            if (!draft) {
                return;
            }
            string text = editor.buffer.text;
            File? dir = draft_dir;
            close_document ();
            if (text.strip () == "") {
                return;
            }
            var t = new Adw.Toast (_("Note discarded"));
            t.button_label = _("Undo");
            t.button_clicked.connect (() => start_draft (dir, text));
            toast_overlay.add_toast (t);
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
            if (draft) {
                save_draft.begin ((obj, res) => {
                    if (save_draft.end (res)) {
                        toast (_("Saved"));
                    }
                });
                return;
            }
            if (disk_conflict) {
                resolve_disk_conflict.begin ((obj, res) => {
                    if (resolve_disk_conflict.end (res) && !disk_conflict) {
                        toast (_("Saved"));
                    }
                });
                return;
            }
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
            if (!has_document ()) {
                return;
            }
            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Save a Copy");
            dialog.initial_name = doc_file != null ? doc_file.get_basename () : _("Untitled") + ".md";
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
