# mermaid-gtk

A Vala library that draws [Mermaid](https://mermaid.js.org/) diagrams natively with
GTK 4: no web engine and no JavaScript. It parses the Mermaid source, lays the diagram
out and draws it with the widget's own colors and fonts, so diagrams follow the light
and dark style and the text size of the app around them.

It's developed inside [Markdown Viewer](../../README.md) for now, but it doesn't
depend on it, and it's meant to move to its own repository later. It isn't affiliated
with the Mermaid project.

## Supported diagrams

- Flowcharts (`flowchart`, `graph`), with subgraphs, 47 of Mermaid's 53 node shapes,
  link styles, `classDef` and `style`
- Sequence diagrams, with activations, notes, loops and other blocks, boxes,
  autonumbering, and created and destroyed participants
- Class diagrams, with members, generics, relations, cardinalities, namespaces and notes
- State diagrams, with composite and concurrent states, forks, joins, choices and notes
- Entity relationship diagrams, with attributes, keys and comments
- Pie charts

[FEATURES.md](FEATURES.md) lists every feature, whether it's supported, and the
differences from Mermaid. Other diagram types fail with
`Mermaid.ParseError.UNSUPPORTED`, so an app can show their source instead.

## Use

```vala
try {
    Mermaid.Diagram diagram = Mermaid.parse (source);
    var view = new Mermaid.View (diagram);
    view.accent = accent_rgba;  // optional, for highlights such as pie slices
    box.append (view);
} catch (Mermaid.ParseError e) {
    // e.message is ready to show; syntax errors start with the line number
}
```

`Mermaid.View` is a height-for-width widget. It draws the diagram at the size of its
font, shrinks it to fit narrower widths, and sets its accessible label and description
from the diagram's title and `accTitle`/`accDescr`. Parsing is cheap and layouts are
cached per diagram and font, so recreating views while a document is edited is fine.

With Meson, add the library as a subproject and use it with a fallback:

```meson
mermaid = dependency('mermaid-gtk-0',
  fallback: ['mermaid-gtk', 'mermaid_gtk_dep'],
  default_options: ['default_library=static'],
)
```

It needs GLib 2.76 and GTK 4.14 or newer.

## Code layout

| Path | Purpose |
|:--|:--|
| `src/core/` | Parsing and layout. Uses only GLib, and turns a diagram into a `Scene` of shapes and text. |
| `src/core/diagrams/` | One parser and layout per diagram type |
| `src/core/dagre/` | A port of the dagre graph layout, used by flowcharts, class, state and ER diagrams |
| `src/core/graph-render.vala` | Clusters, edges, markers and labels for dagre-based diagrams |
| `src/core/shapes.vala` | Flowchart node shapes |
| `src/gtk/` | The `View` widget, text measuring with Pango and drawing with GSK |
| `tests/` | Test cases and the scripts that check them |
| `demo/` | A small viewer that also renders diagrams to PNG |

A `Scene` refers to colors by role (line, node fill, text, accent…) rather than by
value, so switching between light and dark only repaints it.

## Build and test

```sh
meson setup build
ninja -C build
meson test -C build
./build/mermaid-demo diagram.mmd                         # show it in a window
./build/mermaid-demo diagram.mmd --png out.png --dark    # or render it to a file
```

`meson test` runs three checks:

- **mermaid-cases** lays out every `tests/cases/**/*.mmd` with fixed text sizes and
  compares the result with the `.scene` file next to it. After an intended change,
  regenerate them with `tests/run-cases.py build/tests/mermaid-dump tests/cases --update`
  and review the diff. Render the case with `mermaid-demo` to see it.
- **mermaid-inventory** checks that FEATURES.md and the cases agree: every supported
  feature is tested by a case that names it on a `%% features:` line.
- **dagre** compares the dagre port with layouts made by the original JavaScript dagre.

To add a feature, add it to FEATURES.md, add or extend a case that names it, and
regenerate the scenes.

## Upstream

The code follows these versions, and their files are named in the source headers:

- Mermaid 12.2.0 (commit `6d8921f`): the grammars in its `.jison` and `.langium`
  files, its `*Db.ts` models, the shapes in `rendering-util/rendering-elements/`, and
  the cluster handling in `rendering-util/layout-algorithms/dagre/`. The parsers are
  written by hand rather than generated from the grammars.
- dagre-d3-es 7.0.14: `src/core/dagre/` is a line-by-line port of its `dagre` and
  `graphlib` code, with typed labels in place of JavaScript objects. It differs in one
  place: a node's `title_height` makes room for a cluster title above its contents,
  which Mermaid does by shifting nodes after the layout.

## License

GPL-3.0-or-later, see [COPYING](COPYING). The code ported from Mermaid, dagre and
d3-shape keeps their MIT and ISC notices, collected in [THIRD-PARTY.md](THIRD-PARTY.md).
