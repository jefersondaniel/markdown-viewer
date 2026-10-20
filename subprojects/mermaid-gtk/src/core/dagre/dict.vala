/* SPDX-License-Identifier: GPL-3.0-or-later */

namespace Mermaid.Dagre {

    /*
     * A string-keyed map that remembers insertion order, like a JavaScript
     * object. dagre's results depend on the order in which nodes and edges are
     * visited, so iteration has to be deterministic.
     */
    internal class Dict<V> {
        class Entry<V> {
            public string key;
            public V value;
            // The table owns the entries; the links are weak.
            public weak Entry<V>? next;
            public weak Entry<V>? prev;
        }

        HashTable<string, Entry<V>> table = new HashTable<string, Entry<V>> (str_hash, str_equal);
        weak Entry<V>? first;
        weak Entry<V>? last;

        public uint size {
            get { return table.size (); }
        }

        public bool has (string key) {
            return table.contains (key);
        }

        public new V? get (string key) {
            unowned Entry<V>? e = table.lookup (key);
            return e != null ? e.value : null;
        }

        public new void set (string key, V value) {
            unowned Entry<V>? e = table.lookup (key);
            if (e != null) {
                e.value = value;
                return;
            }
            var entry = new Entry<V> ();
            entry.key = key;
            entry.value = value;
            entry.prev = last;
            if (last != null) {
                last.next = entry;
            } else {
                first = entry;
            }
            last = entry;
            table.insert (key, (owned) entry);
        }

        public void remove (string key) {
            unowned Entry<V>? e = table.lookup (key);
            if (e == null) {
                return;
            }
            if (e.next != null) {
                e.next.prev = e.prev;
            } else {
                last = e.prev;
            }
            if (e.prev != null) {
                e.prev.next = e.next;
            } else {
                first = e.next;
            }
            table.remove (key);
        }

        public bool is_empty () {
            return table.size () == 0;
        }

        public string[] keys () {
            var result = new string[table.size ()];
            int i = 0;
            for (unowned Entry<V>? e = first; e != null; e = e.next) {
                result[i++] = e.key;
            }
            return result;
        }

        public GenericArray<V> values () {
            var result = new GenericArray<V> ((int) table.size ());
            for (unowned Entry<V>? e = first; e != null; e = e.next) {
                result.add (e.value);
            }
            return result;
        }
    }
}
