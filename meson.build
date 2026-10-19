project('gnome-markdown', ['c', 'vala'],
  version: '0.1.0',
  meson_version: '>= 1.0.0',
  default_options: ['warning_level=2'],
)

gnome = import('gnome')

app_id = 'org.example.Notes'
resource_path = '/org/example/Notes'

# The generated C code is noisy; Vala already type-checks everything.
add_project_arguments('-w', '-DGETTEXT_PACKAGE="gnome-markdown"', language: 'c')

subdir('data')
subdir('src')

gnome.post_install(
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)
