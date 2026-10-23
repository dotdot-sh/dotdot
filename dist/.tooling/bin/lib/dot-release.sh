#!/usr/bin/env bash
# dot-release.sh — the release config and the push tokens shared by release,
# release:push, and release:token.
#
# Every remote pushes over https with its own personal access token, so no key
# with access to a whole account is ever needed. A token is bound to the exact
# url of its remote and kept encrypted in the machine's secret store: the macOS
# keychain, the desktop keyring through libsecret, or, on a machine with
# neither (a container, a codespace), dotdot's .env, as RELEASE_PAT_<NAME>:
# the url and the token, encrypted together by gpg with a passphrase, in base64.
# It reaches git through a one-shot credential helper that answers only for
# the remote's host, never through a url, an argument, or a config file.
#
# Nothing is cached by default, so a gpg passphrase is asked on every push.
# TOKEN_CACHE_MINUTES (set from --cache-pat=N) keeps the decrypted token
# in git's in-memory credential cache, on a socket of dotdot's own, for N
# minutes from now; 0 drops it. While it lives, every push takes it from there.
#
# Source it after lib/dot-paths.sh and lib/dot-kv.sh; it uses the caller's fail().

REMOTE_NAME_PATTERN='^[a-z0-9][a-z0-9_-]*$'
REMOTE_URL_PATTERN='^https://[A-Za-z0-9.-]+(:[0-9]+)?/[^[:space:]@]+$'
TOKEN_PATTERN='^[A-Za-z0-9_-]{20,255}$'
TOKEN_CIPHER_PATTERN='^[A-Za-z0-9+/]+=*$'
TOKEN_SERVICE="dotdot-release"
TOKEN_CACHE_MINUTES=""
CACHE_MINUTES_PATTERN='^[0-9]{1,4}$'

# Settings are read as data, never sourced and never taken from the
# environment, so what the files say is exactly what runs. $2 picks the file:
# the config by default, dotdot's .env for the signing identity.
setting() {
  local file=${2:-$RELEASE_CONF} value
  [ -f "$file" ] || fail "$1 is needed, but $(dotdot_rel "$file") does not exist"
  value=$(kv_get "$file" "$1") || fail "$1 is missing in $(dotdot_rel "$file")"
  [ -n "$value" ] || fail "$1 is empty in $(dotdot_rel "$file")"
  printf '%s' "$value"
}

# Fills REMOTES (names) and REMOTE_URLS (their urls) from every
# RELEASE_REMOTE_<NAME> in the config, in file order, or fails.
release_remotes() {
  local keys key name url
  keys=$(awk '
    { sub(/\r$/, "") }
    /^[ \t]*(#|$)/ { next }
    {
      line = $0; sub(/^[ \t]*(export[ \t]+)?/, "", line)
      i = index(line, "="); if (i == 0) next
      key = substr(line, 1, i - 1); sub(/[ \t]+$/, "", key)
      if (key ~ /^RELEASE_REMOTE_[A-Za-z0-9_]+$/ && !seen[key]++) print key
    }
  ' "$RELEASE_CONF")
  [ -n "$keys" ] || fail "no RELEASE_REMOTE_<NAME> in $(dotdot_rel "$RELEASE_CONF"); at least one remote is required"
  REMOTES=()
  REMOTE_URLS=()
  for key in $keys; do
    name=$(echo "${key#RELEASE_REMOTE_}" | tr '[:upper:]' '[:lower:]')
    url=$(setting "$key")
    [[ $name =~ $REMOTE_NAME_PATTERN && $name != help && $name != push-all ]] \
      || fail "unusable remote name (letters, digits, _ and -; not help or push-all): $name"
    [[ $url =~ $REMOTE_URL_PATTERN ]] \
      || fail "$key must be an https:// url without credentials in it (pushes authenticate with a token): $url"
    REMOTES+=("$name")
    REMOTE_URLS+=("$url")
  done
}

# Prints the url of remote $1, or fails when the config has no such remote.
release_remote_url() {
  local i
  for i in "${!REMOTES[@]}"; do
    [ "${REMOTES[$i]}" != "$1" ] || { printf '%s' "${REMOTE_URLS[$i]}"; return 0; }
  done
  fail "no remote $1 configured; add RELEASE_REMOTE_${1^^} to $(dotdot_rel "$RELEASE_CONF")"
}

# The secret store this machine offers: keychain, libsecret, or gpg.
token_store() {
  if [ "$(uname -s)" = Darwin ] && command -v security >/dev/null; then echo keychain
  elif command -v secret-tool >/dev/null && [ -n "${DBUS_SESSION_BUS_ADDRESS-}" ]; then echo libsecret
  elif command -v gpg >/dev/null; then echo gpg
  else fail "no secret store found: install gpg, or libsecret's secret-tool"
  fi
}

# A token is filed under a hash of its remote's url, so it serves that one
# repo and a changed url never reuses it.
token_id() {
  printf '%s' "$1" | git hash-object --stdin
}

# The .env key holding the gpg-encrypted token for url $1: RELEASE_PAT_<NAME>,
# after the configured remote with that url.
token_env_key() {
  local i
  for i in "${!REMOTE_URLS[@]}"; do
    [ "${REMOTE_URLS[$i]}" != "$1" ] || { printf 'RELEASE_PAT_%s' "${REMOTES[$i]^^}"; return 0; }
  done
  return 1
}

# Saves token $2 for url $1, replacing any earlier one. The token never goes
# on a command line, where other processes could read it: it is piped in.
token_save() {
  local id store key cipher remote
  [[ $2 =~ $TOKEN_PATTERN ]] || fail "that does not look like a token (letters, digits, _ and -)"
  id=$(token_id "$1")
  store=$(token_store)
  case "$store" in
    keychain)
      printf 'add-generic-password -U -s %s -a %s -w %s\n' "$TOKEN_SERVICE" "$id" "$2" | security -i >/dev/null
      ;;
    libsecret)
      printf '%s' "$2" | secret-tool store --label="dotdot release token for $1" service "$TOKEN_SERVICE" id "$id"
      ;;
    gpg)
      key=$(token_env_key "$1") || return 1
      remote=${key#RELEASE_PAT_}
      echo "🔐 Choose a passphrase to encrypt the token for ${remote,,}, then repeat it; pushes ask for it" >&2
      # The slowest key derivation gpg offers, so each passphrase guess costs most.
      cipher=$(printf '%s\n%s' "$1" "$2" | gpg --quiet --pinentry-mode loopback --no-symkey-cache \
        --symmetric --cipher-algo AES256 --s2k-mode 3 --s2k-digest-algo SHA512 --s2k-count 65011712 \
        --output - | base64 | tr -d '\n') || return 1
      [[ $cipher =~ $TOKEN_CIPHER_PATTERN ]] || return 1
      (umask 077 && kv_set "$ENV_FILE" "$key" "$cipher") && chmod 600 "$ENV_FILE" || return 1
      ;;
  esac
  token_cache erase "$1" </dev/null || true
  token_exists "$1"
}

# Prints the token stored for url $1, or fails when none is stored or what is
# stored is not token-shaped (a newline in it would forge credential lines).
token_read() {
  local id token
  id=$(token_id "$1")
  token=$(case "$(token_store)" in
    keychain) security find-generic-password -s "$TOKEN_SERVICE" -a "$id" -w 2>/dev/null ;;
    libsecret) secret-tool lookup service "$TOKEN_SERVICE" id "$id" 2>/dev/null ;;
    gpg) token_decrypt "$1" ;;
  esac) || return 1
  [[ $token =~ $TOKEN_PATTERN ]] || return 1
  printf '%s' "$token"
}

# Prints the token in .env for url $1, after gpg decrypts it and the url
# encrypted with it matches $1: a value copied from another remote is refused.
# Only a passphrase-encrypted message whose integrity check passed counts: an
# unencrypted one, or one encrypted to a key, would decrypt without the
# passphrase, so whoever could write .env could choose the token.
token_decrypt() {
  local key cipher plain status remote
  key=$(token_env_key "$1") && cipher=$(kv_get "$ENV_FILE" "$key") || return 1
  [[ $cipher =~ $TOKEN_CIPHER_PATTERN ]] || return 1
  status=$(mktemp) || return 1
  remote=${key#RELEASE_PAT_}
  echo "🔐 Pushing to ${remote,,}: enter the passphrase of this remote's token" >&2
  plain=$(printf '%s' "$cipher" | base64 -d | gpg --quiet --pinentry-mode loopback --no-symkey-cache \
    --status-file "$status" --decrypt) || { rm -f -- "$status"; return 1; }
  if ! grep -q '^\[GNUPG:\] NEED_PASSPHRASE_SYM ' "$status" || ! grep -q '^\[GNUPG:\] DECRYPTION_OKAY' "$status" \
    || grep -q '^\[GNUPG:\] ENC_TO ' "$status"; then
    rm -f -- "$status"
    echo "$key in $(dotdot_rel "$ENV_FILE") is not a passphrase-encrypted token; store it again with bash dot release:token" >&2
    return 1
  fi
  rm -f -- "$status"
  [ "${plain%%$'\n'*}" = "$1" ] \
    || { echo "$key in $(dotdot_rel "$ENV_FILE") was stored for another url; store it again with bash dot release:token" >&2; return 1; }
  printf '%s' "${plain#*$'\n'}"
}

# Runs git's credential cache action $1 for url $2 on dotdot's own socket; the
# credential, keyed by the token's id, comes from stdin, $3 sets the seconds
# it lives. The token is piped, never an argument.
token_cache() {
  mkdir -p "$(dirname -- "$RELEASE_TOKEN_CACHE")" && chmod 700 "$(dirname -- "$RELEASE_TOKEN_CACHE")" || return 1
  { printf 'protocol=https\nhost=%s\npath=%s\n' "$TOKEN_SERVICE" "$(token_id "$2")"; cat; echo; } \
    | git credential-cache ${3:+--timeout="$3"} --socket="$RELEASE_TOKEN_CACHE" "$1"
}

# Prints the token for url $1: from the cache while it lives, else from the
# store. With TOKEN_CACHE_MINUTES set, the cache restarts for that long (0
# drops it, so the store is asked). Pass it straight to git; never print or log it.
token_load() {
  local token=""
  if [ "$TOKEN_CACHE_MINUTES" = 0 ]; then
    token_cache erase "$1" </dev/null || true
  else
    token=$(token_cache get "$1" </dev/null 2>/dev/null | sed -n 's/^password=//p') || token=""
  fi
  [[ $token =~ $TOKEN_PATTERN ]] || token=$(token_read "$1") || return 1
  if [ -n "$TOKEN_CACHE_MINUTES" ] && [ "$TOKEN_CACHE_MINUTES" != 0 ]; then
    printf 'username=token\npassword=%s\n' "$token" | token_cache store "$1" $((10#$TOKEN_CACHE_MINUTES * 60)) || return 1
  fi
  printf '%s' "$token"
}

# True when a token is stored for url $1, without decrypting it where the
# store allows that.
token_exists() {
  case "$(token_store)" in
    keychain) security find-generic-password -s "$TOKEN_SERVICE" -a "$(token_id "$1")" >/dev/null 2>&1 ;;
    libsecret) token_read "$1" >/dev/null ;;
    gpg) token_env_key "$1" >/dev/null && [ -n "$(kv_get "$ENV_FILE" "$(token_env_key "$1")" 2>/dev/null)" ] ;;
  esac
}

# Removes the token for url $1; fails when none was stored.
token_remove() {
  local id
  id=$(token_id "$1")
  token_cache erase "$1" </dev/null || true
  case "$(token_store)" in
    keychain) security delete-generic-password -s "$TOKEN_SERVICE" -a "$id" >/dev/null 2>&1 ;;
    libsecret) token_exists "$1" && secret-tool clear service "$TOKEN_SERVICE" id "$id" ;;
    gpg) token_exists "$1" && kv_unset "$ENV_FILE" "$(token_env_key "$1")" ;;
  esac
}

# Answers git's "get" with the token, only for https on the remote's own host;
# every other request (store, erase, a redirect elsewhere) gets nothing.
TOKEN_HELPER='!f() { [ "$1" = get ] || return 0; p=; h=; while IFS= read -r line && [ -n "$line" ]; do case $line in protocol=*) p=${line#protocol=} ;; host=*) h=${line#host=} ;; esac; done; [ "$p" = https ] && [ "$h" = "$RELEASE_TOKEN_HOST" ] || return 0; printf "username=x-access-token\npassword=%s\n" "$RELEASE_TOKEN"; }; f'

# Runs "git push" in repo $1 to remote $2 at url $3 with the rest as
# arguments, authenticated by the stored token. Every configured credential
# helper and password prompt is switched off, so the token is the only way in;
# hooks are off, since they would run with the token in their environment;
# TLS is verified and curl traces redact it, whatever the config or env says.
token_push() {
  local repo=$1 name=$2 url=$3 token host
  shift 3
  token=$(token_load "$url") && [ -n "$token" ] \
    || { printf '%s❌ no token for %s. Store one: bash dot release:token %s%s\n' "$RED$BOLD" "$name" "$name" "$RESET" >&2; return 1; }
  host=${url#https://}
  host=${host%%/*}
  RELEASE_TOKEN=$token RELEASE_TOKEN_HOST=$host GIT_TERMINAL_PROMPT=0 GIT_TRACE_REDACT=1 \
    env -u GIT_ASKPASS -u SSH_ASKPASS -u GIT_SSL_NO_VERIFY \
    git -C "$repo" -c credential.helper= -c "credential.helper=$TOKEN_HELPER" -c core.askPass= \
    -c core.hooksPath=/dev/null -c http.sslVerify=true \
    push "$name" "$@"
}

# A flag or --push-all pushes; otherwise ask, defaulting to no, and without a
# terminal to ask on, leave the push to the printed command.
wants_push() {
  $PUSH_ALL && return 0
  [[ " ${PUSH_TO[*]} " == *" $1 "* ]] && return 0
  confirm "Push $TAG to $1?"
}

# Points the release repo's remotes at the configured urls, then pushes
# $BRANCH and every tag to each one wanted, force pushing when $FORCE. Tags
# are named outright rather than followed, since --follow-tags skips a tag the
# remote already has under another commit; --atomic lands the branch and the
# tags together or not at all. Reads
# DEST, BRANCH, TAG, PUSH_ALL, PUSH_TO, and FORCE from the caller; needs
# lib/dot-confirm.sh and the caller's rel().
release_push() {
  local i name failed=0 force=""
  ! $FORCE || force=--force
  for i in "${!REMOTES[@]}"; do
    if rel remote get-url "${REMOTES[$i]}" >/dev/null 2>&1; then rel remote set-url "${REMOTES[$i]}" "${REMOTE_URLS[$i]}"
    else rel remote add "${REMOTES[$i]}" "${REMOTE_URLS[$i]}"; fi
    # A pushurl would send the push, and so the token, past the configured url.
    rel config --unset-all "remote.${REMOTES[$i]}.pushurl" || true
  done

  echo
  for i in "${!REMOTES[@]}"; do
    name=${REMOTES[$i]}
    if wants_push "$name"; then
      if token_push "$DEST" "$name" "${REMOTE_URLS[$i]}" -q --atomic ${force:+"$force"} "refs/heads/$BRANCH" --tags; then
        printf '%s✅ %spushed to %s%s\n' "$GREEN$BOLD" "$RESET$GREEN" "$name" "$RESET"
      else
        printf '%s❌ push to %s failed.%s Retry: bash dot release:push --%s%s\n' "$RED$BOLD" "$name" "$RESET" "$name" "${force:+ --force}" >&2
        failed=$((failed + 1))
      fi
    else
      printf 'Not pushed to %s. Later: bash dot release:push --%s%s\n' "$name" "$name" "${force:+ --force}"
    fi
  done
  echo
  [ "$failed" -eq 0 ] || fail "$failed push(es) failed; the release commit and tag are kept"
}
