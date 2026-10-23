#!/usr/bin/env bash
# description: Print a full-width divider of a repeated emoji or string.

set -euo pipefail

# Force a UTF-8 locale so bash's string indexing operates on Unicode
# characters (not raw bytes) regardless of the caller's environment.
export LC_ALL=C.UTF-8

# For the --date prefix: exports TZ from the user's timezone.
. "$(dirname "$0")/lib/dot-paths.sh"

ESC=$'\033'

# Real Unicode emoji-bearing ranges (decimal codepoint start/end pairs) that
# -r draws a random codepoint from via bash's builtin $RANDOM (no external
# dependency, e.g. shuf or /dev/urandom, required) and bash printf's \U
# escape to encode it as UTF-8. Covers Misc Symbols & Dingbats, Regional
# Indicators, and the main modern emoji block (Misc Symbols and Pictographs
# through Symbols and Pictographs Extended-A). A handful of codepoints in
# these ranges are unassigned/reserved and may render as a fallback "tofu"
# glyph depending on the terminal's font — an accepted tradeoff for drawing
# from the real emoji space instead of a small curated list.
EMOJI_RANGES=(
  "9728 10175"
  "127462 127487"
  "127744 129791"
)

random_emoji() {
  local total=0 start end size pick cp hex fmt r
  for r in "${EMOJI_RANGES[@]}"; do
    read -r start end <<< "$r"
    total=$(( total + end - start + 1 ))
  done
  pick=$(( RANDOM % total ))
  for r in "${EMOJI_RANGES[@]}"; do
    read -r start end <<< "$r"
    size=$(( end - start + 1 ))
    if [ "$pick" -lt "$size" ]; then
      cp=$(( start + pick ))
      break
    fi
    pick=$(( pick - size ))
  done
  printf -v hex '%08x' "$cp"
  fmt="\\U${hex}"
  printf -v RANDOM_EMOJI "$fmt"
}

usage() {
  cat <<EOF
bash dot emoji:hr — print a divider spanning the full terminal width, built from
a repeated character or string, like an <hr> or a markdown "---".

Measures the terminal (tput cols, then COLUMNS, then 80) and repeats the unit
to fill exactly that width, accounting for the double-width rendering of
emoji and East-Asian characters so the line lands flush instead of wrapping.
That arithmetic is the reason to call this rather than printing a guessed
number of dashes, which breaks as soon as the unit is an emoji.

Usage:
  bash dot emoji:hr <unit>|-r [rainbow|#RRGGBB] [--date]
  bash dot emoji:hr --help

Arguments:
  <unit>            character or string to repeat (any UTF-8 char, incl. emoji)
  -r                use a random emoji instead of <unit>
  rainbow|#RRGGBB   optional background: a rainbow gradient or a solid hex color

Flags:
  --date            prefix the line with the current time as "[HH:MM:SS] ";
                    the divider shrinks by the prefix so the line still ends
                    flush with the terminal edge. May appear in any position.

Notes:
  - -r draws from the real Unicode emoji blocks, so a few picks are
    unassigned and may render as a fallback "tofu" glyph.
  - Full specification: Features/f001--emoji-hr.md
EOF
}

die() {
  printf '❌ %s\n\n' "$1" >&2
  usage >&2
  exit 1
}

# --- argument parsing & validation -----------------------------------------

# --date is positional-agnostic, so strip the flags out first and let the
# <unit>/color checks below keep operating on plain positional arguments.
date_prefix=""
positional=()

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --date)    date_prefix="[$(date +%H:%M:%S)] " ;;
    *)         positional+=("$arg") ;;
  esac
done
set -- ${positional[@]+"${positional[@]}"}

[ "$#" -ge 1 ] || die "missing required <unit> argument (or -r for a random emoji)"
[ "$#" -le 2 ] || die "too many arguments"

if [ "$1" = "-r" ]; then
  random_emoji
  unit="$RANDOM_EMOJI"
else
  unit=$1
  [ -n "$unit" ] || die "<unit> must not be empty"
  # The unit is repeated straight onto the terminal, so an ESC or other C0
  # byte in it is not a character being drawn — it is a control sequence the
  # terminal obeys. Callers pass text that came from a file or a prompt, so
  # refuse it rather than emit it. Checked in the C locale, where the test
  # sees bytes and cannot mistake a UTF-8 continuation byte for a control.
  #
  # The newline is tested separately: grep splits its input on newlines, so
  # it never sees one as content and [[:cntrl:]] alone would let it through.
  if [[ "$unit" == *$'\n'* ]] || printf '%s' "$unit" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    die "<unit> must not contain control characters"
  fi
fi

color_mode="none"
color_hex=""

if [ "$#" -eq 2 ]; then
  case "$2" in
    rainbow)
      color_mode="rainbow"
      ;;
    '#'[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
      color_mode="solid"
      color_hex="$2"
      ;;
    *)
      die "second argument must be \"rainbow\" or a #RRGGBB hex color, got: $2"
      ;;
  esac
fi

# --- terminal width resolution: tput cols -> \$COLUMNS -> 80 ---------------

width=""
if command -v tput >/dev/null 2>&1; then
  width="$(tput cols 2>/dev/null || true)"
fi
if [[ ! "$width" =~ ^[0-9]+$ ]] || [ "$width" -le 0 ]; then
  width="${COLUMNS:-}"
fi
if [[ ! "$width" =~ ^[0-9]+$ ]] || [ "$width" -le 0 ]; then
  width=80
fi

# --- approximate display-width classification (wcwidth-like) ---------------
#
# Not exhaustive (doesn't special-case every ZWJ/skin-tone sequence) but
# covers common emoji and East-Asian-wide ranges well enough to track real
# terminal rendering more closely than a naive 1-column-per-character count.

codepoint_width() {
  local cp=$1
  # Zero-width: combining marks, variation selectors, ZWJ, skin-tone modifiers
  if [ "$cp" -eq 8205 ] || \
     { [ "$cp" -ge 768 ]   && [ "$cp" -le 879 ]; } || \
     { [ "$cp" -ge 65024 ] && [ "$cp" -le 65039 ]; } || \
     { [ "$cp" -ge 127995 ] && [ "$cp" -le 127999 ]; }; then
    echo 0
    return
  fi
  # Wide (double-width): CJK, Hangul, fullwidth forms, common emoji ranges
  if { [ "$cp" -ge 4352 ]   && [ "$cp" -le 4447 ]; } || \
     { [ "$cp" -ge 9728 ]   && [ "$cp" -le 10175 ]; } || \
     { [ "$cp" -ge 11904 ]  && [ "$cp" -le 42191 ]; } || \
     { [ "$cp" -ge 44032 ]  && [ "$cp" -le 55203 ]; } || \
     { [ "$cp" -ge 63744 ]  && [ "$cp" -le 64255 ]; } || \
     { [ "$cp" -ge 65280 ]  && [ "$cp" -le 65376 ]; } || \
     { [ "$cp" -ge 65504 ]  && [ "$cp" -le 65510 ]; } || \
     { [ "$cp" -ge 127462 ] && [ "$cp" -le 127487 ]; } || \
     { [ "$cp" -ge 127744 ] && [ "$cp" -le 129791 ]; } || \
     { [ "$cp" -ge 131072 ] && [ "$cp" -le 262141 ]; }; then
    echo 2
    return
  fi
  echo 1
}

display_width() {
  local s=$1 len=${#1} i=0 ch cp w total=0
  while [ "$i" -lt "$len" ]; do
    ch="${s:i:1}"
    cp=$(printf '%d' "'$ch")
    w=$(codepoint_width "$cp")
    total=$((total + w))
    i=$((i + 1))
  done
  echo "$total"
}

unit_width=$(display_width "$unit")
[ "$unit_width" -gt 0 ] || die "<unit> has no visible width (all zero-width characters)"

# --- reserve room for the --date prefix ------------------------------------
#
# The prefix is printed before the divider, so the divider gets what is left
# of the terminal. Clamped at 0 so a terminal narrower than the timestamp
# degrades to the bare prefix instead of a negative repeat count.

if [ -n "$date_prefix" ]; then
  width=$(( width - $(display_width "$date_prefix") ))
  [ "$width" -ge 0 ] || width=0
fi

# --- compute how many whole repetitions fit, never slicing a unit ----------

repeats=$(( width / unit_width ))
remainder=$(( width - repeats * unit_width ))

# --- hex -> RGB --------------------------------------------------------

hex_to_dec() {
  printf '%d' "0x$1"
}

# --- build the output line --------------------------------------------------

output=""

case "$color_mode" in
  none)
    for ((k = 0; k < repeats; k++)); do
      output+="$unit"
    done
    if [ "$remainder" -gt 0 ]; then
      output+="$(printf '%*s' "$remainder" '')"
    fi
    ;;

  solid)
    r=$(hex_to_dec "${color_hex:1:2}")
    g=$(hex_to_dec "${color_hex:3:2}")
    b=$(hex_to_dec "${color_hex:5:2}")
    bg="${ESC}[48;2;${r};${g};${b}m"
    line=""
    for ((k = 0; k < repeats; k++)); do
      line+="$unit"
    done
    if [ "$remainder" -gt 0 ]; then
      line+="$(printf '%*s' "$remainder" '')"
    fi
    output="${bg}${line}${ESC}[0m"
    ;;

  rainbow)
    last_r=255; last_g=0; last_b=0
    if [ "$repeats" -gt 0 ]; then
      denom=$(( repeats > 1 ? repeats - 1 : 1 ))
      for ((k = 0; k < repeats; k++)); do
        hue=$(( k * 300 / denom ))
        [ "$hue" -ge 300 ] && hue=299
        sector=$(( hue / 60 ))
        step=$(( (hue % 60) * 255 / 59 ))
        case "$sector" in
          0) r=255;            g=$step;            b=0   ;;
          1) r=$((255-step));  g=255;              b=0   ;;
          2) r=0;              g=255;              b=$step ;;
          3) r=0;              g=$((255-step));    b=255 ;;
          *) r=$step;          g=0;                b=255 ;;
        esac
        last_r=$r; last_g=$g; last_b=$b
        output+="${ESC}[48;2;${r};${g};${b}m${unit}"
      done
    fi
    if [ "$remainder" -gt 0 ]; then
      output+="${ESC}[48;2;${last_r};${last_g};${last_b}m$(printf '%*s' "$remainder" '')"
    fi
    output+="${ESC}[0m"
    ;;
esac

printf '%s%s\n' "$date_prefix" "$output"
