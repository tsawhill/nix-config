{ config, pkgs, ... }:
let
  # Adds every video in the repo's wallpapers/ directory to the Nix store, keeps
  # it alive with a GC root, and records its hash in manifest.json so the
  # wallpaper module can reference it with requireFile.
  wallpapersSync = pkgs.writeShellApplication {
    name = "wallpapers-sync";
    runtimeInputs = [
      config.nix.package
      pkgs.coreutils
      pkgs.jq
    ];
    # jq filters reference $vars inside single quotes on purpose.
    excludeShellChecks = [ "SC2016" ];
    text = ''
      dir=''${1:-/mnt/zpool/code/nix-config/wallpapers}
      manifest=$dir/manifest.json
      roots=$dir/.gcroots
      mkdir -p "$roots"

      old='{}'
      if [ -f "$manifest" ]; then
        old=$(cat "$manifest")
      fi
      new='{}'
      status=0

      shopt -s nullglob
      for file in "$dir"/*; do
        name=''${file##*/}
        [ -f "$file" ] || continue
        [ "$name" != manifest.json ] || continue

        # Nix store path names only allow these characters.
        if [[ ! $name =~ ^[A-Za-z0-9+_?=-][A-Za-z0-9+._?=-]*$ ]]; then
          echo "skipping '$name': rename it using only letters, digits and + - _ . ? =" >&2
          status=1
          continue
        fi

        sum=$(jq -r --arg n "$name" '.[$n] // empty' <<<"$old")
        root=$roots/$name
        # Re-add only new or changed files; the root's own mtime marks the last add.
        if [ -z "$sum" ] || [ ! -L "$root" ] || [ "$(stat -c %Y "$file")" -gt "$(stat -c %Y "$root")" ]; then
          echo "adding $name" >&2
          sum=$(sha256sum "$file" | cut -d ' ' -f 1)
          path=$(nix-store --add-fixed sha256 "$file")
          rm -f "$root"
          nix-store --realise "$path" --add-root "$root" >/dev/null
        fi
        new=$(jq --arg n "$name" --arg s "$sum" '. + {($n): $s}' <<<"$new")
      done

      for root in "$roots"/*; do
        [ -e "$dir/''${root##*/}" ] || rm -f "$root"
      done

      jq --sort-keys . <<<"$new" >"$manifest"
      echo "$(jq length "$manifest") wallpapers in $manifest" >&2
      exit "$status"
    '';
  };
in
{
  environment.systemPackages = [ wallpapersSync ];
}
