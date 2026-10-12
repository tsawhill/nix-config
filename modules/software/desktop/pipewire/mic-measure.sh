# Guided level measurement for filteredMic's absolute-dBFS thresholds.
# filtered-mic.nix prepends MIC_SOURCE, MIC_CHANNEL, GATE_* and COMP_THRESHOLD.

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
Usage: mic-measure [-s SOURCE] [-c CHANNEL] [-d SECONDS] [-k] [-l]

Records ${#takes[@]} guided takes from the raw mic and reports the levels the
filteredMic gate and compressor thresholds depend on. Rerun after changing the
hardware gain or input volume.

  -s SOURCE   PipeWire source node.name (default: $MIC_SOURCE)
  -c CHANNEL  input channel, e.g. MONO or AUX0 (default: $MIC_CHANNEL)
  -d SECONDS  length of each take (default: 8)
  -k          keep the recordings
  -l          list capture sources and exit
EOF
}

die() {
  echo "mic-measure: $*" >&2
  exit 1
}

list_sources() {
  pw-dump | jq -r '.[]
    | select((.info.props["media.class"] // "") | startswith("Audio/Source"))
    | "\(.info.props["node.name"])  [\([.info.params.EnumFormat[]?.position[]?] | unique | join(","))]  \(.info.props["node.description"] // "")"'
}

source=$MIC_SOURCE
channel=$MIC_CHANNEL
secs=8
keep=0
while getopts 's:c:d:klh' opt; do
  case $opt in
    s) source=$OPTARG ;;
    c) channel=$OPTARG ;;
    d) secs=$OPTARG ;;
    k) keep=1 ;;
    l)
      list_sources
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

# A missing target would silently fall back to the default source.
positions=$(pw-dump | jq -r --arg n "$source" '
  [.[] | select(.info.props["node.name"] == $n)]
  | if length == 0 then "missing"
    else [.[].info.params.EnumFormat[]?.position[]?] | unique | join(",") end')
case $positions in
  missing) die "no PipeWire node named '$source' (list them with: mic-measure -l)" ;;
  "") ;;
  *) [[ ,$positions, == *",$channel,"* ]] || die "'$source' has channels $positions, not $channel" ;;
esac

dir=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/mic-measure.XXXXXX")
cleanup() {
  if ((keep)); then echo "Recordings kept in $dir"; else rm -rf "$dir"; fi
}
trap cleanup EXIT

record() {
  local rc=0
  # Same channel pick as the filter chain's capture stream.
  timeout --signal=INT "$secs" pw-record --target "$source" --rate 48000 \
    --channels 1 --channel-map "$channel" --format f32 \
    -P '{ stream.dont-remix = true node.dont-fallback = true node.dont-reconnect = true }' \
    "$dir/$1.wav" || rc=$?
  # timeout exits 124 when it ended a recording that ran the full length.
  ((rc == 124)) || die "pw-record failed (exit $rc) recording from $source"
}

# Prints: raw mean, raw peak, gate-envelope p50, p90, max (dBFS, -200 = digital silence).
analyze() {
  local hpf="" i
  for ((i = 0; i < GATE_HPF_MODE; i++)); do hpf+="highpass=f=$GATE_HPF_HZ:p=2,"; done
  # 480 samples = 10 ms, the gate's default RMS reactivity; skip the Enter keypress.
  ffmpeg -hide_banner -nostats -loglevel error -ss 0.5 -i "$dir/$1.wav" -filter_complex \
    "[0:a]asetnsamples=n=480:p=0,asplit[raw][side];[raw]astats=metadata=1:reset=1:measure_perchannel=none,ametadata=mode=print:file=$dir/$1.raw[r];[side]${hpf}astats=metadata=1:reset=1:measure_perchannel=none,ametadata=mode=print:key=lavfi.astats.Overall.RMS_level:file=$dir/$1.side[s]" \
    -map '[r]' -f null - -map '[s]' -f null - || die "ffmpeg could not analyze the $1 take"
  awk -F= -v pre="$GATE_PREAMP" '
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

echo "Measuring $source ($channel), ${secs}s per take."
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

awk -v hpf_mode="$GATE_HPF_MODE" -v hpf_hz="$GATE_HPF_HZ" -v pre="$GATE_PREAMP" \
  -v gate="$GATE_THRESHOLD" -v comp="$COMP_THRESHOLD" '
  function lg(g) { return 20 * log(g) / log(10) }
  function f(v) { return v <= -199 ? "-inf" : sprintf("%.1f", v) }
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
      if (peak[order[i]] > -0.5) printf "WARNING: the %s take clipped; lower the hardware gain and rerun.\n", order[i]

    # p90 sits inside syllables even when half the take is pauses.
    room = max["room"]; quiet = p90["quiet"]
    if (quiet <= -199) { print "Quiet speech was silent: wrong source or channel, or the mic is muted."; exit }
    if (room <= -199) {
      t = quiet - 20
      why = "The room take was digital silence (the device gates itself), so this sits 20 dB under quiet speech."
    } else if (room + 6 <= quiet - 10) {
      t = room + 6
      why = sprintf("6 dB above the loudest room noise (%.1f), %.1f dB under quiet speech (p90 %.1f).", room, quiet - t, quiet)
    } else {
      t = (room + quiet) / 2
      why = sprintf("Room noise (max %.1f) and quiet speech (p90 %.1f) are only %.1f dB apart, so this splits\n  the difference. Move the mic closer or raise the gain if word onsets get cut, and lean on RNNoise.", room, quiet, quiet - room)
    }
    t = int(t * 2 + (t < 0 ? -0.5 : 0.5)) / 2
    printf "Suggested starting values:\n"
    printf "  gate.\"Curve threshold (G)\" = %.4g; # %.1f dBFS\n", 10 ^ (t / 20), t
    printf "  %s\n  Configured now: %.4g (%.1f dBFS).\n", why, gate, lg(gate)
    if (max["typing"] > t)
      printf "  Typing reaches %.1f, above the threshold: the gate cannot reject it by level, so its\n  attack time and RNNoise have to.\n", max["typing"]
    else
      printf "  Typing stays under the threshold (max %.1f), so the gate rejects it by level.\n", max["typing"]
    printf "\nThe compressor threshold is %.4g (%.1f dBFS); speech peaks are normal %s, loud %s.\n", comp, lg(comp), f(peak["normal"]), f(peak["loud"])
    printf "Like the gate it is absolute: if only the gain changed, shift it by the same number of dB\n"
    printf "that these levels moved.\n"
  }' <<<"$results"
