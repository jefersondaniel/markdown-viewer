/* The sidebar: a folder's subfolders and Markdown files as an expandable tree,
 * plus a search mode that lists matching files from the whole folder.
 *
 * Directory contents load lazily and stay up to date on their own through
 * Gtk.DirectoryList, which monitors each directory it lists. */

public class Notes.FileTree : Adw.Bin {
    public signal void file_activated (File file);
    public signal void context_menu (File file, bool is_dir, double x, double y);

    public File? folder { get; private set; }

    const string ATTRIBUTES = "standard::name,standard::display-name,standard::type,standard::is-hidden,standard::is-backup";

    Gtk.Stack stack;
    Gtk.ListView view;
    Gtk.SingleSelection selection;
    Gtk.TreeListModel? tree;
    Gtk.ListBox results;
    Gtk.Label results_status;
    Gtk.PopoverMenu menu_popover;

    File? pending_select;
    bool selecting;
    uint retry_source;
    uint search_source;
    Cancellable? search_cancellable;

    construct {
        selection = new Gtk.SingleSelection (null);
        selection.autoselect = false;
        selection.can_unselect = true;
        selection.notify["selected-item"].connect (on_selection_changed);

        var factory = new Gtk.SignalListItemFactory ();
        factory.setup.connect (setup_row);
        factory.bind.connect (bind_row);

        view = new Gtk.ListView (selection, factory);
        view.add_css_class ("navigation-sidebar");
        view.activate.connect (on_activate);

        var tree_scroller = new Gtk.ScrolledWindow ();
        tree_scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
        tree_scroller.child = view;

        results = new Gtk.ListBox ();
        results.add_css_class ("navigation-sidebar");
        results.row_activated.connect ((row) => file_activated (((ResultRow) row).file));
        results_status = new Gtk.Label (null);
        results_status.margin_top = 24;
        results_status.add_css_class ("dim-label");
        var results_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        results_box.append (results);
        results_box.append (results_status);
        var results_scroller = new Gtk.ScrolledWindow ();
        results_scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
        results_scroller.child = results_box;

        stack = new Gtk.Stack ();
        stack.add_named (tree_scroller, "tree");
        stack.add_named (results_scroller, "results");
        stack.vexpand = true;
        child = stack;

        menu_popover = new Gtk.PopoverMenu.from_model (null);
        menu_popover.has_arrow = false;
        menu_popover.halign = Gtk.Align.START;
        menu_popover.set_parent (this);
    }

    public override void dispose () {
        if (menu_popover != null) {
            menu_popover.unparent ();
            menu_popover = null;
        }
        if (search_cancellable != null) {
            search_cancellable.cancel ();
        }
        base.dispose ();
    }

    public override void size_allocate (int width, int height, int baseline) {
        base.size_allocate (width, height, baseline);
        menu_popover.present ();
    }

    /* ---- Model ---- */

    static File file_of (FileInfo info) {
        return (File) info.get_attribute_object ("standard::file");
    }

    static bool is_dir (FileInfo info) {
        return info.get_file_type () == FileType.DIRECTORY;
    }

    /* A directory's visible entries: folders first, then Markdown files. */
    static ListModel list_directory (File dir) {
        var list = new Gtk.DirectoryList (ATTRIBUTES, dir);
        var filter = new Gtk.CustomFilter ((obj) => {
            var info = (FileInfo) obj;
            string name = info.get_name ();
            if (name.has_prefix (".") || info.get_is_hidden () || info.get_is_backup ()) {
                return false;
            }
            return is_dir (info) || Files.is_markdown_name (name);
        });
        var sorter = new Gtk.CustomSorter ((a, b) => {
            var ia = (FileInfo) a;
            var ib = (FileInfo) b;
            if (is_dir (ia) != is_dir (ib)) {
                return is_dir (ia) ? -1 : 1;
            }
            int cmp = strcmp (ia.get_display_name ().collate_key_for_filename (),
                              ib.get_display_name ().collate_key_for_filename ());
            return cmp < 0 ? -1 : cmp > 0 ? 1 : 0;
        });
        return new Gtk.SortListModel (new Gtk.FilterListModel (list, filter), sorter);
    }

    public void load (File? dir) {
        folder = dir;
        pending_select = null;
        search ("");
        if (dir == null) {
            tree = null;
            selection.model = null;
            return;
        }
        tree = new Gtk.TreeListModel (list_directory (dir), false, false, (item) => {
            var info = (FileInfo) item;
            return is_dir (info) ? list_directory (file_of (info)) : null;
        });
        tree.items_changed.connect (schedule_retry);
        selection.model = tree;
    }

    /* The folder new files should go into: the selected folder, or the selected file's folder. */
    public File? selected_dir () {
        var row = selection.selected_item as Gtk.TreeListRow;
        if (row == null) {
            return null;
        }
        var info = (FileInfo) row.item;
        File file = file_of (info);
        return is_dir (info) ? file : file.get_parent ();
    }

    /* ---- Rows ---- */

    void setup_row (Object obj) {
        var item = (Gtk.ListItem) obj;
        var expander = new Gtk.TreeExpander ();
        expander.indent_for_icon = true;

        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        box.append (new Gtk.Image ());
        var label = new Gtk.Label (null);
        label.xalign = 0;
        label.hexpand = true;
        label.ellipsize = Pango.EllipsizeMode.END;
        box.append (label);
        expander.child = box;
        item.child = expander;

        var click = new Gtk.GestureClick ();
        click.button = 0;
        click.pressed.connect ((n, x, y) => {
            var row = item.item as Gtk.TreeListRow;
            if (row == null) {
                return;
            }
            var info = (FileInfo) row.item;
            if (click.get_current_button () == Gdk.BUTTON_SECONDARY) {
                Graphene.Point point;
                if (expander.compute_point (this, Graphene.Point () { x = (float) x, y = (float) y }, out point)) {
                    context_menu (file_of (info), is_dir (info), point.x, point.y);
                }
                return;
            }
            // A click anywhere on a folder row opens or closes it; the arrow already does this itself.
            if (click.get_current_button () == Gdk.BUTTON_PRIMARY && n == 1 && row.expandable) {
                var picked = expander.pick (x, y, Gtk.PickFlags.DEFAULT);
                if (picked == null || picked.get_css_name () != "expander") {
                    row.expanded = !row.expanded;
                }
            }
        });
        expander.add_controller (click);
    }

    void bind_row (Object obj) {
        var item = (Gtk.ListItem) obj;
        var row = (Gtk.TreeListRow) item.item;
        var expander = (Gtk.TreeExpander) item.child;
        expander.list_row = row;

        var info = (FileInfo) row.item;
        var icon = (Gtk.Image) expander.child.get_first_child ();
        var label = (Gtk.Label) icon.get_next_sibling ();
        bool dir = is_dir (info);
        icon.icon_name = dir ? "folder-symbolic" : "text-x-generic-symbolic";
        label.label = dir ? info.get_display_name () : Files.stem_of (info.get_display_name ());
    }

    void on_selection_changed () {
        if (selecting) {
            return;
        }
        var row = selection.selected_item as Gtk.TreeListRow;
        if (row == null) {
            return;
        }
        var info = (FileInfo) row.item;
        if (!is_dir (info)) {
            file_activated (file_of (info));
        }
    }

    void on_activate (uint position) {
        var row = tree != null ? tree.get_row (position) : null;
        if (row != null && row.expandable) {
            row.expanded = !row.expanded;
        }
    }

    /* ---- Selecting a file from outside ---- */

    /* Highlights `file`, opening the folders that lead to it. Directories load
     * asynchronously, so this keeps trying as their contents arrive. */
    public void select_file (File? file) {
        pending_select = file;
        if (file == null || folder == null || !file.has_prefix (folder)) {
            pending_select = null;
            selecting = true;
            selection.unselect_all ();
            selecting = false;
            return;
        }
        try_select ();
    }

    void schedule_retry () {
        if (pending_select != null && retry_source == 0) {
            retry_source = Idle.add (() => {
                retry_source = 0;
                try_select ();
                return Source.REMOVE;
            });
        }
    }

    void try_select () {
        if (pending_select == null || tree == null) {
            return;
        }
        uint n = tree.get_n_items ();
        for (uint i = 0; i < n; i++) {
            var row = tree.get_row (i);
            if (row == null) {
                continue;
            }
            File file = file_of ((FileInfo) row.item);
            if (file.equal (pending_select)) {
                pending_select = null;
                selecting = true;
                selection.selected = i;
                selecting = false;
                view.scroll_to (i, Gtk.ListScrollFlags.NONE, null);
                return;
            }
            if (row.expandable && !row.expanded && pending_select.has_prefix (file)) {
                row.expanded = true;  // its children arrive through items-changed
                return;
            }
        }
    }

    /* ---- Context menu ---- */

    public void popup_menu (MenuModel model, double x, double y) {
        menu_popover.menu_model = model;
        menu_popover.pointing_to = Gdk.Rectangle () { x = (int) x, y = (int) y, width = 1, height = 1 };
        menu_popover.popup ();
    }

    /* ---- Search ---- */

    class ResultRow : Gtk.ListBoxRow {
        public File file;

        public ResultRow (File file, string name, string location) {
            this.file = file;
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            box.margin_top = 4;
            box.margin_bottom = 4;
            var title = new Gtk.Label (name);
            title.xalign = 0;
            title.ellipsize = Pango.EllipsizeMode.END;
            box.append (title);
            var where = new Gtk.Label (location);
            where.xalign = 0;
            where.ellipsize = Pango.EllipsizeMode.MIDDLE;
            where.add_css_class ("caption");
            where.add_css_class ("dim-label");
            box.append (where);
            child = box;
        }
    }

    /* Shows files whose name or text contains `query`; an empty query shows the tree again. */
    public void search (string query) {
        if (search_source != 0) {
            Source.remove (search_source);
            search_source = 0;
        }
        if (search_cancellable != null) {
            search_cancellable.cancel ();
            search_cancellable = null;
        }
        if (query == "" || folder == null) {
            stack.visible_child_name = "tree";
            return;
        }
        search_source = Timeout.add (150, () => {
            search_source = 0;
            search_cancellable = new Cancellable ();
            run_search.begin (query.casefold (), search_cancellable);
            return Source.REMOVE;
        });
    }

    async void run_search (string query, Cancellable cancellable) {
        results.remove_all ();
        results_status.label = _("Searching…");
        results_status.visible = true;
        stack.visible_child_name = "results";

        int found = 0;
        var queue = new Queue<File> ();
        queue.push_tail (folder);
        while (!queue.is_empty () && found < 200) {
            File dir = queue.pop_head ();
            FileEnumerator enumerator;
            try {
                enumerator = yield dir.enumerate_children_async (
                    "standard::name,standard::display-name,standard::type,standard::is-hidden,standard::size",
                    FileQueryInfoFlags.NONE, Priority.LOW, cancellable);
            } catch (Error e) {
                if (e is IOError.CANCELLED) {
                    return;
                }
                continue;
            }

            while (true) {
                List<FileInfo> infos;
                try {
                    infos = yield enumerator.next_files_async (64, Priority.LOW, cancellable);
                } catch (Error e) {
                    if (e is IOError.CANCELLED) {
                        return;
                    }
                    break;
                }
                if (infos.length () == 0) {
                    break;
                }
                foreach (unowned FileInfo info in infos) {
                    string name = info.get_name ();
                    if (name.has_prefix (".") || info.get_is_hidden ()) {
                        continue;
                    }
                    File child = dir.get_child (name);
                    if (is_dir (info)) {
                        queue.push_tail (child);
                        continue;
                    }
                    if (!Files.is_markdown_name (name)) {
                        continue;
                    }
                    string stem = Files.stem_of (info.get_display_name ());
                    bool match = stem.casefold ().contains (query);
                    if (!match && info.get_size () < 2 * 1024 * 1024) {
                        try {
                            uint8[] data;
                            yield child.load_contents_async (cancellable, out data, null);
                            match = ((string) data).casefold ().contains (query);
                        } catch (Error e) {
                            if (e is IOError.CANCELLED) {
                                return;
                            }
                        }
                    }
                    if (cancellable.is_cancelled ()) {
                        return;
                    }
                    if (match) {
                        string? rel = folder.get_relative_path (dir);
                        results.append (new ResultRow (child, stem, rel != null && rel != "" ? rel : folder.get_basename ()));
                        found++;
                    }
                }
            }
        }
        results_status.label = _("No Results");
        results_status.visible = found == 0;
    }
}
