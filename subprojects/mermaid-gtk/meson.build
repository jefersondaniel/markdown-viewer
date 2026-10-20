project('mermaid-gtk', ['c', 'vala'],
  version: '0.1.0',
  license: 'GPL-3.0-or-later',
  meson_version: '>= 1.0.0',
  default_options: ['warning_level=2'],
)

# The generated C code is noisy; Vala already type-checks everything.
add_project_arguments('-w', language: 'c')

cc = meson.get_compiler('c')
glib = dependency('glib-2.0', version: '>= 2.76')
gobject = dependency('gobject-2.0')
libm = cc.find_library('m', required: false)

core_deps = [glib, gobject, libm]

subdir('src')
subdir('tests')

meson.override_dependency('mermaid-gtk-0', mermaid_gtk_dep)

if not meson.is_subproject()
  executable('mermaid-demo',
    'demo/mermaid-demo.vala',
    dependencies: [mermaid_gtk_dep, dependency('pangocairo'), dependency('cairo')],
  )
endif
