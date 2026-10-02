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

# Hostnames from known_hosts and ~/.ssh/config, keeping any user@ prefix.
def ssh-hosts [word: string] {
  let user = if ($word | str contains '@') { ($word | split row '@' | first) + '@' } else { '' }
  # NixOS lists knownHostsFiles in GlobalKnownHostsFile, so ask ssh for the paths.
  let known = ^ssh -G x err> /dev/null | lines | parse '{key} {value}'
    | where key in [globalknownhostsfile userknownhostsfile]
    | get value | each { split row ' ' } | flatten | path expand
    | where ($it | path exists)
    | each { open --raw $in | lines | where $it !~ '^\s*($|#|@|\|)' | each { split row ' ' | first | split row ',' } }
    | flatten | flatten
  let config = ($env.HOME | path join .ssh/config)
  let aliases = if ($config | path exists) {
    open --raw $config | lines | parse -r '(?i)^\s*host\s+(?<h>.+)$' | get h | each { split row ' ' } | flatten
  } else { [] }
  $known | append $aliases
    | str replace -r '^\[(.+)\]:\d+$' '$1'
    | where $it !~ '[*?!]'
    | uniq | sort
    | each { $user + $in }
}

# ssh hosts ourselves, everything else via carapace; null means file completion.
$env.config.completions.external = {
  enable: true
  completer: {|spans|
    let alias = (scope aliases | where name == $spans.0 | get -o 0.expansion)
    let spans = if $alias != null { $alias | split row ' ' | append ($spans | skip 1) } else { $spans }
    let word = ($spans | last)
    let prev = ($spans | drop 1 | last)
    let flag_args = [-b -B -c -D -E -e -F -I -i -L -l -m -O -o -p -Q -R -S -W -w]
    if $spans.0 in [ssh sftp mosh] and not ($word | str starts-with '-') and $prev not-in $flag_args {
      ssh-hosts $word
    } else if (which carapace | is-not-empty) {
      carapace $spans.0 nushell ...$spans | from json
        | if ($in | default [] | where value =~ '^-.*ERR$' | is-empty) { $in } else { null }
    }
  }
}
