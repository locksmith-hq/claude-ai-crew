#!/usr/bin/env bash
# Runs a scheduled agent as its GitHub App persona instead of the owner's account.
# A persona is a role key from crew.json `.roles`; its bot login is `crew_role_login <role>` ("<app>[bot]").
#   agent-identity.sh setup <role>   git author, push credentials and a gh shim in BOTH checkouts (plan and code);
#                                    on any failure undoes them, prints FAIL and exits 1
#   agent-identity.sh token          prints a valid installation token (cached, re-minted after 50 minutes)
#   agent-identity.sh credential get git credential helper
#   agent-identity.sh keyvar <role>  the name of the variable that holds the role's App key (never its value)
#   agent-identity.sh logins [role]  the role's GitHub logins, one per line (default: the recorded persona)
#   agent-identity.sh selftest       offline checks
# Per role (ROLE = the role key upper-cased, "-" -> "_"):
#   AGENT_APP_ID_<ROLE>   the App id (not secret)
#   AGENT_APP_KEY_<ROLE>  base64 of the App's PEM private key. On macOS the login Keychain item
#                         "crew-agent-<role>" (same base64) is the fallback.
#   AGENT_INSTALLATION_ID_<ROLE>  optional; found through the API (the plan repo's installation) when unset.
# The App must be installed on the plan repo and the code repo, with one installation covering both.
# A network secret cannot do this job: the JWT that the token request needs expires within 10 minutes, so it is
# signed here on every mint. Never print the key or the token.
set -uo pipefail
. "$(dirname "$0")/lib/crew-env.sh"
state="${AGENT_ID_DIR:-$HOME/.config/crew-agent}"
self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
api="${AGENT_API_URL:-https://api.github.com}"

role_var() { tr '[:lower:]-' '[:upper:]_' <<<"$1"; }
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
jwt() { # <app_id> <pem-file>
  local now h p
  now=$(date +%s)
  h=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
  p=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 30)) $((now + 300)) "$1" | b64url)
  printf '%s.%s.%s' "$h" "$p" "$(printf '%s.%s' "$h" "$p" | openssl dgst -sha256 -sign "$2" | b64url)"
}
# keyvar <role>: the key variable: roles.<role>.key_env when it is set in this environment, else AGENT_APP_KEY_<ROLE>
# when that one is set (an environment moved to the role names keeps working), else key_env or the default name.
keyvar() {
  local d k; d="AGENT_APP_KEY_$(role_var "$1")"; k=$(crew_get ".roles[\"$1\"].key_env" "$d")
  if [ -z "${!k:-}" ] && [ -n "${!d:-}" ]; then echo "$d"; else echo "$k"; fi
}
why() { printf '%s' "$1" >"$state/why"; }
# app_jwt <role>: prints a fresh App JWT. Each failure records its cause in $state/why, so the WARN line says what to fix.
app_jwt() {
  local role="$1" rv key pem app j
  rv=$(role_var "$role")
  # crew.json may name the variables (roles.<role>.key_env / id_env), so a project that already stores App keys under
  # other names (for example per-persona names) keeps its environment unchanged.
  local kv iv
  kv=$(keyvar "$role"); iv=$(crew_get ".roles[\"$role\"].id_env" "AGENT_APP_ID_$rv")
  app="${!iv:-}"
  # The App id is public: crew.json can carry it (roles.<role>.app_id). Preferred: a cloud session shares an IP, so an
  # unauthenticated lookup hits GitHub's rate limit, and a session proxy refuses the path (both observed).
  [ -n "$app" ] || app=$(crew_get ".roles[\"$role\"].app_id")
  # Last resort: look it up by slug (GET /apps/<slug>) and cache it.
  if [ -z "$app" ]; then
    [ -s "$state/appid-$role" ] && app=$(cat "$state/appid-$role")
    if [ -z "$app" ]; then
      local slug; slug=$(crew_get ".roles[\"$role\"].app")
      [ -n "$slug" ] && app=$(curl -fsS --noproxy '*' -H "Accept: application/vnd.github+json" "$api/apps/$slug" 2>/dev/null | jq -r '.id // empty' 2>/dev/null)
      [ -n "$app" ] && printf '%s' "$app" >"$state/appid-$role"
    fi
  fi
  [ -n "$app" ] || { why "$iv is not set in this environment and the App id could not be looked up"; return 1; }
  key="${!kv:-}"
  [ -n "$key" ] || ! command -v security >/dev/null || key=$(security find-generic-password -s "crew-agent-$role" -w 2>/dev/null)
  [ -n "$key" ] || { why "$kv is not set in this environment"; return 1; }
  pem=$(umask 077 && mktemp) || return 1
  printf '%s' "$key" | openssl base64 -d -A >"$pem" 2>/dev/null
  grep -q 'PRIVATE KEY' "$pem" || { rm -f "$pem"; why "$kv is not the base64 of a private key file (${#key} characters)"; return 1; }
  j=$(jwt "$app" "$pem"); rm -f "$pem"
  printf '%s' "$j"
}
# gh_api <jwt> <path>: GET with the App JWT. --noproxy: a cloud session proxy (HTTPS_PROXY) can refuse App API
# paths with 403; GitHub itself is reachable directly.
gh_api() { curl -fsS --noproxy '*' -H "Authorization: Bearer $1" -H "Accept: application/vnd.github+json" "$api$2" 2>/dev/null; }
installation_id() { # <role>
  local iv j id
  iv="AGENT_INSTALLATION_ID_$(role_var "$1")"
  [ -n "${!iv:-}" ] && { echo "${!iv}"; return 0; }
  [ -s "$state/installation" ] && { cat "$state/installation"; return 0; }
  j=$(app_jwt "$1") || return 1
  id=$(gh_api "$j" "/repos/$PLAN_REPO/installation" | jq -r '.id // empty' 2>/dev/null)
  [ -n "$id" ] || { why "no installation of the App on $PLAN_REPO (is the App installed there?)"; return 1; }
  printf '%s' "$id" >"$state/installation"; echo "$id"
}
token() {
  local role j inst t resp code
  role=$(cat "$state/persona" 2>/dev/null) || return 1
  if [ -f "$state/token" ] && [ $(($(date +%s) - $(cat "$state/minted" 2>/dev/null || echo 0))) -lt 3000 ]; then
    cat "$state/token"; return 0
  fi
  inst=$(installation_id "$role") || return 1
  j=$(app_jwt "$role") || return 1
  resp=$(curl -sS --noproxy '*' -w '\n%{http_code}' -X POST -H "Authorization: Bearer $j" -H "Accept: application/vnd.github+json" \
    "$api/app/installations/$inst/access_tokens" 2>/dev/null) || { why "cannot reach $api (curl exit $?)"; return 1; }
  code=${resp##*$'\n'}
  t=$(jq -r '.token // empty' <<<"${resp%$'\n'*}" 2>/dev/null)
  [ -n "$t" ] || { why "GitHub answered HTTP $code to the token request: $(jq -r '.message // "no message"' <<<"${resp%$'\n'*}" 2>/dev/null | head -c 120)"; return 1; }
  (umask 077 && printf '%s' "$t" >"$state/token" && date +%s >"$state/minted")
  printf '%s' "$t"
}
checkouts() { printf '%s\n' "$CREW_PLAN_DIR"; [ "$CREW_CODE_DIR" = "$CREW_PLAN_DIR" ] || printf '%s\n' "$CREW_CODE_DIR"; }
fail() { # <reason>: undo everything and fail: a run must never act as the owner by accident
  local d
  if [ -f "$state/git" ]; then # only undo git settings this script made
    while IFS= read -r d; do
      git -C "$d" config --local --unset-all credential.https://github.com.helper 2>/dev/null
      git -C "$d" config --local --unset remote.origin.pushurl 2>/dev/null
      git -C "$d" config --local --unset http.https://github.com/.proxy 2>/dev/null
      git -C "$d" config --local --unset user.name 2>/dev/null; git -C "$d" config --local --unset user.email 2>/dev/null
    done < <(checkouts)
  fi
  [ -f "$state/shim" ] && rm -f "$(cat "$state/shim")"
  rm -rf "$state"
  echo "FAIL identity: $1"
  exit 1
}
setup() {
  local role="$1" login app_name uid real dir shim="" j d repo roots=() dirs
  login=$(crew_role_login "$role"); [ -n "$login" ] || { echo "FAIL identity: unknown role '$role' (not in crew.json roles)"; exit 1; }
  app_name="${login%\[bot\]}"
  (umask 077 && mkdir -p "$state") && printf '%s' "$role" >"$state/persona"
  token >/dev/null || fail "$(cat "$state/why" 2>/dev/null || echo "no working key for $role")"
  # The bot's user id (for the noreply commit email) is public.
  uid=$(curl -fsS --noproxy '*' "$api/users/${app_name}%5Bbot%5D" 2>/dev/null | jq -r '.id // empty')
  [ -n "$uid" ] || fail "cannot look up the bot user id of ${login}"

  # gh: a shim earlier on PATH adds the app token, so every later `gh` call inside a checkout acts as the app.
  # Outside the checkouts the shim passes through, so on a shared machine (the owner's Mac) the owner's own gh is unchanged.
  real=$(command -v gh) || fail "gh not found"
  IFS=: read -ra dirs <<<"$PATH"
  for dir in "${dirs[@]}"; do
    [ "$dir" = "$(dirname "$real")" ] && break
    [ -d "$dir" ] && [ -w "$dir" ] && { shim="$dir/gh"; break; }
  done
  [ -n "$shim" ] || fail "no writable PATH directory before $real for the gh shim"
  while IFS= read -r d; do roots+=("$(cd "$d" && pwd -P)"); done < <(checkouts)
  shim_text "$real" "${roots[@]}" >"$shim"
  chmod +x "$shim"; printf '%s' "$shim" >"$state/shim"; hash -r
  j=$(cd "$CREW_PLAN_DIR" && gh api /installation/repositories -q '.repositories[].full_name' 2>/dev/null)
  for repo in "$PLAN_REPO" "$CODE_REPO"; do
    grep -qx "$repo" <<<"$j" || fail "the app token is not accepted for $repo through this network"
  done

  # git: commits and pushes as the app. Fetch keeps the remote the session came with.
  : >"$state/git"
  while IFS= read -r d; do
    repo=$PLAN_REPO; [ "$d" = "$CREW_PLAN_DIR" ] || repo=$CODE_REPO
    git -C "$d" config --local user.name "$login"
    git -C "$d" config --local user.email "$uid+$login@users.noreply.github.com"
    git -C "$d" config --local credential.https://github.com.helper ""
    git -C "$d" config --local --add credential.https://github.com.helper "!bash $self credential"
    git -C "$d" config --local remote.origin.pushurl "https://github.com/$repo.git"
    git -C "$d" config --local http.https://github.com/.proxy ""  # straight to GitHub with the app token, not the session proxy
    GIT_TERMINAL_PROMPT=0 git -C "$d" ls-remote --heads "https://github.com/$repo.git" >/dev/null 2>&1 ||
      fail "git cannot reach github.com with the app token ($repo)"
  done < <(checkouts)
  echo "OK identity: $login"
}
shim_text() { # <real gh> <checkout root>...
  local real="$1" pat="" r; shift
  for r in "$@"; do pat="${pat:+$pat|}$(printf '%q' "$r")/*"; done
  # shellcheck disable=SC2016  # the shim expands these at run time
  printf '#!/usr/bin/env bash\ncase "$(pwd -P)/" in %s) t=$(AGENT_ID_DIR=%q bash %q token 2>/dev/null) && export GH_TOKEN="$t" NO_PROXY="${NO_PROXY:+$NO_PROXY,}api.github.com,github.com" no_proxy="${no_proxy:+$no_proxy,}api.github.com,github.com" ;; esac\nexec %q "$@"\n' \
    "$pat" "$state" "$self" "$real"
}
selftest() {
  local d h p s role
  d=$(mktemp -d)
  # shellcheck disable=SC2064  # expand now: d is local and gone by the time the trap runs
  trap "rm -rf '$d'" EXIT
  role=$(jq -r '.roles | keys[0]' "$CREW_CONFIG"); [ -n "$role" ] && [ "$role" != null ] || { echo "selftest: crew.json has no roles"; exit 1; }
  openssl genrsa -out "$d/k.pem" 2048 2>/dev/null; openssl rsa -in "$d/k.pem" -pubout -out "$d/k.pub" 2>/dev/null
  IFS=. read -r h p s <<<"$(jwt 42 "$d/k.pem")"
  pad() { local x; x=$(tr '_-' '/+' <<<"$1"); while [ $((${#x} % 4)) -ne 0 ]; do x="$x="; done; printf '%s' "$x"; }
  [ "$(pad "$p" | openssl base64 -d -A | jq -r .iss)" = 42 ] || { echo "selftest: bad payload"; exit 1; }
  pad "$s" | openssl base64 -d -A >"$d/sig"
  printf '%s.%s' "$h" "$p" | openssl dgst -sha256 -verify "$d/k.pub" -signature "$d/sig" >/dev/null || { echo "selftest: bad signature"; exit 1; }
  [ "$(role_var worker-a)" = WORKER_A ] || { echo "selftest: role variable name"; exit 1; }
  [ "$(env -u AGENT_APP_KEY_ZZ_NONE bash "$self" keyvar zz-none)" = AGENT_APP_KEY_ZZ_NONE ] || { echo "selftest: default key variable"; exit 1; }
  crew_role_logins "$role" | grep -qxF "$(crew_role_login "$role")" || { echo "selftest: logins lack the App login"; exit 1; }
  state="$d/s"; mkdir "$state"; printf '%s' "$role" >"$state/persona"
  local rv; rv=$(role_var "$role")
  # a bad key is refused, with its cause recorded
  if (export "AGENT_APP_ID_$rv=1" "AGENT_APP_KEY_$rv=$(printf 'not a key' | openssl base64 -A)"; token >/dev/null 2>&1); then echo "selftest: token from a bad key"; exit 1; fi
  grep -q 'not the base64 of a private key' "$state/why" || { echo "selftest: bad-key cause not recorded"; exit 1; }
  # a missing App id is refused, with its cause recorded (the id lookup must not reach the real GitHub from a test)
  api="http://127.0.0.1:9"
  if (export "AGENT_APP_KEY_$rv=$(openssl base64 -A <"$d/k.pem")"; token >/dev/null 2>&1); then echo "selftest: token without an app id"; exit 1; fi
  grep -q "AGENT_APP_ID_$rv is not set" "$state/why" || { echo "selftest: missing-id cause not recorded"; exit 1; }
  # the shim adds the token only inside its checkouts
  printf '%s' tok >"$state/token"; date +%s >"$state/minted"
  # shellcheck disable=SC2016  # expands inside the fake gh
  printf '#!/usr/bin/env bash\necho "${GH_TOKEN:-none}"\n' >"$d/realgh"; chmod +x "$d/realgh"
  mkdir -p "$d/repo/sub" "$d/repo2" "$d/other"
  shim_text "$d/realgh" "$(cd "$d/repo" && pwd -P)" "$(cd "$d/repo2" && pwd -P)" >"$d/gh"; chmod +x "$d/gh"
  [ "$(cd "$d/repo/sub" && GH_TOKEN='' "$d/gh")" = tok ] || { echo "selftest: shim inside checkout"; exit 1; }
  [ "$(cd "$d/repo2" && GH_TOKEN='' "$d/gh")" = tok ] || { echo "selftest: shim inside second checkout"; exit 1; }
  [ "$(cd "$d/other" && GH_TOKEN='' "$d/gh")" = none ] || { echo "selftest: shim outside checkouts"; exit 1; }
  echo "agent-identity selftest: OK"
}

case "${1:-}" in
  setup) setup "${2:?usage: agent-identity.sh setup <role>}" ;;
  keyvar) keyvar "${2:?usage: agent-identity.sh keyvar <role>}" ;;
  logins) p=${2:-$(cat "$state/persona" 2>/dev/null)}; crew_role_logins "${p:?usage: agent-identity.sh logins <role>}" ;;  # later shells lose $AGENT_PERSONA
  token) token ;;
  credential) [ "${2:-}" = get ] && t=$(token) && printf 'username=x-access-token\npassword=%s\n' "$t" ;;
  selftest) selftest ;;
  *) echo "usage: agent-identity.sh setup <role> | keyvar <role> | logins [role] | token | credential get | selftest" >&2; exit 2 ;;
esac
