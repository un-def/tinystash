std = 'ngx_lua'
exclude_files = {
  'resty_modules/**',
}
files['commands'] = {
    read_globals = {
      'OPENRESTY_PREFIX',
      'TINYSTASH_DIR',
      'run_command',
    },
}
