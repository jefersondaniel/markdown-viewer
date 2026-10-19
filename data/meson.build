desktop_conf = configuration_data()
desktop_conf.set('APP_ID', app_id)

configure_file(
  input: 'app.desktop.in',
  output: app_id + '.desktop',
  configuration: desktop_conf,
  install: true,
  install_dir: get_option('datadir') / 'applications',
)

install_data('icons' / app_id + '.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps',
)
