std = 'ngx_lua'
codes = true
exclude_files = {
  'resty_modules/**',
  'config.lua',
}
files['commands'] = {
    read_globals = {
      'OPENRESTY_PREFIX',
      'TINYSTASH_DIR',
      'run_command',
    },
}
