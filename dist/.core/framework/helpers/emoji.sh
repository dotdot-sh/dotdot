#!/usr/bin/env bash

dot::use framework.helpers.text

EMOJI_RANGES=(
  "9728 10175"
  "127462 127487"
  "127744 129791"
)
EMOJI_ESCAPE=$'\033'
EMOJI_RAINBOW_HUES=300
EMOJI_HUE_SECTOR=60
EMOJI_CHANNEL_MAX=255

framework.helpers.emoji::random() {
  local total=0 start end size pick range
  for range in "${EMOJI_RANGES[@]}"; do
    read -r start end <<< "$range"
    total=$((total + end - start + 1))
  done
  pick=$((RANDOM % total))
  for range in "${EMOJI_RANGES[@]}"; do
    read -r start end <<< "$range"
    size=$((end - start + 1))
    if [ "$pick" -lt "$size" ]; then
      framework.helpers.text::character $((start + pick))
      return
    fi
    pick=$((pick - size))
  done
}

framework.helpers.emoji::background() {
  printf -v EMOJI_BACKGROUND '%s[48;2;%s;%s;%sm' "$EMOJI_ESCAPE" "$1" "$2" "$3"
}

framework.helpers.emoji::reset() {
  printf '%s[0m' "$EMOJI_ESCAPE"
}

framework.helpers.emoji::rainbow_color() {
  local index="$1" count="$2" denominator hue sector step
  denominator=$(( count > 1 ? count - 1 : 1 ))
  hue=$(( index * EMOJI_RAINBOW_HUES / denominator ))
  [ "$hue" -lt "$EMOJI_RAINBOW_HUES" ] || hue=$((EMOJI_RAINBOW_HUES - 1))
  sector=$(( hue / EMOJI_HUE_SECTOR ))
  step=$(( (hue % EMOJI_HUE_SECTOR) * EMOJI_CHANNEL_MAX / (EMOJI_HUE_SECTOR - 1) ))
  case "$sector" in
    0) printf -v EMOJI_RGB '%s %s %s' "$EMOJI_CHANNEL_MAX" "$step" 0 ;;
    1) printf -v EMOJI_RGB '%s %s %s' $((EMOJI_CHANNEL_MAX - step)) "$EMOJI_CHANNEL_MAX" 0 ;;
    2) printf -v EMOJI_RGB '%s %s %s' 0 "$EMOJI_CHANNEL_MAX" "$step" ;;
    3) printf -v EMOJI_RGB '%s %s %s' 0 $((EMOJI_CHANNEL_MAX - step)) "$EMOJI_CHANNEL_MAX" ;;
    *) printf -v EMOJI_RGB '%s %s %s' "$step" 0 "$EMOJI_CHANNEL_MAX" ;;
  esac
}

framework.helpers.emoji::divider() {
  local unit="$1" width="$2" color="$3" unit_width repeats remainder padding line="" index red green blue
  unit_width=$(framework.helpers.text::width "$unit")
  repeats=$((width / unit_width))
  remainder=$((width - repeats * unit_width))
  padding=$(printf '%*s' "$remainder" '')
  case "$color" in
    "")
      printf '%s%s' "$(framework.helpers.text::repeat "$unit" "$repeats")" "$padding"
      ;;
    rainbow)
      framework.helpers.emoji::background "$EMOJI_CHANNEL_MAX" 0 0
      for ((index = 0; index < repeats; index++)); do
        framework.helpers.emoji::rainbow_color "$index" "$repeats"
        read -r red green blue <<< "$EMOJI_RGB"
        framework.helpers.emoji::background "$red" "$green" "$blue"
        line="$line$EMOJI_BACKGROUND$unit"
      done
      [ "$remainder" -eq 0 ] || line="$line$EMOJI_BACKGROUND$padding"
      printf '%s%s' "$line" "$(framework.helpers.emoji::reset)"
      ;;
    *)
      framework.helpers.emoji::background $((16#${color:1:2})) $((16#${color:3:2})) $((16#${color:5:2}))
      printf '%s%s%s%s' "$EMOJI_BACKGROUND" "$(framework.helpers.text::repeat "$unit" "$repeats")" "$padding" "$(framework.helpers.emoji::reset)"
      ;;
  esac
}
