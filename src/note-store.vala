/* The notes library: a directory of Markdown files.
 *
 *   <root>/*.md              notes without a folder
 *   <root>/<Folder>/*.md     notes in a folder (one level deep)
 *   <root>/.trash/...        trashed notes, keeping their folder layout
 *
 * Note objects are kept stable across reloads (keyed by path) so the window
 * can hold on to them.
 */

namespace Notes {

    public class Note : Object {
        public File file;
        public string title = "";
        public string content = "";
        public string folder = "";
        public string relpath = "";
        public bool trashed;
        public bool favorite;
        public DateTime modified;

        public Note (File file) {
            this.file = file;
            modified = new DateTime.now_local ();
        }
    }

    public class NoteStore : Object {
        public File root { get; private set; }
        public File trash_dir { get; private set; }
        public GenericArray<Note> notes = new GenericArray<Note> ();
        public GenericArray<string> folders = new GenericArray<string> ();

        public signal void changed ();
        public signal void favorites_changed ();

        HashTable<string, Note> by_path = new HashTable<string, Note> (str_hash, str_equal);
        HashTable<string, bool> favorites = new HashTable<string, bool> (str_hash, str_equal);
        GenericArray<FileMonitor> monitors = new GenericArray<FileMonitor> ();
        uint reload_source;

        public NoteStore (File root, string[] favorite_paths) {
            this.root = root;
            trash_dir = root.get_child (".trash");
            foreach (string f in favorite_paths) {
                favorites.insert (f, true);
            }
            ensure_dir (root);
            reload ();
        }

        ~NoteStore () {
            if (reload_source != 0) {
                Source.remove (reload_source);
            }
            for (int k = 0; k < monitors.length; k++) {
                monitors[k].cancel ();
            }
        }

        /* ---- Helpers ---- */

        public static bool is_markdown_name (string name) {
            string low = name.down ();
            return low.has_suffix (".md") || low.has_suffix (".markdown") || low.has_suffix (".mdown")
                || low.has_suffix (".mkd");
        }

        public static string stem_of (string name) {
            int dot = name.last_index_of_char ('.');
            return dot > 0 ? name.substring (0, dot) : name;
        }

        static string ext_of (string name) {
            int dot = name.last_index_of_char ('.');
            return dot > 0 ? name.substring (dot) : ".md";
        }

        public static string sanitize_name (string name) {
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

        /* The first meaningful line of a note, without Markdown syntax. */
        public static string derive_title (string text, string fallback) {
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
                    if (l.char_count () > 80) {
                        l = l.substring (0, l.index_of_nth_char (80)) + "…";
                    }
                    return l;
                }
            }
            return fallback;
        }

        static void ensure_dir (File dir) {
            try {
                dir.make_directory_with_parents ();
            } catch (IOError.EXISTS e) {
            } catch (Error e) {
                warning ("Could not create %s: %s", dir.get_path (), e.message);
            }
        }

        static File unique_file (File dir, string stem, string ext, File? ignore = null) {
            File f = dir.get_child (stem + ext);
            for (int k = 2; f.query_exists () && (ignore == null || !f.equal (ignore)); k++) {
                f = dir.get_child ("%s %d%s".printf (stem, k, ext));
            }
            return f;
        }

        File folder_dir (string folder) {
            return folder == "" ? root : root.get_child (folder);
        }

        /* ---- Scanning ---- */

        public void reload () {
            var fresh = new GenericArray<Note> ();
            var seen = new HashTable<string, Note> (str_hash, str_equal);
            var new_folders = new GenericArray<string> ();

            scan (root, "", false, true, fresh, seen, new_folders);
            scan (trash_dir, "", true, true, fresh, seen, null);
            new_folders.sort ((a, b) => strcmp (a.collate_key (), b.collate_key ()));

            notes = fresh;
            by_path = seen;
            folders = new_folders;
            watch ();
            changed ();
        }

        void scan (File dir, string folder, bool trashed, bool top, GenericArray<Note> into,
                   HashTable<string, Note> seen, GenericArray<string>? folder_list) {
            FileEnumerator enumerator;
            try {
                enumerator = dir.enumerate_children ("standard::name,standard::type,time::modified",
                                                     FileQueryInfoFlags.NONE);
            } catch (Error e) {
                return;
            }

            FileInfo? info;
            try {
                while ((info = enumerator.next_file ()) != null) {
                    string name = info.get_name ();
                    if (name.has_prefix (".")) {
                        continue;
                    }
                    File child = dir.get_child (name);
                    if (info.get_file_type () == FileType.DIRECTORY) {
                        if (top) {
                            if (folder_list != null) {
                                folder_list.add (name);
                            }
                            scan (child, name, trashed, false, into, seen, null);
                        }
                        continue;
                    }
                    if (!is_markdown_name (name)) {
                        continue;
                    }

                    string path = child.get_path ();
                    DateTime mtime = info.get_modification_date_time () ?? new DateTime.now_utc ();
                    Note? note = by_path.lookup (path);
                    if (note == null || !note.modified.equal (mtime)) {
                        if (note == null) {
                            note = new Note (child);
                        }
                        note.content = read_text (child);
                        note.title = derive_title (note.content, stem_of (name));
                    }
                    note.modified = mtime;
                    note.folder = folder;
                    note.trashed = trashed;
                    note.relpath = folder == "" ? name : folder + "/" + name;
                    note.favorite = !trashed && favorites.contains (note.relpath);
                    into.add (note);
                    seen.insert (path, note);
                }
            } catch (Error e) {
                warning ("Could not list %s: %s", dir.get_path (), e.message);
            }
        }

        static string read_text (File file) {
            try {
                uint8[] data;
                file.load_contents (null, out data, null);
                string text = (string) data;
                return text.validate () ? text : text.make_valid ();
            } catch (Error e) {
                return "";
            }
        }

        void watch () {
            for (int k = 0; k < monitors.length; k++) {
                monitors[k].cancel ();
            }
            monitors = new GenericArray<FileMonitor> ();
            add_monitor (root);
            for (int k = 0; k < folders.length; k++) {
                add_monitor (root.get_child (folders[k]));
            }
            add_monitor (trash_dir);
        }

        void add_monitor (File dir) {
            try {
                var monitor = dir.monitor_directory (FileMonitorFlags.WATCH_MOVES);
                monitor.changed.connect (schedule_reload);
                monitors.add (monitor);
            } catch (Error e) {
            }
        }

        void schedule_reload () {
            if (reload_source != 0) {
                Source.remove (reload_source);
            }
            reload_source = Timeout.add (300, () => {
                reload_source = 0;
                reload ();
                return Source.REMOVE;
            });
        }

        /* ---- Queries ---- */

        public Note? find (File file) {
            return by_path.lookup (file.get_path ());
        }

        public Note? find_path (string path) {
            return by_path.lookup (path);
        }

        public bool contains (File file) {
            return file.has_prefix (root);
        }

        public string[] favorite_list () {
            string[] list = {};
            favorites.foreach ((k, v) => list += k);
            return list;
        }

        /* ---- Notes ---- */

        /* Records a save made by the window, without waiting for the monitor. */
        public void note_saved (Note note, string text) {
            note.content = text;
            note.title = derive_title (text, stem_of (note.file.get_basename ()));
            try {
                var info = note.file.query_info ("time::modified", FileQueryInfoFlags.NONE);
                note.modified = info.get_modification_date_time () ?? new DateTime.now_utc ();
            } catch (Error e) {
                note.modified = new DateTime.now_utc ();
            }
        }

        public File create_note (string folder) throws Error {
            File dir = folder_dir (folder);
            ensure_dir (dir);
            File file = unique_file (dir, _("Untitled"), ".md");
            file.create (FileCreateFlags.NONE).close ();
            reload ();
            return file;
        }

        public File create_note_with (string name, string content) throws Error {
            File file = unique_file (root, name, ".md");
            file.replace_contents (content.data, null, false, FileCreateFlags.NONE, null);
            reload ();
            return file;
        }

        File move_note (Note note, File dir, string stem) throws Error {
            ensure_dir (dir);
            string name = note.file.get_basename ();
            File dest = unique_file (dir, stem, ext_of (name), note.file);
            if (!dest.equal (note.file)) {
                note.file.move (dest, FileCopyFlags.NONE);
            }
            return dest;
        }

        void rekey_favorite (string old_rel, File dest) {
            if (favorites.remove (old_rel)) {
                string? rel = root.get_relative_path (dest);
                if (rel != null && !rel.has_prefix (".trash")) {
                    favorites.insert (rel, true);
                }
                favorites_changed ();
            }
        }

        public File rename_note (Note note, string new_name) throws Error {
            string stem = sanitize_name (new_name);
            if (stem == "") {
                throw new IOError.INVALID_ARGUMENT (_("The name is not valid"));
            }
            string old_rel = note.relpath;
            File dest = move_note (note, note.file.get_parent (), stem);
            rekey_favorite (old_rel, dest);
            reload ();
            return dest;
        }

        public File move_to_folder (Note note, string folder) throws Error {
            string old_rel = note.relpath;
            File dest = move_note (note, folder_dir (folder), stem_of (note.file.get_basename ()));
            rekey_favorite (old_rel, dest);
            reload ();
            return dest;
        }

        public File trash (Note note) throws Error {
            File dir = note.folder == "" ? trash_dir : trash_dir.get_child (note.folder);
            string old_rel = note.relpath;
            File dest = move_note (note, dir, stem_of (note.file.get_basename ()));
            rekey_favorite (old_rel, dest);
            reload ();
            return dest;
        }

        public File restore (Note note) throws Error {
            File dest = move_note (note, folder_dir (note.folder), stem_of (note.file.get_basename ()));
            reload ();
            return dest;
        }

        public void delete_forever (Note note) throws Error {
            note.file.delete ();
            reload ();
        }

        public void empty_trash () throws Error {
            for (int k = 0; k < notes.length; k++) {
                if (notes[k].trashed) {
                    notes[k].file.delete ();
                }
            }
            try {
                var enumerator = trash_dir.enumerate_children ("standard::name,standard::type", FileQueryInfoFlags.NONE);
                FileInfo? info;
                while ((info = enumerator.next_file ()) != null) {
                    if (info.get_file_type () == FileType.DIRECTORY) {
                        try {
                            trash_dir.get_child (info.get_name ()).delete ();
                        } catch (Error e) {
                            // Not empty: it holds files we don't manage.
                        }
                    }
                }
            } catch (Error e) {
            }
            reload ();
        }

        public void set_favorite (Note note, bool favorite) {
            if (note.trashed) {
                return;
            }
            note.favorite = favorite;
            if (favorite) {
                favorites.insert (note.relpath, true);
            } else {
                favorites.remove (note.relpath);
            }
            favorites_changed ();
            changed ();
        }

        /* ---- Folders ---- */

        public void create_folder (string name) throws Error {
            string clean = sanitize_name (name);
            if (clean == "") {
                throw new IOError.INVALID_ARGUMENT (_("The name is not valid"));
            }
            root.get_child (clean).make_directory ();
            reload ();
        }

        public void rename_folder (string old_name, string new_name) throws Error {
            string clean = sanitize_name (new_name);
            if (clean == "") {
                throw new IOError.INVALID_ARGUMENT (_("The name is not valid"));
            }
            if (clean == old_name) {
                return;
            }
            root.get_child (old_name).move (root.get_child (clean), FileCopyFlags.NONE);
            string prefix = old_name + "/";
            foreach (string fav in favorite_list ()) {
                if (fav.has_prefix (prefix)) {
                    favorites.remove (fav);
                    favorites.insert (clean + "/" + fav.substring (prefix.length), true);
                }
            }
            favorites_changed ();
            reload ();
        }

        /* Moves the folder's notes to the trash, then removes the folder. */
        public void delete_folder (string name) throws Error {
            for (int k = 0; k < notes.length; k++) {
                Note note = notes[k];
                if (!note.trashed && note.folder == name) {
                    File dir = trash_dir.get_child (name);
                    ensure_dir (dir);
                    File dest = unique_file (dir, stem_of (note.file.get_basename ()), ext_of (note.file.get_basename ()));
                    note.file.move (dest, FileCopyFlags.NONE);
                    favorites.remove (note.relpath);
                }
            }
            favorites_changed ();
            try {
                root.get_child (name).delete ();
            } catch (Error e) {
                reload ();
                throw new IOError.NOT_EMPTY (_("The folder still contains other files"));
            }
            reload ();
        }
    }
}
