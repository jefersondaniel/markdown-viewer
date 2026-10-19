namespace Notes {

    enum Filter {
        ALL,
        FAVORITES,
        TRASH,
        FOLDER,
    }

    enum Mode {
        VIEW,
        EDIT,
    }

    class SidebarRow : Gtk.ListBoxRow {
        public Filter filter;
        public string folder;
        Gtk.Label count_label;

        public SidebarRow (Filter filter, string folder, string icon, string label, string icon_class) {
            this.filter = filter;
            this.folder = folder;

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            var image = new Gtk.Image.from_icon_name (icon);
            image.add_css_class (icon_class);
            box.append (image);

            var name = new Gtk.Label (label);
            name.xalign = 0;
            name.hexpand = true;
            name.ellipsize = Pango.EllipsizeMode.END;
            box.append (name);

            count_label = new Gtk.Label ("");
            count_label.add_css_class ("sidebar-count");
            box.append (count_label);
            child = box;
        }

        public void set_count (int count) {
            count_label.label = count > 0 ? count.to_string () : "";
        }
    }

    class NoteRow : Gtk.ListBoxRow {
        public Note note;

        public NoteRow (Note note) {
            this.note = note;
            add_css_class ("note-row");

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            var icon = new Gtk.Image.from_icon_name ("text-x-generic-symbolic");
            icon.valign = Gtk.Align.START;
            icon.add_css_class ("icon-note");
            box.append (icon);

            var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            text.hexpand = true;
            var title = new Gtk.Label (note.title);
            title.xalign = 0;
            title.ellipsize = Pango.EllipsizeMode.END;
            title.add_css_class ("note-row-title");
            text.append (title);

            var date = new Gtk.Label (format_date (note.modified));
            date.xalign = 0;
            date.add_css_class ("note-row-date");
            text.append (date);
            box.append (text);

            if (note.favorite) {
                var star = new Gtk.Image.from_icon_name ("starred-symbolic");
                star.valign = Gtk.Align.CENTER;
                star.add_css_class ("icon-favorite");
                star.add_css_class ("note-row-star");
                box.append (star);
            }
            child = box;
        }

        public static string format_date (DateTime when) {
            var local = when.to_local ();
            var now = new DateTime.now_local ();
            if (local.get_year () == now.get_year () && local.get_day_of_year () == now.get_day_of_year ()) {
                return _("Today, %s").printf (local.format ("%H:%M"));
            }
            var yesterday = now.add_days (-1);
            if (local.get_year () == yesterday.get_year () && local.get_day_of_year () == yesterday.get_day_of_year ()) {
                return _("Yesterday, %s").printf (local.format ("%H:%M"));
            }
            if (now.difference (local) < 6 * TimeSpan.DAY) {
                return local.format ("%A");
            }
            return local.format ("%b %-d, %Y");
        }
    }

    [GtkTemplate (ui = "/org/example/Notes/window.ui")]
    public class Window : Adw.ApplicationWindow {
        [GtkChild] unowned Adw.ToastOverlay toast_overlay;
        [GtkChild] unowned Adw.OverlaySplitView split_view;
        [GtkChild] unowned Gtk.SearchEntry search_entry;
        [GtkChild] unowned Gtk.ListBox collections_list;
        [GtkChild] unowned Gtk.ListBox folders_list;
        [GtkChild] unowned Gtk.Revealer folders_revealer;
        [GtkChild] unowned Gtk.Button folders_toggle;
        [GtkChild] unowned Gtk.Label notes_header;
        [GtkChild] unowned Gtk.Button empty_trash_button;
        [GtkChild] unowned Gtk.ListBox notes_list;
        [GtkChild] unowned Gtk.Label notes_empty;
        [GtkChild] unowned Gtk.Label title_label;
        [GtkChild] unowned Gtk.Label subtitle_label;
        [GtkChild] unowned Gtk.SearchBar find_bar;
        [GtkChild] unowned Gtk.SearchEntry find_entry;
        [GtkChild] unowned Gtk.Label find_count;
        [GtkChild] unowned Adw.Banner trash_banner;
        [GtkChild] unowned Gtk.Stack content_stack;
        [GtkChild] unowned Gtk.Paned paned;
        [GtkChild] unowned Gtk.ScrolledWindow editor_scroller;
        [GtkChild] unowned Gtk.ScrolledWindow preview_scroller;
        [GtkChild] unowned Adw.Clamp preview_clamp;

        State state;
        NoteStore store;
        Editor editor;
        Markdown.Renderer? renderer;
        GtkSource.SearchSettings search_settings;
        GtkSource.SearchContext search_context;

        SidebarRow all_row;
        SidebarRow favorites_row;
        SidebarRow trash_row;
        Gtk.PopoverMenu notes_menu;
        Gtk.PopoverMenu folders_menu;

        /* The open document. Notes from the library also have a Note. */
        File? doc_file;
        Note? doc_note;
        string saved_text = "";
        GenericArray<File> history = new GenericArray<File> ();

        Filter filter = Filter.ALL;
        string filter_folder = "";
        Mode mode = Mode.VIEW;
        bool split;
        bool loading;
        bool updating_sidebar;
        bool moving_document;  // the open file is being renamed/moved by us
        bool preview_dirty = true;
        string folders_signature = "";
        string notes_signature = "";
        int match_index = -1;
        uint save_source;
        uint render_source;

        const ActionEntry[] ACTIONS = {
            { "new-note", on_new_note },
            { "new-folder", on_new_folder },
            { "open", on_open },
            { "save", on_save },
            { "go-back", on_go_back },
            { "toggle-mode", on_toggle_mode },
            { "find", on_find },
            { "toggle-sidebar", on_toggle_sidebar },
            { "rename-note", on_rename_current },
            { "trash-note", on_trash_current },
            { "restore-current", on_restore_current },
            { "copy-markdown", on_copy_markdown },
            { "save-copy", on_save_copy },
            { "show-in-files", on_show_in_files },
            { "choose-library", on_choose_library },
            { "empty-trash", on_empty_trash },
            { "note-favorite", on_note_favorite, "s" },
            { "note-move", on_note_move, "(ss)" },
            { "note-rename", on_note_rename, "s" },
            { "note-trash", on_note_trash, "s" },
            { "note-restore", on_note_restore, "s" },
            { "note-delete", on_note_delete, "s" },
            { "folder-rename", on_folder_rename, "s" },
            { "folder-delete", on_folder_delete, "s" },
            { "mode", null, "s", "'view'", on_mode_changed },
            { "split", null, null, "false", on_split_changed },
            { "favorite", null, null, "false", on_favorite_changed },
        };

        public Window (Application app, State state) {
            Object (application: app);
            this.state = state;

            setup_editor ();
            setup_actions ();
            setup_sidebar ();
            setup_find ();
            setup_drop ();
            restore_state ();

            var style = Adw.StyleManager.get_default ();
            editor.set_dark (style.dark);
            style.notify["dark"].connect (() => {
                editor.set_dark (style.dark);
                preview_dirty = true;
                render_preview (true);
            });

            open_library (state.get_string ("library", default_library ()));
            open_initial_document ();
        }

        static string default_library () {
            string docs = Environment.get_user_special_dir (UserDirectory.DOCUMENTS) ?? Environment.get_home_dir ();
            return Path.build_filename (docs, "Notes");
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

        void setup_actions () {
            add_action_entries (ACTIONS, this);
        }

        void setup_sidebar () {
            all_row = new SidebarRow (Filter.ALL, "", "text-x-generic-symbolic", _("All Notes"), "icon-note");
            favorites_row = new SidebarRow (Filter.FAVORITES, "", "starred-symbolic", _("Favorites"), "icon-favorite");
            trash_row = new SidebarRow (Filter.TRASH, "", "user-trash-symbolic", _("Trash"), "icon-trash");
            collections_list.append (all_row);
            collections_list.append (favorites_row);
            collections_list.append (trash_row);

            collections_list.row_selected.connect ((row) => {
                if (updating_sidebar || row == null) {
                    return;
                }
                updating_sidebar = true;
                folders_list.unselect_all ();
                updating_sidebar = false;
                set_filter (((SidebarRow) row).filter, "");
            });
            folders_list.row_selected.connect ((row) => {
                if (updating_sidebar || row == null) {
                    return;
                }
                updating_sidebar = true;
                collections_list.unselect_all ();
                updating_sidebar = false;
                set_filter (Filter.FOLDER, ((SidebarRow) row).folder);
            });
            notes_list.row_selected.connect ((row) => {
                if (updating_sidebar || row == null) {
                    return;
                }
                open_file (((NoteRow) row).note.file);
            });
            search_entry.search_changed.connect (() => refresh_notes (true));

            notes_menu = new Gtk.PopoverMenu.from_model (null);
            notes_menu.has_arrow = false;
            notes_menu.halign = Gtk.Align.START;
            // Parented to the sidebar column: a ListBox would treat it as a row.
            notes_menu.set_parent (notes_list.get_parent ());
            var notes_click = new Gtk.GestureClick ();
            notes_click.button = Gdk.BUTTON_SECONDARY;
            notes_click.pressed.connect ((n, x, y) => {
                var row = notes_list.get_row_at_y ((int) y) as NoteRow;
                if (row != null) {
                    show_note_menu (row.note, notes_list, x, y);
                }
            });
            notes_list.add_controller (notes_click);

            folders_menu = new Gtk.PopoverMenu.from_model (null);
            folders_menu.has_arrow = false;
            folders_menu.halign = Gtk.Align.START;
            folders_menu.set_parent (notes_list.get_parent ());
            var folders_click = new Gtk.GestureClick ();
            folders_click.button = Gdk.BUTTON_SECONDARY;
            folders_click.pressed.connect ((n, x, y) => {
                var row = folders_list.get_row_at_y ((int) y) as SidebarRow;
                if (row != null) {
                    show_folder_menu (row.folder, folders_list, x, y);
                }
            });
            folders_list.add_controller (folders_click);
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
                    string? name = file.get_basename ();
                    if (name != null && NoteStore.is_markdown_name (name)) {
                        open_file (file);
                        return true;
                    }
                }
                return false;
            });
            content_stack.add_controller (drop);
        }

        void restore_state () {
            set_default_size (state.get_int ("width", 1180), state.get_int ("height", 820));
            if (state.get_bool ("maximized", false)) {
                maximize ();
            }
            split_view.show_sidebar = state.get_bool ("sidebar", true);
            folders_revealer.reveal_child = state.get_bool ("folders-expanded", true);
            update_folders_toggle ();
            split = state.get_bool ("split", false);
            mode = state.get_string ("mode", "view") == "edit" ? Mode.EDIT : Mode.VIEW;
            lookup (("split")).set_state (new Variant.boolean (split));
            lookup ("mode").set_state (new Variant.string (mode == Mode.EDIT ? "edit" : "view"));
            apply_mode (false);
            update_actions ();
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
            state.set_bool ("folders-expanded", folders_revealer.reveal_child);
            state.set_bool ("split", split);
            state.set_string ("mode", mode == Mode.EDIT ? "edit" : "view");
            state.set_string ("last-file", doc_file != null ? doc_file.get_path () : "");
            state.save ();
            notes_menu.unparent ();
            folders_menu.unparent ();
            return false;
        }

        /* ---- Library ---- */

        void open_library (string path) {
            store = new NoteStore (File.new_for_path (path), state.get_list ("favorites"));
            store.changed.connect (on_store_changed);
            store.favorites_changed.connect (() => {
                state.set_list ("favorites", store.favorite_list ());
                state.save ();
            });

            if (!state.get_bool ("initialized", false)) {
                state.set_bool ("initialized", true);
                state.save ();
                if (store.notes.length == 0) {
                    try {
                        var bytes = resources_lookup_data (Config.RESOURCE_PATH + "/welcome.md", ResourceLookupFlags.NONE);
                        store.create_note_with (_("Getting Started"), (string) bytes.get_data ());
                    } catch (Error e) {
                        warning ("Could not create the welcome note: %s", e.message);
                    }
                }
            }
            folders_signature = "";
            notes_signature = "";
            refresh_sidebar ();
        }

        void open_initial_document () {
            string last = state.get_string ("last-file");
            if (last != "" && FileUtils.test (last, FileTest.EXISTS)) {
                open_file (File.new_for_path (last), false);
                return;
            }
            var visible = visible_notes ();
            if (visible.length > 0) {
                open_file (visible[0].file, false);
            } else {
                close_document ();
            }
        }

        void on_store_changed () {
            if (moving_document) {
                // The window updates the document's location itself.
            } else if (doc_file != null && !doc_file.query_exists ()) {
                close_document ();
                toast (_("The note was moved or deleted"));
            } else if (doc_file != null) {
                doc_note = store.find (doc_file);
                // Pick up changes made by other programs, unless we have unsaved edits.
                if (doc_note != null && doc_note.content != saved_text && editor.buffer.text == saved_text) {
                    reload_buffer (doc_note.content);
                }
            }
            refresh_sidebar ();
            update_header ();
        }

        /* ---- Sidebar ---- */

        void set_filter (Filter f, string folder) {
            filter = f;
            filter_folder = folder;
            refresh_notes (true);
        }

        void refresh_sidebar () {
            int all = 0, favorites = 0, trashed = 0;
            var per_folder = new HashTable<string, int> (str_hash, str_equal);
            for (int k = 0; k < store.notes.length; k++) {
                Note note = store.notes[k];
                if (note.trashed) {
                    trashed++;
                    continue;
                }
                all++;
                if (note.favorite) {
                    favorites++;
                }
                per_folder.insert (note.folder, per_folder.lookup (note.folder) + 1);
            }
            all_row.set_count (all);
            favorites_row.set_count (favorites);
            trash_row.set_count (trashed);

            var sig = new StringBuilder ();
            for (int k = 0; k < store.folders.length; k++) {
                sig.append_printf ("%s:%d/", store.folders[k], per_folder.lookup (store.folders[k]));
            }

            updating_sidebar = true;
            if (sig.str != folders_signature) {
                folders_signature = sig.str;
                folders_list.remove_all ();
                for (int k = 0; k < store.folders.length; k++) {
                    string name = store.folders[k];
                    var row = new SidebarRow (Filter.FOLDER, name, "folder-symbolic", name, "icon-folder");
                    row.set_count (per_folder.lookup (name));
                    folders_list.append (row);
                }
            }

            bool folder_exists = false;
            for (int k = 0; k < store.folders.length; k++) {
                if (store.folders[k] == filter_folder) {
                    folder_exists = true;
                }
            }
            if (filter == Filter.FOLDER && !folder_exists) {
                filter = Filter.ALL;
            }

            collections_list.unselect_all ();
            folders_list.unselect_all ();
            if (filter == Filter.FOLDER) {
                for (int k = 0;; k++) {
                    var row = folders_list.get_row_at_index (k) as SidebarRow;
                    if (row == null) {
                        break;
                    }
                    if (row.folder == filter_folder) {
                        folders_list.select_row (row);
                    }
                }
            } else {
                collections_list.select_row (filter == Filter.ALL ? all_row : filter == Filter.FAVORITES ? favorites_row : trash_row);
            }
            updating_sidebar = false;
            refresh_notes (false);
        }

        string search_query () {
            return search_entry.text.strip ().casefold ();
        }

        GenericArray<Note> visible_notes () {
            var list = new GenericArray<Note> ();
            string query = search_query ();
            for (int k = 0; k < store.notes.length; k++) {
                Note note = store.notes[k];
                bool keep;
                if (query != "") {
                    keep = !note.trashed && (note.title.casefold ().contains (query) || note.content.casefold ().contains (query));
                } else {
                    switch (filter) {
                    case Filter.FAVORITES:
                        keep = note.favorite;
                        break;
                    case Filter.TRASH:
                        keep = note.trashed;
                        break;
                    case Filter.FOLDER:
                        keep = !note.trashed && note.folder == filter_folder;
                        break;
                    default:
                        keep = !note.trashed;
                        break;
                    }
                }
                if (keep) {
                    list.add (note);
                }
            }
            list.sort ((a, b) => b.modified.compare (a.modified));
            return list;
        }

        void refresh_notes (bool force) {
            var list = visible_notes ();
            bool searching = search_query () != "";

            var sig = new StringBuilder ();
            for (int k = 0; k < list.length; k++) {
                Note note = list[k];
                sig.append_printf ("%s|%s|%s|%s\n", note.file.get_path (), note.title,
                                   NoteRow.format_date (note.modified), note.favorite ? "*" : "");
            }
            if (force || sig.str != notes_signature) {
                notes_signature = sig.str;
                updating_sidebar = true;
                notes_list.remove_all ();
                for (int k = 0; k < list.length; k++) {
                    notes_list.append (new NoteRow (list[k]));
                }
                updating_sidebar = false;
            }

            if (searching) {
                notes_header.label = _("Results");
            } else if (filter == Filter.FOLDER) {
                notes_header.label = filter_folder;
            } else if (filter == Filter.FAVORITES) {
                notes_header.label = _("Favorites");
            } else if (filter == Filter.TRASH) {
                notes_header.label = _("Trash");
            } else {
                notes_header.label = _("Notes");
            }
            notes_empty.visible = list.length == 0;
            notes_empty.label = searching ? _("No Results") : filter == Filter.TRASH ? _("Trash is Empty") : _("No Notes");
            empty_trash_button.visible = filter == Filter.TRASH && !searching && list.length > 0;
            select_current_note ();
        }

        void select_current_note () {
            updating_sidebar = true;
            Gtk.ListBoxRow? match = null;
            for (int k = 0;; k++) {
                var row = notes_list.get_row_at_index (k) as NoteRow;
                if (row == null) {
                    break;
                }
                if (doc_note != null && row.note == doc_note) {
                    match = row;
                    break;
                }
            }
            if (match != null) {
                notes_list.select_row (match);
            } else {
                notes_list.unselect_all ();
            }
            updating_sidebar = false;
        }

        [GtkCallback]
        void on_folders_toggle () {
            folders_revealer.reveal_child = !folders_revealer.reveal_child;
            update_folders_toggle ();
        }

        void update_folders_toggle () {
            bool open = folders_revealer.reveal_child;
            folders_toggle.icon_name = open ? "pan-up-symbolic" : "pan-down-symbolic";
            folders_toggle.tooltip_text = open ? _("Collapse Folders") : _("Expand Folders");
        }

        [GtkCallback]
        void on_show_sidebar () {
            split_view.show_sidebar = true;
        }

        void show_note_menu (Note note, Gtk.Widget origin, double x, double y) {
            string path = note.file.get_path ();
            var menu = new Menu ();
            if (note.trashed) {
                menu.append (_("Restore"), Action.print_detailed_name ("win.note-restore", path));
                menu.append (_("Delete Permanently"), Action.print_detailed_name ("win.note-delete", path));
            } else {
                var main = new Menu ();
                main.append (note.favorite ? _("Remove from Favorites") : _("Add to Favorites"),
                             Action.print_detailed_name ("win.note-favorite", path));
                main.append (_("Rename…"), Action.print_detailed_name ("win.note-rename", path));

                var move = new Menu ();
                if (note.folder != "") {
                    move.append (_("No Folder"), Action.print_detailed_name ("win.note-move", new Variant ("(ss)", path, "")));
                }
                for (int k = 0; k < store.folders.length; k++) {
                    string folder = store.folders[k];
                    if (folder != note.folder) {
                        move.append (folder, Action.print_detailed_name ("win.note-move", new Variant ("(ss)", path, folder)));
                    }
                }
                if (move.get_n_items () > 0) {
                    main.append_submenu (_("Move To"), move);
                }
                menu.append_section (null, main);

                var danger = new Menu ();
                danger.append (_("Move to Trash"), Action.print_detailed_name ("win.note-trash", path));
                menu.append_section (null, danger);
            }
            popup_menu (notes_menu, menu, origin, x, y);
        }

        void show_folder_menu (string folder, Gtk.Widget origin, double x, double y) {
            var menu = new Menu ();
            menu.append (_("Rename…"), Action.print_detailed_name ("win.folder-rename", folder));
            menu.append (_("Delete Folder"), Action.print_detailed_name ("win.folder-delete", folder));
            popup_menu (folders_menu, menu, origin, x, y);
        }

        static void popup_menu (Gtk.PopoverMenu popover, Menu menu, Gtk.Widget origin, double x, double y) {
            Graphene.Point point;
            if (!origin.compute_point (popover.get_parent (), Graphene.Point () { x = (float) x, y = (float) y }, out point)) {
                return;
            }
            popover.menu_model = menu;
            popover.pointing_to = Gdk.Rectangle () { x = (int) point.x, y = (int) point.y, width = 1, height = 1 };
            popover.popup ();
        }

        /* ---- Documents ---- */

        public void open_file (File file, bool push_history = true) {
            if (doc_file != null && doc_file.equal (file)) {
                if (split_view.collapsed) {
                    split_view.show_sidebar = false;
                }
                return;
            }

            string text;
            try {
                uint8[] data;
                file.load_contents (null, out data, null);
                text = (string) data;
            } catch (Error e) {
                toast (_("Could not open “%s”").printf (file.get_basename ()));
                return;
            }
            if (!text.validate ()) {
                toast (_("“%s” is not a text file").printf (file.get_basename ()));
                return;
            }

            File? previous = leave_document ();
            if (push_history && previous != null) {
                history.add (previous);
            }

            doc_file = file;
            doc_note = store.find (file);
            reload_buffer (text);
            Gtk.TextIter start;
            editor.buffer.get_start_iter (out start);
            editor.buffer.place_cursor (start);

            bool trashed = doc_note != null && doc_note.trashed;
            editor.editable = !trashed;
            trash_banner.revealed = trashed;
            content_stack.visible_child_name = "document";
            editor_scroller.vadjustment.value = 0;

            update_header ();
            update_actions ();
            preview_dirty = true;
            render_preview (false);
            if (find_bar.search_mode_enabled) {
                run_find ();
            }
            select_current_note ();
            state.set_string ("last-file", file.get_path ());

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

        /* Saves the current document and gives untitled notes a name from their
         * first line. Returns the document's final location. */
        File? leave_document () {
            if (doc_file == null) {
                return null;
            }
            save_now ();
            if (doc_note != null && !doc_note.trashed
                && /^Untitled( \d+)?$/.match (NoteStore.stem_of (doc_file.get_basename ()))) {
                string title = NoteStore.derive_title (saved_text, "");
                if (title != "") {
                    try {
                        moving_document = true;
                        File renamed = store.rename_note (doc_note, title);
                        replace_in_history (doc_file, renamed);
                        doc_file = renamed;
                        doc_note = store.find (renamed);
                    } catch (Error e) {
                        warning ("Could not rename note: %s", e.message);
                    }
                    moving_document = false;
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
            doc_file = null;
            doc_note = null;
            loading = true;
            editor.buffer.text = "";
            loading = false;
            saved_text = "";
            preview_clamp.child = null;
            renderer = null;
            trash_banner.revealed = false;
            content_stack.visible_child_name = "empty";
            update_header ();
            update_actions ();
            select_current_note ();
        }

        void update_header () {
            if (doc_file == null) {
                title_label.label = _("Notes");
                subtitle_label.label = "";
                subtitle_label.visible = false;
                title = _("Notes");
                return;
            }
            string name = doc_note != null ? doc_note.title
                : NoteStore.derive_title (saved_text, NoteStore.stem_of (doc_file.get_basename ()));
            title_label.label = name;
            title = name;
            subtitle_label.label = pretty_path (doc_file.get_parent ());
            subtitle_label.visible = true;
        }

        static string pretty_path (File? dir) {
            if (dir == null) {
                return "";
            }
            string path = dir.get_path () ?? dir.get_uri ();
            string home = Environment.get_home_dir ();
            if (path.has_prefix (home)) {
                path = "~" + path.substring (home.length);
            }
            return path;
        }

        void update_actions () {
            bool has_doc = doc_file != null;
            bool in_library = doc_note != null && !doc_note.trashed;
            lookup ("save").set_enabled (has_doc);
            lookup ("copy-markdown").set_enabled (has_doc);
            lookup ("save-copy").set_enabled (has_doc);
            lookup ("show-in-files").set_enabled (has_doc);
            lookup ("find").set_enabled (has_doc);
            lookup ("rename-note").set_enabled (in_library);
            lookup ("trash-note").set_enabled (in_library);
            lookup ("favorite").set_enabled (in_library);
            lookup ("favorite").set_state (new Variant.boolean (in_library && doc_note.favorite));
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
            if (doc_file == null) {
                return true;
            }
            string text = editor.buffer.text;
            if (text == saved_text) {
                return true;
            }
            try {
                doc_file.replace_contents (text.data, null, false, FileCreateFlags.NONE, null);
                saved_text = text;
                if (doc_note != null) {
                    store.note_saved (doc_note, text);
                    refresh_notes (false);
                }
                update_header ();
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
            r.read_only = doc_note != null && doc_note.trashed;
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
            preview_clamp.child = content;
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

            if (NoteStore.is_markdown_name (target.get_basename ())) {
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
            apply_mode (true);
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

        bool finding_in_editor () {
            return editor_scroller.visible && !preview_scroller.visible;
        }

        void update_find_count () {
            if (find_entry.text == "") {
                find_count.label = "";
                return;
            }
            int count = finding_in_editor () ? search_context.occurrences_count
                : (renderer != null ? renderer.match_count : 0);
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
            leave_document ();
            if (filter == Filter.TRASH || filter == Filter.FAVORITES) {
                filter = Filter.ALL;
            }
            if (search_entry.text != "") {
                search_entry.text = "";
            }
            try {
                File file = store.create_note (filter == Filter.FOLDER ? filter_folder : "");
                refresh_sidebar ();
                open_file (file);
                activate_action_variant ("win.mode", new Variant.string ("edit"));
                editor.grab_focus ();
            } catch (Error e) {
                toast (_("Could not create the note: %s").printf (e.message));
            }
        }

        void on_new_folder () {
            ask_name.begin (_("New Folder"), "", _("Create"), (obj, res) => {
                string? name = ask_name.end (res);
                if (name == null) {
                    return;
                }
                try {
                    store.create_folder (name);
                } catch (Error e) {
                    toast (_("Could not create the folder: %s").printf (e.message));
                }
            });
        }

        void on_open () {
            open_dialog.begin ();
        }

        async void open_dialog () {
            var filter = new Gtk.FileFilter ();
            filter.name = _("Markdown");
            filter.add_mime_type ("text/markdown");
            filter.add_suffix ("md");
            filter.add_suffix ("markdown");
            var all = new Gtk.FileFilter ();
            all.name = _("All Files");
            all.add_pattern ("*");
            var filters = new ListStore (typeof (Gtk.FileFilter));
            filters.append (filter);
            filters.append (all);

            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Open Markdown File");
            dialog.filters = filters;
            dialog.default_filter = filter;
            try {
                File file = yield dialog.open (this, null);
                open_file (file);
            } catch (Error e) {
                // Cancelled.
            }
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

        void on_favorite_changed (SimpleAction action, Variant value) {
            if (doc_note == null) {
                return;
            }
            action.set_state (value);
            store.set_favorite (doc_note, value.get_boolean ());
        }

        void on_rename_current () {
            if (doc_note != null) {
                rename_note (doc_note);
            }
        }

        void rename_note (Note note) {
            save_now ();
            ask_name.begin (_("Rename Note"), NoteStore.stem_of (note.file.get_basename ()), _("Rename"), (obj, res) => {
                string? name = ask_name.end (res);
                if (name == null) {
                    return;
                }
                bool is_current = note == doc_note;
                moving_document = is_current;
                try {
                    File old_file = note.file;
                    File renamed = store.rename_note (note, name);
                    replace_in_history (old_file, renamed);
                    if (is_current) {
                        doc_file = renamed;
                        doc_note = store.find (renamed);
                        update_header ();
                        update_actions ();
                        select_current_note ();
                    }
                } catch (Error e) {
                    toast (_("Could not rename: %s").printf (e.message));
                }
                moving_document = false;
            });
        }

        void on_trash_current () {
            if (doc_note != null) {
                trash_note (doc_note);
            }
        }

        void trash_note (Note note) {
            bool is_current = note == doc_note;
            if (is_current) {
                save_now ();
            }
            moving_document = is_current;
            try {
                File trashed = store.trash (note);
                moving_document = false;
                if (is_current) {
                    doc_file = null;
                    doc_note = null;
                    var visible = visible_notes ();
                    if (visible.length > 0) {
                        open_file (visible[0].file, false);
                    } else {
                        close_document ();
                    }
                }
                var t = new Adw.Toast (_("Note moved to the Trash"));
                t.button_label = _("Undo");
                t.button_clicked.connect (() => {
                    Note? n = store.find (trashed);
                    if (n == null) {
                        return;
                    }
                    try {
                        open_file (store.restore (n));
                    } catch (Error e) {
                        toast (_("Could not restore: %s").printf (e.message));
                    }
                });
                toast_overlay.add_toast (t);
            } catch (Error e) {
                moving_document = false;
                toast (_("Could not move to the Trash: %s").printf (e.message));
            }
        }

        void on_restore_current () {
            if (doc_note == null || !doc_note.trashed) {
                return;
            }
            try {
                moving_document = true;
                File restored = store.restore (doc_note);
                moving_document = false;
                doc_file = null;
                doc_note = null;
                open_file (restored, false);
            } catch (Error e) {
                moving_document = false;
                toast (_("Could not restore: %s").printf (e.message));
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
                toast (_("Saved a copy to %s").printf (pretty_path (file.get_parent ())));
            } catch (Gtk.DialogError.DISMISSED e) {
            } catch (Error e) {
                toast (_("Could not save: %s").printf (e.message));
            }
        }

        void on_show_in_files () {
            if (doc_file != null) {
                new Gtk.FileLauncher (doc_file).open_containing_folder.begin (this, null);
            }
        }

        void on_choose_library () {
            choose_library.begin ();
        }

        async void choose_library () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Choose Notes Folder");
            dialog.initial_folder = store.root;
            try {
                File folder = yield dialog.select_folder (this, null);
                leave_document ();
                close_document ();
                history = new GenericArray<File> ();
                state.set_string ("library", folder.get_path ());
                state.save ();
                filter = Filter.ALL;
                open_library (folder.get_path ());
                open_initial_document ();
            } catch (Error e) {
                // Cancelled.
            }
        }

        void on_empty_trash () {
            var dialog = new Adw.AlertDialog (_("Empty Trash?"), _("All notes in the Trash will be permanently deleted."));
            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("empty", _("Empty Trash"));
            dialog.set_response_appearance ("empty", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.default_response = "cancel";
            dialog.response.connect ((response) => {
                if (response != "empty") {
                    return;
                }
                if (doc_note != null && doc_note.trashed) {
                    close_document ();
                }
                try {
                    store.empty_trash ();
                } catch (Error e) {
                    toast (_("Could not empty the Trash: %s").printf (e.message));
                }
            });
            dialog.present (this);
        }

        void on_note_favorite (SimpleAction action, Variant? param) {
            Note? note = store.find_path (param.get_string ());
            if (note != null) {
                store.set_favorite (note, !note.favorite);
                update_actions ();
            }
        }

        void on_note_move (SimpleAction action, Variant? param) {
            string path, folder;
            param.get ("(ss)", out path, out folder);
            Note? note = store.find_path (path);
            if (note == null) {
                return;
            }
            bool is_current = note == doc_note;
            if (is_current) {
                save_now ();
            }
            moving_document = is_current;
            try {
                File moved = store.move_to_folder (note, folder);
                replace_in_history (note.file, moved);
                if (is_current) {
                    doc_file = moved;
                    doc_note = store.find (moved);
                    update_header ();
                    select_current_note ();
                }
            } catch (Error e) {
                toast (_("Could not move the note: %s").printf (e.message));
            }
            moving_document = false;
        }

        void on_note_rename (SimpleAction action, Variant? param) {
            Note? note = store.find_path (param.get_string ());
            if (note != null) {
                rename_note (note);
            }
        }

        void on_note_trash (SimpleAction action, Variant? param) {
            Note? note = store.find_path (param.get_string ());
            if (note != null) {
                trash_note (note);
            }
        }

        void on_note_restore (SimpleAction action, Variant? param) {
            Note? note = store.find_path (param.get_string ());
            if (note == null) {
                return;
            }
            bool is_current = note == doc_note;
            moving_document = is_current;
            try {
                File restored = store.restore (note);
                moving_document = false;
                if (is_current) {
                    doc_file = null;
                    doc_note = null;
                    open_file (restored, false);
                }
            } catch (Error e) {
                moving_document = false;
                toast (_("Could not restore: %s").printf (e.message));
            }
        }

        void on_note_delete (SimpleAction action, Variant? param) {
            Note? note = store.find_path (param.get_string ());
            if (note == null) {
                return;
            }
            var dialog = new Adw.AlertDialog (_("Delete Permanently?"),
                                              _("“%s” will be deleted. This cannot be undone.").printf (note.title));
            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("delete", _("Delete"));
            dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.default_response = "cancel";
            dialog.response.connect ((response) => {
                if (response != "delete") {
                    return;
                }
                if (note == doc_note) {
                    close_document ();
                }
                try {
                    store.delete_forever (note);
                } catch (Error e) {
                    toast (_("Could not delete: %s").printf (e.message));
                }
            });
            dialog.present (this);
        }

        void on_folder_rename (SimpleAction action, Variant? param) {
            string folder = param.get_string ();
            ask_name.begin (_("Rename Folder"), folder, _("Rename"), (obj, res) => {
                string? name = ask_name.end (res);
                if (name == null) {
                    return;
                }
                save_now ();
                bool current_inside = doc_note != null && !doc_note.trashed && doc_note.folder == folder;
                string doc_name = doc_file != null ? doc_file.get_basename () : "";
                moving_document = current_inside;
                try {
                    store.rename_folder (folder, name);
                    if (filter == Filter.FOLDER && filter_folder == folder) {
                        filter_folder = NoteStore.sanitize_name (name);
                    }
                    if (current_inside) {
                        doc_file = store.root.get_child (NoteStore.sanitize_name (name)).get_child (doc_name);
                        doc_note = store.find (doc_file);
                        update_header ();
                    }
                    folders_signature = "";
                    refresh_sidebar ();
                } catch (Error e) {
                    toast (_("Could not rename the folder: %s").printf (e.message));
                }
                moving_document = false;
            });
        }

        void on_folder_delete (SimpleAction action, Variant? param) {
            string folder = param.get_string ();
            var dialog = new Adw.AlertDialog (_("Delete Folder?"),
                                              _("The notes in “%s” will be moved to the Trash.").printf (folder));
            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("delete", _("Delete"));
            dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.default_response = "cancel";
            dialog.response.connect ((response) => {
                if (response != "delete") {
                    return;
                }
                if (doc_note != null && !doc_note.trashed && doc_note.folder == folder) {
                    save_now ();
                    close_document ();
                }
                try {
                    store.delete_folder (folder);
                } catch (Error e) {
                    toast (_("Could not delete the folder: %s").printf (e.message));
                }
            });
            dialog.present (this);
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
