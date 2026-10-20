/* SPDX-License-Identifier: GPL-3.0-or-later */

namespace Mermaid {

    /* A cursor over source text, for the hand-written parsers. */
    internal class Scanner {
        public string text;
        public int pos;
        /* The line of `text`'s first character in the diagram source. */
        public int first_line;

        public Scanner (string text, int first_line = 0) {
            this.text = text;
            this.first_line = first_line;
        }

        public bool eof {
            get { return pos >= text.length; }
        }

        public char peek (int offset = 0) {
            int p = pos + offset;
            return p < text.length ? text[p] : '\0';
        }

        public bool at (string s) {
            return text.length - pos >= s.length && Memory.cmp ((char*) text + pos, (char*) s, s.length) == 0;
        }

        /* Whether the keyword is here, followed by a non-word character. */
        public bool at_word (string word) {
            if (!at (word)) {
                return false;
            }
            char c = peek (word.length);
            return !(c.isalnum () || c == '_' || c == '-');
        }

        public bool accept (string s) {
            if (at (s)) {
                pos += s.length;
                return true;
            }
            return false;
        }

        public void skip_spaces () {
            while (pos < text.length && (text[pos] == ' ' || text[pos] == '\t')) {
                pos++;
            }
        }

        /* The rest of the current line, without the line break. */
        public string rest_of_line () {
            int end = text.index_of_char ('\n', pos);
            if (end < 0) {
                end = text.length;
            }
            string s = text.substring (pos, end - pos);
            pos = end;
            return s;
        }

        /* The rest of the statement: up to the end of the line or a ";". */
        public string rest_of_statement () {
            int start = pos;
            while (pos < text.length && text[pos] != '\n' && text[pos] != ';') {
                pos++;
            }
            return text.substring (start, pos - start);
        }

        public int line {
            get {
                int n = first_line;
                for (int i = 0; i < pos && i < text.length; i++) {
                    if (text[i] == '\n') {
                        n++;
                    }
                }
                return n;
            }
        }

        public ParseError error (string message) {
            return syntax_error (line, message);
        }

        /* A short excerpt of the text here, for error messages. */
        public string excerpt () {
            int end = pos;
            while (end < text.length && text[end] != '\n' && end - pos < 20) {
                end++;
            }
            string s = text.substring (pos, end - pos).strip ();
            return s == "" ? "the end of the line" : "“" + s + "”";
        }
    }
}
