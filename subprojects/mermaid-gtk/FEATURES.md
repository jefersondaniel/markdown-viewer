# Supported Mermaid features

This is the inventory of Mermaid features and how far this library supports
them, compared with Mermaid 12.2.0. Each feature has a stable ID. A feature
marked supported or partial must be covered by a test case in `tests/cases/`
that lists its ID on a `%% features:` line. `tests/check-inventory.py`, run by
`meson test`, fails when this table and the test cases disagree.

Statuses:

- ✅ **Supported**: parsed and drawn.
- 🟡 **Partial**: parsed and drawn, with the differences in the notes.
- ❌ **Not yet**: not supported yet. Unknown syntax is a syntax error, and
  unsupported diagram types show their source with a note.
- ⛔ **Not planned**: deliberately not supported, usually because it doesn't
  fit a document viewer.

Diagrams are drawn with the desktop's colors and fonts, so they look native
rather than identical to Mermaid's own output.

## Diagram types

| ID | Feature | Status | Notes |
|:--|:--|:--|:--|
| `type.flowchart` | `flowchart` and `graph` | ✅ Supported | |
| `type.sequence` | `sequenceDiagram` | ✅ Supported | |
| `type.class` | `classDiagram` | ✅ Supported | |
| `type.state` | `stateDiagram` and `stateDiagram-v2` | ✅ Supported | |
| `type.er` | `erDiagram` | ✅ Supported | |
| `type.pie` | `pie` | ✅ Supported | |
| `type.gantt` | `gantt` | ❌ Not yet | |
| `type.journey` | `journey` | ❌ Not yet | |
| `type.git` | `gitGraph` | ❌ Not yet | |
| `type.mindmap` | `mindmap` | ❌ Not yet | |
| `type.timeline` | `timeline` | ❌ Not yet | |
| `type.quadrant` | `quadrantChart` | ❌ Not yet | |
| `type.requirement` | `requirementDiagram` | ❌ Not yet | |
| `type.c4` | `C4Context` and the other C4 diagrams | ❌ Not yet | |
| `type.sankey` | `sankey` | ❌ Not yet | |
| `type.xychart` | `xychart` | ❌ Not yet | |
| `type.block` | `block` | ❌ Not yet | |
| `type.packet` | `packet` | ❌ Not yet | |
| `type.architecture` | `architecture` | ❌ Not yet | |
| `type.kanban` | `kanban` | ❌ Not yet | |
| `type.radar` | `radar` | ❌ Not yet | |
| `type.treemap` | `treemap` | ❌ Not yet | |
| `type.other` | `zenuml`, `venn`, `ishikawa`, `usecase`, `wardley` and other new types | ❌ Not yet | |

## Common to all diagrams

| ID | Feature | Status | Notes |
|:--|:--|:--|:--|
| `general.front-matter-title` | `title:` in YAML front matter | ✅ Supported | Other front matter is ignored. |
| `general.front-matter-config` | `config:` in front matter | ❌ Not yet | Ignored. |
| `general.directives` | `%%{init: …}%%` directives | ❌ Not yet | Ignored, so they don't break diagrams. |
| `general.comments` | `%%` comment lines | ✅ Supported | |
| `general.accessibility` | `accTitle` and `accDescr` | ✅ Supported | Used as the diagram's accessible name and description. |
| `general.html-labels` | HTML in labels | 🟡 Partial | `<br>`, `<b>`, `<strong>`, `<i>`, `<em>`, `<u>`, `<s>`, `<code>`, `<sub>` and `<sup>`; other tags are dropped, their text kept. |
| `general.entity-codes` | Entity codes such as `#quot;` and `#9829;` | ✅ Supported | |
| `general.unicode` | Unicode text and ids | ✅ Supported | |
| `general.unsupported-types` | Unsupported diagram types | ✅ Supported | Reported as unsupported, so the app can show the source. |
| `general.syntax-errors` | Syntax errors | ✅ Supported | Reported with a line number. |
| `general.themes` | Themes and `themeVariables` | ⛔ Not planned | Diagrams follow the desktop's light or dark style and accent color. |
| `general.looks` | The `handDrawn` and `neo` looks | ⛔ Not planned | |
| `general.icons` | Font Awesome and Iconify icons, such as `fa:fa-car` | ❌ Not yet | Shown as text. |
| `general.math` | KaTeX math (`$$…$$`) | ❌ Not yet | Shown as text. |
| `general.interaction` | `click`, `href`, callbacks and tooltips | ⛔ Not planned | Ignored. |

## Flowcharts

| ID | Feature | Status | Notes |
|:--|:--|:--|:--|
| `flowchart.header` | `flowchart` and `graph`, with or without a direction | ✅ Supported | |
| `flowchart.direction` | `TB`, `TD`, `BT`, `LR`, `RL` and `<`, `>`, `^`, `v` | ✅ Supported | |
| `flowchart.separators` | Statements separated by `;` | ✅ Supported | |
| `flowchart.node.id-only` | A node with only an id | ✅ Supported | |
| `flowchart.shape.rect` | `A[text]` | ✅ Supported | |
| `flowchart.shape.rounded` | `A(text)` | ✅ Supported | |
| `flowchart.shape.stadium` | `A([text])` | ✅ Supported | |
| `flowchart.shape.subroutine` | `A[[text]]` | ✅ Supported | |
| `flowchart.shape.cylinder` | `A[(text)]` | ✅ Supported | |
| `flowchart.shape.circle` | `A((text))` | ✅ Supported | |
| `flowchart.shape.double-circle` | `A(((text)))` | ✅ Supported | |
| `flowchart.shape.diamond` | `A{text}` | ✅ Supported | |
| `flowchart.shape.hexagon` | `A{{text}}` | ✅ Supported | |
| `flowchart.shape.lean-right` | `A[/text/]` | ✅ Supported | |
| `flowchart.shape.lean-left` | `A[\text\]` | ✅ Supported | |
| `flowchart.shape.trapezoid` | `A[/text\]` | ✅ Supported | |
| `flowchart.shape.inv-trapezoid` | `A[\text/]` | ✅ Supported | |
| `flowchart.shape.odd` | `A>text]` | ✅ Supported | |
| `flowchart.shape.ellipse` | `A(-text-)` | ✅ Supported | |
| `flowchart.shape-data` | `A@{ shape: … }` | ✅ Supported | |
| `flowchart.shape-data.label` | `A@{ label: "…" }` | ✅ Supported | |
| `flowchart.shape-data.names` | The shape names of Mermaid 11 | 🟡 Partial | 47 of the 53 shapes, with their aliases. `bang`, `cloud`, `person`, `bucket`, `browser` and `console` are drawn as rectangles. |
| `flowchart.shape-data.assets` | `icon`, `img`, `pos`, `w` and `h` in shape data | ❌ Not yet | Ignored. |
| `flowchart.link.arrow` | `-->` | ✅ Supported | |
| `flowchart.link.open` | `---` | ✅ Supported | |
| `flowchart.link.dotted` | `-.->` and `-.-` | ✅ Supported | |
| `flowchart.link.thick` | `==>` and `===` | ✅ Supported | |
| `flowchart.link.invisible` | `~~~` | ✅ Supported | |
| `flowchart.link.circle` | `--o` | ✅ Supported | |
| `flowchart.link.cross` | `--x` | ✅ Supported | |
| `flowchart.link.bidirectional` | `<-->`, `o--o` and `x--x` | ✅ Supported | |
| `flowchart.link.length` | Longer links such as `---->` and `-...->` | ✅ Supported | |
| `flowchart.link.text-pipe` | `-->|text|` | ✅ Supported | |
| `flowchart.link.text-inline` | `-- text -->`, `== text ==>`, `-. text .->` | ✅ Supported | |
| `flowchart.link.chaining` | `A --> B --> C` | ✅ Supported | |
| `flowchart.link.ampersand` | `A & B --> C & D` | ✅ Supported | |
| `flowchart.link.id` | `A e1@--> B` | 🟡 Partial | Accepted; edge metadata such as animations is ignored. |
| `flowchart.link.animation` | `e1@{ animate: true }` | ⛔ Not planned | Ignored. |
| `flowchart.self-loop` | A link from a node to itself | ✅ Supported | |
| `flowchart.subgraph` | `subgraph … end` | ✅ Supported | |
| `flowchart.subgraph.title` | `subgraph id [title]` and titles with spaces | ✅ Supported | |
| `flowchart.subgraph.nested` | Subgraphs inside subgraphs | ✅ Supported | |
| `flowchart.subgraph.edges` | Links to and from subgraphs | ✅ Supported | |
| `flowchart.subgraph.direction` | `direction` inside a subgraph | ✅ Supported | As in Mermaid, only for subgraphs that no link crosses. |
| `flowchart.subgraph.isolated` | Subgraphs that no link crosses are laid out on their own | ✅ Supported | Without a direction they turn, as in Mermaid: TB becomes LR and others become TB. |
| `flowchart.subgraph.collapsed` | `@{ view: collapsed }` | ❌ Not yet | |
| `flowchart.style` | `style id …` | ✅ Supported | `fill`, `stroke`, `stroke-width`, `stroke-dasharray`, `color`, `font-weight` and `font-style`. |
| `flowchart.class-def` | `classDef` | ✅ Supported | |
| `flowchart.class` | `class a,b name` | ✅ Supported | |
| `flowchart.class-shorthand` | `A:::name` | ✅ Supported | |
| `flowchart.class-default` | `classDef default` | ✅ Supported | |
| `flowchart.text-contrast` | Text on a `fill` with no `color` | ✅ Supported | Dark or white, whichever is easier to read on the fill, so it works in light and dark style. Mermaid keeps the theme's text color. |
| `flowchart.link-style` | `linkStyle 0,1 …` and `linkStyle default …` | ✅ Supported | |
| `flowchart.link-style.curve` | `linkStyle … interpolate …` | 🟡 Partial | `basis`, `linear` and the `step` curves; others are drawn as `basis`. |
| `flowchart.markdown-strings` | `` "`**Markdown** strings`" `` | ✅ Supported | Bold, italic and automatic wrapping. |
| `flowchart.click` | `click` | ⛔ Not planned | Ignored. |
| `flowchart.vertex-props` | `A[|field:value|text]` | ❌ Not yet | |
| `flowchart.elk` | `flowchart-elk` and the ELK layout | 🟡 Partial | Laid out with dagre. |

## Sequence diagrams

| ID | Feature | Status | Notes |
|:--|:--|:--|:--|
| `sequence.participant` | `participant` | ✅ Supported | |
| `sequence.actor` | `actor` | ✅ Supported | Drawn as a stick figure. |
| `sequence.alias` | `participant A as Alice` | ✅ Supported | |
| `sequence.implicit` | Participants first named in a message | ✅ Supported | |
| `sequence.participant-types` | `participant A@{ "type": "database" }` and the other types | ❌ Not yet | Drawn as boxes. |
| `sequence.message.arrows` | `->`, `-->`, `->>`, `-->>`, `<<->>`, `<<-->>`, `-x`, `--x`, `-)`, `--)` | ✅ Supported | |
| `sequence.message.half-arrows` | Half arrows such as `-|\` and `//-` | 🟡 Partial | Drawn with whole arrowheads. |
| `sequence.self-message` | A message to the same participant | ✅ Supported | |
| `sequence.line-breaks` | `<br>` in messages and notes | ✅ Supported | |
| `sequence.wrap` | `wrap:` and automatic wrapping | ❌ Not yet | `wrap:` is accepted; text isn't wrapped. |
| `sequence.activation` | `activate`, `deactivate`, `+` and `-` | ✅ Supported | Nested activations are offset. |
| `sequence.note` | `Note left of`, `right of` and `over` one or two participants | ✅ Supported | |
| `sequence.loop` | `loop` | ✅ Supported | |
| `sequence.alt` | `alt`, `else` | ✅ Supported | |
| `sequence.opt` | `opt` | ✅ Supported | |
| `sequence.par` | `par`, `and`, `par_over` | ✅ Supported | |
| `sequence.critical` | `critical`, `option` | ✅ Supported | |
| `sequence.break` | `break` | ✅ Supported | |
| `sequence.rect` | `rect rgb(…)` backgrounds | ✅ Supported | Colors are made translucent so text stays readable. |
| `sequence.nested-blocks` | Blocks inside blocks | ✅ Supported | |
| `sequence.autonumber` | `autonumber`, with a start, step or `off` | ✅ Supported | |
| `sequence.box` | `box Color Title … end` | ✅ Supported | Colors are made translucent. |
| `sequence.create-destroy` | `create participant` and `destroy` | ✅ Supported | |
| `sequence.title` | `title` | ✅ Supported | |
| `sequence.menus` | `link`, `links`, `properties` and `details` | ⛔ Not planned | Ignored. |
| `sequence.mirror-actors` | Participants repeated at the bottom | ✅ Supported | |

## Class diagrams

| ID | Feature | Status | Notes |
|:--|:--|:--|:--|
| `class.header` | `classDiagram` and `classDiagram-v2` | ✅ Supported | |
| `class.definition` | `class Name` | ✅ Supported | |
| `class.members` | Members in `class Name { … }` | ✅ Supported | |
| `class.members-colon` | `Name : +member` | ✅ Supported | |
| `class.methods` | Methods with parameters and return types | ✅ Supported | Shown as `name(params) : type`. |
| `class.visibility` | `+`, `-`, `#` and `~` | ✅ Supported | |
| `class.static-abstract` | `$` (static) and `*` (abstract) | ✅ Supported | Underlined and in italics. |
| `class.generics` | `~T~` | ✅ Supported | Shown as `<T>`. |
| `class.annotations` | `<<interface>>` inside the class or before its name | ✅ Supported | |
| `class.label` | `class Name["Label"]` | ✅ Supported | |
| `class.backticks` | `` class `Any name` `` | ✅ Supported | |
| `class.relation.inheritance` | `<|--` | ✅ Supported | |
| `class.relation.composition` | `*--` | ✅ Supported | |
| `class.relation.aggregation` | `o--` | ✅ Supported | |
| `class.relation.association` | `-->` | ✅ Supported | |
| `class.relation.link` | `--` | ✅ Supported | |
| `class.relation.dependency` | `..>` | ✅ Supported | |
| `class.relation.realization` | `..|>` | ✅ Supported | |
| `class.relation.dashed` | `..` | ✅ Supported | |
| `class.relation.lollipop` | `()--` and `--()` | ✅ Supported | |
| `class.relation.two-way` | Markers on both ends, such as `<|--|>` | ✅ Supported | |
| `class.relation.label` | `A --> B : label` | ✅ Supported | |
| `class.cardinality` | `A "1" --> "*" B` | ✅ Supported | |
| `class.notes` | `note` and `note for Name` | ✅ Supported | |
| `class.namespace` | `namespace Name { … }` | ✅ Supported | |
| `class.direction` | `direction` | ✅ Supported | |
| `class.styles` | `style`, `classDef`, `cssClass` and `:::` | ✅ Supported | |
| `class.interaction` | `click`, `link` and `callback` | ⛔ Not planned | Ignored. |

## State diagrams

| ID | Feature | Status | Notes |
|:--|:--|:--|:--|
| `state.header` | `stateDiagram` and `stateDiagram-v2` | ✅ Supported | |
| `state.transition` | `A --> B` | ✅ Supported | |
| `state.label` | `A --> B : label` | ✅ Supported | |
| `state.start-end` | `[*]` | ✅ Supported | One start and one end point for each composite state, as in Mermaid. |
| `state.description` | `A : description` | ✅ Supported | Several descriptions are listed below the name. |
| `state.alias` | `state "Description" as A` | ✅ Supported | |
| `state.composite` | `state A { … }` | ✅ Supported | |
| `state.composite-nested` | Composite states inside composite states | ✅ Supported | |
| `state.concurrency` | `--` regions | ✅ Supported | |
| `state.fork-join` | `<<fork>>` and `<<join>>` | ✅ Supported | |
| `state.choice` | `<<choice>>` | ✅ Supported | |
| `state.notes` | `note left of` and `note right of`, on one line or until `end note` | ✅ Supported | |
| `state.floating-notes` | `note "text" as N` | ❌ Not yet | Ignored. |
| `state.direction` | `direction` | ✅ Supported | |
| `state.styles` | `classDef`, `class`, `:::` and `style` | ✅ Supported | |
| `state.hide-empty` | `hide empty description` | ⛔ Not planned | Ignored. |

## Entity relationship diagrams

| ID | Feature | Status | Notes |
|:--|:--|:--|:--|
| `er.header` | `erDiagram` | ✅ Supported | |
| `er.entity` | Entities | ✅ Supported | |
| `er.attributes` | `NAME { type name }` | ✅ Supported | |
| `er.attribute-keys` | `PK`, `FK` and `UK` | ✅ Supported | |
| `er.attribute-comments` | `"comment"` | ✅ Supported | |
| `er.relationship` | `A ||--o{ B : label` | ✅ Supported | |
| `er.cardinality` | `|o`, `||`, `}o`, `}|` and their mirrors | ✅ Supported | Crow's foot notation. |
| `er.cardinality-words` | `one or more`, `zero or many` and the other word forms | ❌ Not yet | |
| `er.identifying` | `--` and `..` | ✅ Supported | |
| `er.label` | Relationship labels, quoted or not | ✅ Supported | |
| `er.alias` | `NAME["Label"]` | ✅ Supported | |
| `er.direction` | `direction` | ✅ Supported | |
| `er.styles` | `style`, `classDef`, `class` and `:::` | ✅ Supported | |

## Pie charts

| ID | Feature | Status | Notes |
|:--|:--|:--|:--|
| `pie.header` | `pie` | ✅ Supported | |
| `pie.title` | `pie title …` and `title …` | ✅ Supported | With more space between the title and the chart than Mermaid leaves. |
| `pie.show-data` | `showData` | ✅ Supported | |
| `pie.values` | `"Label" : value` | ✅ Supported | Slices under 1% are left out, as in Mermaid. |
| `pie.config` | `textPosition`, `donutHole` and other options | ❌ Not yet | |
