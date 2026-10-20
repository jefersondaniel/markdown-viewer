# The core parses and lays out diagrams with GLib only. The GTK part measures
# text with Pango and paints the result.
core_sources = files(
  'core/css.vala',
  'core/dagre/acyclic.vala',
  'core/dagre/dict.vala',
  'core/dagre/graph.vala',
  'core/dagre/layout.vala',
  'core/dagre/nesting-graph.vala',
  'core/dagre/normalize.vala',
  'core/dagre/order.vala',
  'core/dagre/parent-dummy-chains.vala',
  'core/dagre/position.vala',
  'core/dagre/rank.vala',
  'core/dagre/util.vala',
  'core/diagram.vala',
  'core/diagrams/class/class.vala',
  'core/diagrams/er/er.vala',
  'core/diagrams/flowchart/flowchart.vala',
  'core/diagrams/pie/pie.vala',
  'core/diagrams/sequence/sequence.vala',
  'core/diagrams/state/state.vala',
  'core/graph-render.vala',
  'core/mermaid.vala',
  'core/scanner.vala',
  'core/scene.vala',
  'core/shapes.vala',
  'core/text.vala',
)

gtk_sources = files(
  'gtk/painter.vala',
  'gtk/view.vala',
)

gtk_dep = dependency('gtk4', version: '>= 4.14')

mermaid_lib = library('mermaid-gtk-0',
  core_sources, gtk_sources,
  dependencies: core_deps + [gtk_dep],
  vala_header: 'mermaid-gtk.h',
  vala_vapi: 'mermaid-gtk-0.vapi',
  install: not meson.is_subproject(),
  install_dir: [true, true, true],
)

mermaid_gtk_dep = declare_dependency(
  link_with: mermaid_lib,
  include_directories: include_directories('.'),
  dependencies: core_deps + [gtk_dep],
)
