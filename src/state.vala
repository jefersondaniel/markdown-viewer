/* Small persistent key/value state (window size, last note, favorites...).
 * A plain key file, so the app runs from the build directory without
 * installing a GSettings schema. */

public class Notes.State : Object {
    const string GROUP = "state";

    KeyFile file = new KeyFile ();
    string path;

    public State () {
        path = Path.build_filename (Environment.get_user_config_dir (), Config.APP_ID, "state.ini");
        try {
            file.load_from_file (path, KeyFileFlags.NONE);
        } catch (Error e) {
            // First run.
        }
    }

    public string get_string (string key, string fallback = "") {
        try {
            return file.get_string (GROUP, key);
        } catch (Error e) {
            return fallback;
        }
    }

    public void set_string (string key, string value) {
        file.set_string (GROUP, key, value);
    }

    public int get_int (string key, int fallback) {
        try {
            return file.get_integer (GROUP, key);
        } catch (Error e) {
            return fallback;
        }
    }

    public void set_int (string key, int value) {
        file.set_integer (GROUP, key, value);
    }

    public bool get_bool (string key, bool fallback) {
        try {
            return file.get_boolean (GROUP, key);
        } catch (Error e) {
            return fallback;
        }
    }

    public void set_bool (string key, bool value) {
        file.set_boolean (GROUP, key, value);
    }

    public string[] get_list (string key) {
        try {
            return file.get_string_list (GROUP, key);
        } catch (Error e) {
            return {};
        }
    }

    public void set_list (string key, string[] value) {
        file.set_string_list (GROUP, key, value);
    }

    public void save () {
        DirUtils.create_with_parents (Path.get_dirname (path), 0755);
        try {
            file.save_to_file (path);
        } catch (Error e) {
            warning ("Could not save state: %s", e.message);
        }
    }
}
