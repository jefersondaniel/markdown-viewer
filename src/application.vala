public class Notes.Application : Adw.Application {
    State state;

    public Application () {
        Object (application_id: Config.APP_ID,
                flags: ApplicationFlags.HANDLES_OPEN,
                resource_base_path: Config.RESOURCE_PATH);
    }

    protected override void startup () {
        base.startup ();
        GtkSource.init ();
        state = new State ();

        // Clicking into a rendered note shouldn't select a whole paragraph.
        Gtk.Settings.get_default ().gtk_label_select_on_focus = false;

        var css = new Gtk.CssProvider ();
        css.load_from_resource (Config.RESOURCE_PATH + "/app.css");
        Gtk.StyleContext.add_provider_for_display (Gdk.Display.get_default (), css,
                                                   Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1);

        var about = new SimpleAction ("about", null);
        about.activate.connect (show_about);
        add_action (about);
        var quit_action = new SimpleAction ("quit", null);
        quit_action.activate.connect (() => {
            foreach (var w in get_windows ()) {
                w.close ();
            }
        });
        add_action (quit_action);        set_accels_for_action ("win.new-note", { "<Control>n" });
        set_accels_for_action ("win.open", { "<Control>o" });
        set_accels_for_action ("win.open-folder", { "<Control><Shift>o" });
        set_accels_for_action ("win.save", { "<Control>s" });
        set_accels_for_action ("win.toggle-mode", { "<Control>e" });
        set_accels_for_action ("win.split", { "<Control>backslash" });
        set_accels_for_action ("win.find", { "<Control>f" });
        set_accels_for_action ("win.toggle-sidebar", { "F9" });
        set_accels_for_action ("win.go-back", { "<Alt>Left" });
        set_accels_for_action ("window.close", { "<Control>w" });
        set_accels_for_action ("app.quit", { "<Control>q" });
    }

    Window main_window () {
        var window = active_window as Window;
        if (window == null) {
            window = new Window (this, state);
        }
        return window;
    }

    protected override void activate () {
        main_window ().present ();
    }

    protected override void open (File[] files, string hint) {
        var window = main_window ();
        window.present ();
        foreach (var file in files) {
            if (file.query_file_type (FileQueryInfoFlags.NONE) == FileType.DIRECTORY) {
                window.open_folder (file);
            } else {
                window.open_file (file);
            }
        }
    }

    void show_about () {
        var about = new Adw.AboutDialog ();
        about.application_name = _("Notes");
        about.application_icon = Config.APP_ID;
        about.version = Config.VERSION;
        about.comments = _("Browse, read and write Markdown files");
        about.license_type = Gtk.License.GPL_3_0;
        about.present (active_window);
    }
}

int main (string[] args) {
    return new Notes.Application ().run (args);
}
