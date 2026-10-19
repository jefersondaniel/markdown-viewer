# The release date shown in software centers comes from the newest entry that
# release-please wrote to the changelog, e.g. "## [0.2.0](...) (2026-11-02)".
release_date = '2026-10-19'
changelog = meson.project_source_root() / 'CHANGELOG.md'
if fs.exists(changelog)
  foreach line : fs.read(changelog).split('\n')
    line = line.strip()
    if line.startswith('## ') and line.endswith(')')
      release_date = line.split('(')[-1].replace(')', '')
      break
    endif
  endforeach
endif

data_conf = configuration_data()
data_conf.set('APP_ID', app_id)
data_conf.set('VERSION', meson.project_version())
data_conf.set('RELEASE_DATE', release_date)

desktop_file = configure_file(
  input: 'app.desktop.in',
  output: app_id + '.desktop',
  configuration: data_conf,
  install: true,
  install_dir: get_option('datadir') / 'applications',
)

metainfo_file = configure_file(
  input: 'app.metainfo.xml.in',
  output: app_id + '.metainfo.xml',
  configuration: data_conf,
  install: true,
  install_dir: get_option('datadir') / 'metainfo',
)

install_data('icons' / app_id + '.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps',
)
install_data('icons' / app_id + '-symbolic.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'symbolic' / 'apps',
)

desktop_file_validate = find_program('desktop-file-validate', required: false)
if desktop_file_validate.found()
  test('validate-desktop', desktop_file_validate, args: [desktop_file])
endif

appstreamcli = find_program('appstreamcli', required: false)
if appstreamcli.found()
  test('validate-metainfo', appstreamcli, args: ['validate', '--no-net', '--explain', metainfo_file])
endif
