/* The document tree produced by the parser and consumed by the renderer. */

namespace Markdown {

    public enum BlockKind {
        DOCUMENT,
        PARAGRAPH,
        HEADING,
        BLOCKQUOTE,
        LIST,
        ITEM,
        CODE,
        RULE,
        TABLE,
        TABLE_ROW,
        TABLE_CELL,
        CONTAINER,  // <div>, <p>, <center>: groups blocks, may set alignment
        DETAILS,    // <details> with an optional <summary>
        SPACER,     // a lone <br>
    }

    public enum Align {
        NONE,
        LEFT,
        CENTER,
        RIGHT,
    }

    public class Block {
        public BlockKind kind;
        public GenericArray<Block> children = new GenericArray<Block> ();

        /* Line in the source document where the block starts (0-based). */
        public int line = -1;

        /* Paragraphs, headings, table cells: raw inline source and its parse. */
        public string raw = "";
        public Inline? inlines;

        public int level;          // headings
        public bool lead;          // paragraph right under a title, shown as a subtitle
        public string info = "";   // code fence language
        public string code = "";   // code block content

        public bool ordered;       // lists
        public int start = 1;
        public bool tight = true;

        public bool task;          // list items
        public bool checked;

        public Align align = Align.NONE;
        public Align[] aligns = {};  // table column alignment
        public bool header;          // table row

        public string summary = "";  // details
        public Inline? summary_inlines;
        public bool open;

        public Block (BlockKind kind) {
            this.kind = kind;
        }

        public void add (Block child) {
            children.add (child);
        }
    }

    public enum InlineKind {
        ROOT,
        TEXT,
        CODE,
        EMPH,
        STRONG,
        STRIKE,
        UNDERLINE,
        MARK,
        SUB,
        SUP,
        SMALL,
        KBD,
        MONO,
        LINK,
        IMAGE,
        SOFTBREAK,
        HARDBREAK,
        /* Temporary markers for inline HTML, folded into containers after parsing. */
        HTML_OPEN,
        HTML_CLOSE,
    }

    /* Inline nodes form a doubly linked tree, which makes the CommonMark
     * delimiter algorithm (wrapping a run of siblings into a new node) cheap. */
    public class Inline {
        public InlineKind kind;
        public string text;
        public string url = "";
        public string title = "";
        public int width = -1;  // <img width="...">

        public Inline? first;
        public unowned Inline? last;
        public Inline? next;
        public unowned Inline? prev;
        public unowned Inline? parent;

        public Inline (InlineKind kind, string text = "") {
            this.kind = kind;
            this.text = text;
        }

        public void append (Inline child) {
            child.parent = this;
            child.next = null;
            child.prev = last;
            if (last != null) {
                last.next = child;
            } else {
                first = child;
            }
            last = child;
        }

        public void insert_after (Inline node) {
            node.parent = parent;
            node.prev = this;
            node.next = next;
            if (next != null) {
                next.prev = node;
            } else if (parent != null) {
                parent.last = node;
            }
            next = node;
        }

        /* Callers must hold their own reference: the sibling link may be the last one. */
        public void unlink () {
            Inline self = this;
            if (prev != null) {
                prev.next = next;
            } else if (parent != null) {
                parent.first = next;
            }
            if (next != null) {
                next.prev = prev;
            } else if (parent != null) {
                parent.last = prev;
            }
            self.prev = null;
            self.next = null;
            self.parent = null;
        }

        /* Concatenated text of this node's descendants, for alt text and anchors. */
        public string plain_text () {
            var sb = new StringBuilder ();
            collect_text (this, sb);
            return sb.str;
        }

        static void collect_text (Inline node, StringBuilder sb) {
            for (Inline? c = node.first; c != null; c = c.next) {
                switch (c.kind) {
                case InlineKind.TEXT:
                case InlineKind.CODE:
                    sb.append (c.text);
                    break;
                case InlineKind.SOFTBREAK:
                case InlineKind.HARDBREAK:
                    sb.append_c (' ');
                    break;
                default:
                    collect_text (c, sb);
                    break;
                }
            }
        }
    }
}
