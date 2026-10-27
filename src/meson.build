conf = configuration_data()
conf.set('APP_ID', app_id)
conf.set('VERSION', meson.project_version())
conf.set('RESOURCE_PATH', resource_path)

config_vala = configure_file(
  input: 'config.vala.in',
  output: 'config.vala',
  configuration: conf,
)

libadwaita = dependency('libadwaita-1', version: '>= 1.5')
vala_args = ['--gresourcesdir=' + meson.current_build_dir()]

# libadwaita 1.8 replaces the deprecated GtkShortcutsWindow with AdwShortcutsDialog.
if libadwaita.version().version_compare('>= 1.8')
  shortcuts_ui = 'shortcuts/shortcuts-dialog'
  vala_args += ['--define=ADW_1_8']
else
  shortcuts_ui = 'shortcuts/shortcuts-window'
endif

blueprint_compiler = find_program('blueprint-compiler')
blueprints = []
foreach ui : [['window', 'window.blp'], ['shortcuts', shortcuts_ui + '.blp']]
  blueprints += custom_target(ui[0] + '-ui',
    input: ui[1],
    output: ui[0] + '.ui',
    command: [blueprint_compiler, 'compile', '--output', '@OUTPUT@', '@INPUT@'],
  )
endforeach

resources = gnome.compile_resources('notes-resources',
  'notes.gresource.xml',
  source_dir: [meson.current_build_dir(), meson.current_source_dir()],
  c_name: 'notes',
  dependencies: blueprints,
)

sources = files(
  'application.vala',
  'editor.vala',
  'files.vala',
  'state.vala',
  'window.vala',
  'markdown/ast.vala',
  'markdown/inline-parser.vala',
  'markdown/parser.vala',
  'markdown/renderer.vala',
  'widgets/file-tree.vala',
  'widgets/find-highlight.vala',
  'widgets/image-view.vala',
  'widgets/text-selection.vala',
  'widgets/wrap-box.vala',
)

# Mermaid diagrams. The library lives in subprojects/mermaid-gtk and is built
# into the app; see its README.
mermaid = dependency('mermaid-gtk-0',
  fallback: ['mermaid-gtk', 'mermaid_gtk_dep'],
  default_options: ['default_library=static'],
)

deps = [
  dependency('glib-2.0', version: '>= 2.76'),
  dependency('gio-2.0'),
  dependency('gtk4', version: '>= 4.14'),
  libadwaita,
  dependency('gtksourceview-5', version: '>= 5.10'),
  mermaid,
]

executable('gnome-markdown',
  sources, config_vala, resources,
  dependencies: deps,
  vala_args: vala_args,
  install: true,
)
