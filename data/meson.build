data_conf = configuration_data()
data_conf.set('APP_ID', app_id)

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

desktop_file_validate = find_program('desktop-file-validate', required: false)
if desktop_file_validate.found()
  test('validate-desktop', desktop_file_validate, args: [desktop_file])
endif

appstreamcli = find_program('appstreamcli', required: false)
if appstreamcli.found()
  test('validate-metainfo', appstreamcli, args: ['validate', '--no-net', '--explain', metainfo_file])
endif
