conf = configuration_data()
conf.set('APP_ID', app_id)
conf.set('VERSION', meson.project_version())
conf.set('RESOURCE_PATH', resource_path)

config_vala = configure_file(
  input: 'config.vala.in',
  output: 'config.vala',
  configuration: conf,
)

blueprints = custom_target('blueprints',
  input: files('window.blp'),
  output: '.',
  command: [find_program('blueprint-compiler'), 'batch-compile', '@OUTPUT@', '@CURRENT_SOURCE_DIR@', '@INPUT@'],
)

resources = gnome.compile_resources('notes-resources',
  'notes.gresource.xml',
  c_name: 'notes',
  dependencies: blueprints,
)

sources = files(
  'application.vala',
  'editor.vala',
  'note-store.vala',
  'state.vala',
  'window.vala',
  'markdown/ast.vala',
  'markdown/inline-parser.vala',
  'markdown/parser.vala',
  'markdown/renderer.vala',
  'widgets/image-view.vala',
  'widgets/wrap-box.vala',
)

deps = [
  dependency('glib-2.0', version: '>= 2.76'),
  dependency('gio-2.0'),
  dependency('gtk4', version: '>= 4.14'),
  dependency('libadwaita-1', version: '>= 1.5'),
  dependency('gtksourceview-5', version: '>= 5.10'),
]

executable('gnome-markdown',
  sources, config_vala, resources,
  dependencies: deps,
  vala_args: ['--gresourcesdir=' + meson.current_build_dir()],
  install: true,
)
