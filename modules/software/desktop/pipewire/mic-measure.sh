# Guided mic level measurement that writes a filteredMics module for the repo.
# filtered-mic.nix prepends MIC_PROFILES, MIC_DEFAULTS and MIC_REFERENCE_PEAK.

takes=(room typing quiet normal loud)
declare -A cue=(
  [room]="Stay silent. Leave fans, AC and anything else that's usually on running."
  [typing]="Don't speak. Type and bump the desk the way you normally do."
  [quiet]="Read something aloud continuously, as softly as you still expect to be heard."
  [normal]="Keep reading aloud at your normal talking volume."
  [loud]="Read loudly: laugh, get excited, as loud as you get on calls."
)

usage() {
  cat <<EOF
Usage: mic-measure [-s SOURCE] [-c CHANNEL] [-d SECONDS] [-k] [-m] [-l]

Pick a mic, record ${#takes[@]} guided takes from it, and get a filteredMics
module with gate and compressor levels for it. Rerun after changing the mic's
gain or input volume.

  -s SOURCE   PipeWire source node.name instead of picking from a list
  -c CHANNEL  input channel, e.g. MONO or AUX0, instead of picking
  -d SECONDS  length of each take (default: 8)
  -k          keep the recordings
  -m          live level meter for setting the gain knob, instead of measuring
  -l          list capture devices and exit
EOF
}

die() {
  echo "mic-measure: $*" >&2
  exit 1
}

# node.name, description and channels of each hardware capture source.
devices() {
  pw-dump | jq -r '.[] | .info.props as $p
    | select(($p["media.class"] // "") == "Audio/Source" and $p["device.id"] != null)
    | [$p["node.name"], ($p["node.description"] // $p["node.name"]),
       ([.info.params.EnumFormat[]?.position[]?] | unique | join(","))]
    | @tsv'
}

source=""
channel=""
secs=8
keep=0
meter=0
while getopts 's:c:d:kmlh' opt; do
  case $opt in
    s) source=$OPTARG ;;
    c) channel=$OPTARG ;;
    d) secs=$OPTARG ;;
    k) keep=1 ;;
    m) meter=1 ;;
    l)
      devices | awk -F'\t' '{ printf "%s  [%s]  %s\n", $2, $3, $1 }'
      exit 0
      ;;
    h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done
if ! [[ $secs =~ ^[0-9]+$ ]] || ((secs < 3)); then die "-d needs whole seconds, at least 3"; fi

mapfile -t rows < <(devices)
((${#rows[@]})) || die "no capture devices found"
if [[ -z $source ]]; then
  echo "Capture devices:"
  for i in "${!rows[@]}"; do
    IFS=$'\t' read -r name desc positions <<<"${rows[i]}"
    known=$(jq -r --arg s "$name" '.[$s].name // empty' <<<"$MIC_PROFILES")
    printf '  %d) %s [%s]%s\n' "$((i + 1))" "$desc" "${positions:-channels unknown}" "${known:+  (module: $known)}"
  done
  read -rp "Device [1-${#rows[@]}]: " pick
  if ! [[ $pick =~ ^[0-9]+$ ]] || ((pick < 1 || pick > ${#rows[@]})); then die "no device $pick"; fi
  IFS=$'\t' read -r source desc positions <<<"${rows[pick - 1]}"
else
  row=$(printf '%s\n' "${rows[@]}" | awk -F'\t' -v s="$source" '$1 == s')
  [[ -n $row ]] || die "no capture device named '$source' (list them with: mic-measure -l)"
  IFS=$'\t' read -r source desc positions <<<"$row"
fi

# This mic's current settings if it already has a module, else the defaults.
settings=$(jq -c --arg s "$source" '.[$s] // empty' <<<"$MIC_PROFILES")
known=${settings:+1}
settings=${settings:-$MIC_DEFAULTS}

if [[ -z $channel ]]; then
  IFS=, read -ra chans <<<"$positions"
  current=$(jq -r '.channel // empty' <<<"$settings")
  if ((${#chans[@]} == 1)); then
    channel=${chans[0]}
  else
    fallback=${current:-${chans[0]:-MONO}}
    read -rp "Channel${positions:+ ($positions)} [$fallback]: " channel
    channel=${channel:-$fallback}
  fi
fi
if [[ -n $positions && ,$positions, != *",$channel,"* ]]; then
  die "'$desc' has channels $positions, not $channel"
fi

# Live peak meter: 10 updates a second, 2 s peak hold, bar from -60 to 0 dBFS.
if ((meter)); then
  echo "Live level of $desc ($channel); Ctrl-C to stop."
  echo "Turn the knob until normal talking peaks near -16 (first |) and loud laughs stay under -6 (second |)."
  pw-record --target "$source" --rate 48000 --channels 1 --channel-map "[$channel]" --format f32 --raw \
    -P '{ stream.dont-remix = true node.dont-fallback = true node.dont-reconnect = true }' - |
    ffmpeg -nostdin -hide_banner -loglevel error -f f32le -ar 48000 -ac 1 -i - -af \
      "asetnsamples=n=4800,astats=metadata=1:reset=1:measure_perchannel=none,ametadata=mode=print:key=lavfi.astats.Overall.Peak_level:file=/dev/stdout:direct=1" \
      -f null - |
    awk -F= '$1 == "lavfi.astats.Overall.Peak_level" {
      v = $2 ~ /inf/ ? -99 : $2 + 0
      held[n++ % 20] = v; hold = -99
      for (i in held) if (held[i] > hold) hold = held[i]
      bar = ""
      for (i = 0; i < 40; i++) bar = bar (-60 + i * 1.5 < v ? "#" : (i == 29 || i == 36 ? "|" : "."))
      verdict = hold > -3 ? "TOO HOT" : hold > -10 ? "loud range" : hold >= -20 ? "talking range" : "low"
      printf "\r%s %6.1f dBFS  peak %6.1f  %-13s", bar, v, hold, verdict
      fflush ()
    }'
  exit 0
fi

read -r hpf_mode hpf_hz preamp < <(jq -r '.gate | [(.["High-pass filter mode"] | floor),
  .["High-pass filter frequency (Hz)"], .["Sidechain preamp (G)"]] | @tsv' <<<"$settings")

dir=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/mic-measure.XXXXXX")
cleanup() {
  if ((keep)); then echo "Recordings kept in $dir"; else rm -rf "$dir"; fi
}
trap cleanup EXIT

record() {
  local rc=0
  # Same channel pick as the filter chain; brackets stop pw-record reading AUX0 as a layout.
  timeout --signal=INT "$secs" pw-record --target "$source" --rate 48000 \
    --channels 1 --channel-map "[$channel]" --format f32 \
    -P '{ stream.dont-remix = true node.dont-fallback = true node.dont-reconnect = true }' \
    "$dir/$1.wav" || rc=$?
  # timeout exits 124 when it ended a recording that ran the full length.
  ((rc == 124)) || die "pw-record failed (exit $rc) recording from $source"
}

# Prints: raw mean, raw peak, gate-envelope p50, p90, max (dBFS, -200 = digital silence).
analyze() {
  local hpf="" i
  for ((i = 0; i < hpf_mode; i++)); do hpf+="highpass=f=$hpf_hz:p=2,"; done
  # 480 samples = 10 ms, the gate's default RMS reactivity; skip the Enter keypress.
  ffmpeg -nostdin -hide_banner -nostats -loglevel error -ss 0.5 -i "$dir/$1.wav" -filter_complex \
    "[0:a]asetnsamples=n=480:p=0,asplit[raw][side];[raw]astats=metadata=1:reset=1:measure_perchannel=none,ametadata=mode=print:file=$dir/$1.raw[r];[side]${hpf}astats=metadata=1:reset=1:measure_perchannel=none,ametadata=mode=print:key=lavfi.astats.Overall.RMS_level:file=$dir/$1.side[s]" \
    -map '[r]' -f null - -map '[s]' -f null - || die "ffmpeg could not analyze the $1 take"
  awk -F= -v pre="$preamp" '
    function db(v) { return v ~ /inf|nan/ ? -200 : v + 0 }
    BEGIN { off = 20 * log(pre) / log(10); pk = -200 }
    FILENAME ~ /raw$/ && $1 == "lavfi.astats.Overall.RMS_level" { v = db($2); if (v > -200) pw += 10 ^ (v / 10); n++ }
    FILENAME ~ /raw$/ && $1 == "lavfi.astats.Overall.Peak_level" { v = db($2); if (v > pk) pk = v }
    FILENAME ~ /side$/ && $1 == "lavfi.astats.Overall.RMS_level" { v = db($2); s[++m] = v > -200 ? v + off : -200 }
    END {
      if (!n || !m) exit 1
      asort(s)
      printf "%.1f %.1f %.1f %.1f %.1f\n", (pw > 0 ? 10 * log(pw / n) / log(10) : -200), pk,
        s[int((m - 1) * 0.5) + 1], s[int((m - 1) * 0.9) + 1], s[m]
    }' "$dir/$1.raw" "$dir/$1.side" || die "no audio decoded from the $1 take"
}

echo
echo "Measuring $desc ($channel), ${secs}s per take."
echo "Set the gain and input volume where they will stay before starting."
for i in "${!takes[@]}"; do
  take=${takes[i]}
  printf '\n[%d/%d] %s: %s\n' "$((i + 1))" "${#takes[@]}" "$take" "${cue[$take]}"
  read -rp "Press Enter to start. " _
  echo "  recording..."
  record "$take"
done

results=""
for take in "${takes[@]}"; do
  results+="$take $(analyze "$take")"$'\n'
done

name_default=$(jq -r '.name // empty' <<<"$settings")
if [[ -z $name_default ]]; then
  name_default=$(awk '{ s = tolower($0); gsub(/[^a-z0-9]+/, "-", s); gsub(/^-+|-+$/, "", s); print s }' <<<"$desc")
fi
read -rp $'\n'"Module name [$name_default]: " name
name=${name:-$name_default}
[[ $name =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "module name must be lowercase letters, digits and dashes"
description=$(jq -r '.description // empty' <<<"$settings")
description=${description:-$desc (Processed)}
description=${description//[\"\\\$]/}

module=$dir/module.nix
awk -v pre="$preamp" -v hpf_mode="$hpf_mode" -v hpf_hz="$hpf_hz" -v known="$known" \
  -v gate_now="$(jq -r '.gate["Curve threshold (G)"]' <<<"$settings")" \
  -v comp_now="$(jq -r '.compressor["Attack threshold (G)"]' <<<"$settings")" \
  -v makeup_now="$(jq -r '.compressor["Makeup gain (G)"]' <<<"$settings")" \
  -v comp_ref="$(jq -r '.compressor["Attack threshold (G)"]' <<<"$MIC_DEFAULTS")" \
  -v makeup_ref="$(jq -r '.compressor["Makeup gain (G)"]' <<<"$MIC_DEFAULTS")" \
  -v ref_peak="$MIC_REFERENCE_PEAK" -v module="$module" -v name="$name" -v source="$source" \
  -v channel="$channel" -v description="$description" -v host="$(uname -n)" -v date="$(date +%F)" '
  function lg(g) { return 20 * log(g) / log(10) }
  function f(v) { return v <= -199 ? "-inf" : sprintf("%.1f", v) }
  function g(db) { return sprintf("%.4g", 10 ^ (db / 20)) }
  function half(v) { return int(v * 2 + (v < 0 ? -0.5 : 0.5)) / 2 }
  NF == 6 { mean[$1] = $2; peak[$1] = $3; p50[$1] = $4; p90[$1] = $5; max[$1] = $6; order[++n] = $1 }
  END {
    printf "\nLevels in dBFS. raw = whole take, full band. gate = the 10 ms RMS the gate\n"
    printf "compares with its threshold (sidechain high-pass %s, preamp %+.1f dB).\n\n",
      (hpf_mode > 0 ? sprintf("%g Hz", hpf_hz) : "off"), lg(pre)
    printf "%-8s %9s %7s %10s %7s %7s\n", "take", "raw mean", "peak", "gate p50", "p90", "max"
    for (i = 1; i <= n; i++) {
      t = order[i]
      printf "%-8s %9s %7s %10s %7s %7s\n", t, f(mean[t]), f(peak[t]), f(p50[t]), f(p90[t]), f(max[t])
    }
    print ""
    for (i = 1; i <= n; i++)
      if (peak[order[i]] > -0.5) printf "WARNING: the %s take clipped; lower the gain and rerun.\n", order[i]

    # p90 sits inside syllables even when half the take is pauses.
    room = max["room"]; quiet = p90["quiet"]
    if (quiet <= -199 || peak["normal"] <= -199) {
      print "Speech was silent: wrong device or channel, or the mic is muted."
      exit 1
    }
    if (room <= -199) {
      gt = half(quiet - 20)
      why = sprintf("Room is digital silence; 20 dB under quiet speech (%.1f).", quiet)
    } else if (room + 6 <= quiet - 10) {
      gt = half(room + 6)
      why = sprintf("6 dB over room noise (%.1f), %.1f under quiet speech (%.1f).", room, quiet - gt, quiet)
    } else {
      gt = half((room + quiet) / 2)
      why = sprintf("Room noise (%.1f) and quiet speech (%.1f) are only %.1f dB apart.", room, quiet, quiet - room)
    }
    # Shift the M2-tuned compressor by how far this mic sits from the M2.
    d = peak["normal"] - ref_peak
    ct = half(lg(comp_ref) + d); if (ct > -1) ct = -1
    mk = half(lg(makeup_ref) - d); if (mk < 0) mk = 0; if (mk > 24) mk = 24

    printf "Gate threshold      %6.1f dBFS  %s\n", gt, why
    printf "Compressor          %6.1f dBFS  normal speech peaks %+.1f dB from the M2\n", ct, d
    printf "Makeup gain         %+6.1f dB\n", mk
    if (known)
      printf "Configured now: gate %.1f, compressor %.1f, makeup %+.1f\n", lg(gate_now), lg(comp_now), lg(makeup_now)
    if (max["typing"] > gt)
      printf "Typing reaches %.1f in the gate, so its attack time and DeepFilterNet must reject it.\n", max["typing"]
    if (room > -199 && quiet - room < 16)
      print "Little room between noise and quiet speech: move the mic closer or raise the gain."

    printf "# Generated by mic-measure on %s, %s; rerun it after changing gain.\n", host, date > module
    printf "{\n  my.desktop.audio.filteredMics.%s = {\n", name > module
    printf "    source = \"%s\";\n    channel = \"%s\";\n    description = \"%s\";\n", source, channel, description > module
    printf "    controls = {\n      # %s\n", why > module
    printf "      gate.\"Curve threshold (G)\" = %s; # %.1f dBFS\n", g(gt), gt > module
    printf "      # Speech peaks %+.1f dB from the M2 reference; shifted to match.\n", d > module
    printf "      compressor.\"Attack threshold (G)\" = %s; # %.1f dBFS\n", g(ct), ct > module
    printf "      compressor.\"Makeup gain (G)\" = %s; # %+.1f dB\n", g(mk), mk > module
    printf "    };\n  };\n}\n" > module
  }' <<<"$results"

target=modules/software/desktop/pipewire/filtered-mics/$name.nix
printf '\n----- %s -----\n' "$target"
cat "$module"
read -rp $'\n'"Save as ./$name.nix? [Y/n] " save
if [[ ! $save =~ ^[Nn] ]]; then
  cp "$module" "./$name.nix"
  echo "Saved ./$name.nix; copy it to $target in the repo."
fi
