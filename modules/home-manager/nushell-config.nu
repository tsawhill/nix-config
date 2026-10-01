# Shared by the HM nushell module and the NixOS headless shell.
$env.config.show_banner = false
$env.config.edit_mode = 'emacs'
$env.config.table.mode = 'rounded'
$env.config.history.file_format = 'sqlite'
$env.config.history.max_size = 50000
$env.config.history.isolation = false
$env.config.color_config = ($env.config.color_config | merge {
  separator: '#414868'
  leading_trailing_space_bg: { attr: 'n' }
  row_index: '#bb9af7'
  string: '#9ece6a'
  int: '#ff9e64'
  float: '#ff9e64'
  bool: '#bb9af7'
  filesize: '#7dcfff'
  date: '#2ac3de'
  nothing: '#565f89'
  shape_internalcall: { fg: '#7aa2f7' attr: 'b' }
  shape_external: '#7dcfff'
  shape_string: '#9ece6a'
  shape_flag: '#bb9af7'
  shape_pipe: '#ff9e64'
  shape_variable: '#c0caf5'
})
