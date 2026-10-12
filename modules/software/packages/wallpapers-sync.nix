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
      pkgs.gnused
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

        # Store path names allow few characters, so turn anything else into "-".
        ext=
        if [[ $name =~ (\.[A-Za-z0-9]+)$ ]]; then
          ext=''${BASH_REMATCH[1]}
        fi
        # Also keeps half-finished downloads (.part, .crdownload) out.
        case ''${ext,,} in
          .mp4 | .m4v | .webm | .mkv | .mov) ;;
          *)
            echo "ignoring '$name': not a video file" >&2
            continue
            ;;
        esac
        base=$(sed -E 's/[^A-Za-z0-9._+-]+/-/g; s/-{2,}/-/g; s/^[-.]+//; s/[-.]+$//' <<<"''${name%"$ext"}")
        base=''${base:-wallpaper}
        safe=$base$ext
        if [ "$safe" != "$name" ]; then
          target=$safe
          i=2
          while [ -e "$dir/$target" ]; do
            target=$base-$i$ext
            i=$((i + 1))
          done
          mv -n -- "$file" "$dir/$target"
          echo "renamed '$name' -> '$target'" >&2
          name=$target
          file=$dir/$target
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
