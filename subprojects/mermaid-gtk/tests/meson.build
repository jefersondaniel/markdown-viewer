# Tests build the core sources directly, so they can reach internal code and
# so that the core is proven to build without GTK.
dagre_dump = executable('dagre-dump',
  core_sources, 'dagre-dump.vala',
  dependencies: core_deps,
)

mermaid_dump = executable('mermaid-dump',
  core_sources, 'mermaid-dump.vala',
  dependencies: core_deps,
)

python = find_program('python3')
cases_dir = meson.current_source_dir() / 'cases'

test('mermaid-cases', python,
  args: [files('run-cases.py'), mermaid_dump, cases_dir],
  suite: 'mermaid',
)

test('mermaid-inventory', python,
  args: [files('check-inventory.py'), files('../FEATURES.md'), cases_dir],
  suite: 'mermaid',
)

test('dagre', python,
  args: [files('run-dagre.py'), dagre_dump, meson.current_source_dir() / 'dagre'],
  suite: 'mermaid',
)
