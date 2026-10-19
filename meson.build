project('gnome-markdown', ['c', 'vala'],
  version: files('version.txt'),  # maintained by release-please
  meson_version: '>= 1.0.0',
  default_options: ['warning_level=2'],
)

fs = import('fs')
gnome = import('gnome')

app_id = 'io.github.jefersondaniel.MarkdownViewer'
resource_path = '/io/github/jefersondaniel/MarkdownViewer'

# The generated C code is noisy; Vala already type-checks everything.
add_project_arguments('-w', '-DGETTEXT_PACKAGE="gnome-markdown"', language: 'c')

subdir('data')
subdir('src')

gnome.post_install(
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)
