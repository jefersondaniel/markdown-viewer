/* SPDX-License-Identifier: GPL-3.0-or-later */

namespace Mermaid {

    /* Diagram types that Mermaid has but this library doesn't draw yet. */
    const string[] UNSUPPORTED_TYPES = {
        "gantt", "journey", "gitGraph", "mindmap", "timeline",
        "quadrantChart", "requirementDiagram", "requirement", "C4Context", "C4Container",
        "C4Component", "C4Dynamic", "C4Deployment", "sankey-beta", "sankey", "xychart-beta",
        "xychart", "block-beta", "block", "packet-beta", "packet", "architecture-beta",
        "architecture", "kanban", "radar-beta", "radar", "treemap-beta", "treemap", "zenuml",
        "info", "venn-beta", "venn", "ishikawa-beta", "ishikawa", "usecase", "wardley-beta",
        "wardley", "swimlane-beta", "railroad-beta", "cynefin-beta", "eventmodeling", "treeView-beta"
    };

    /*
     * Parses Mermaid source. Throws ParseError.UNSUPPORTED for diagram types
     * that aren't supported, and ParseError.SYNTAX for invalid sources.
     */
    public Diagram parse (string text) throws ParseError {
        var src = new Source (text);
        int first = src.first_line ();
        if (first < 0) {
            throw new ParseError.EMPTY ("The diagram is empty");
        }
        string keyword = first_word (src.lines[first]);

        Diagram diagram;
        switch (keyword) {
        case "pie":
            diagram = PieParser.parse (src, first);
            break;
        case "graph":
        case "flowchart":
        case "flowchart-elk":
            diagram = FlowchartParser.parse (src, first);
            break;
        case "sequenceDiagram":
            diagram = SequenceParser.parse (src, first);
            break;
        case "stateDiagram":
        case "stateDiagram-v2":
            diagram = StateParser.parse (src, first);
            break;
        case "classDiagram":
        case "classDiagram-v2":
            diagram = ClassParser.parse (src, first);
            break;
        case "erDiagram":
            diagram = ErParser.parse (src, first);
            break;
        default:
            if (keyword in UNSUPPORTED_TYPES) {
                throw new ParseError.UNSUPPORTED ("“%s” diagrams aren't supported yet".printf (keyword));
            }
            throw new ParseError.SYNTAX ("Unknown diagram type “%s”".printf (keyword));
        }
        if (diagram.title == null) {
            diagram.title = src.title;
        }
        return diagram;
    }

    /* The diagram type a source declares, such as "flowchart", or null. */
    public string? detect_type (string text) {
        var src = new Source (text);
        int first = src.first_line ();
        return first >= 0 ? first_word (src.lines[first]) : null;
    }

    internal string first_word (string line) {
        string l = line.strip ();
        int end = 0;
        while (end < l.length && !l[end].isspace () && l[end] != ';' && l[end] != ':') {
            end++;
        }
        return l.substring (0, end);
    }
}
