#!/usr/bin/env bash
#
# paseo-mermaid-wrap-patch.sh
#
# Stopgap for mermaid-js/mermaid#7794: long Mermaid flowchart labels clip
# instead of wrapping on fractional device-pixel-ratio displays.
#
# Patches the installed Paseo.app's bundled web UI with the one-line upstream
# tolerance (bbox.width === width  ->  bbox.width >= width - 1).
#
# The match is variable-name agnostic, so it survives Paseo/mermaid rebuilds
# as long as the upstream expression is unchanged.
#
# TEMPORARY: the Paseo updater replaces the whole app, so re-run `patch` after
# every update. `restore` puts the original file back.
#
# Usage:
#   ./paseo-mermaid-wrap-patch.sh status
#   ./paseo-mermaid-wrap-patch.sh patch
#   ./paseo-mermaid-wrap-patch.sh restore
#
# Env:
#   PASEO_APP   path to the app (default: /Applications/Paseo.app)
#
set -euo pipefail

APP="${PASEO_APP:-/Applications/Paseo.app}"
WEB_DIR="$APP/Contents/Resources/app-dist/_expo/static/js/web"
SUFFIX=".orig-mergewrap"

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: need '$1' on PATH" >&2; exit 1; }; }
need python3

find_bundle() {
  [ -d "$WEB_DIR" ] || { echo "error: not found: $WEB_DIR" >&2; exit 1; }
  local f=""
  while IFS= read -r line; do f="$line"; break; done < <(
    find "$WEB_DIR" -maxdepth 1 -name 'index-*.js' ! -name "*${SUFFIX}" 2>/dev/null || true
  )
  [ -n "$f" ] || { echo "error: no index-*.js under $WEB_DIR" >&2; exit 1; }
  printf '%s' "$f"
}

# Counts occurrences of the buggy (===) and fixed (>= - 1) expressions.
counts() {
  python3 - "$1" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
eq = len(re.findall(r"getBoundingClientRect\(\);return [A-Za-z_$][\w$]*\.width===([A-Za-z_$][\w$]*)&&", s))
ge = len(re.findall(r"getBoundingClientRect\(\);return [A-Za-z_$][\w$]*\.width>=[A-Za-z_$][\w$]*-1&&", s))
print(eq, ge)
PY
}

apply_patch() {
  python3 - "$1" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
pat = re.compile(r"getBoundingClientRect\(\);return ([A-Za-z_$][\w$]*)\.width===([A-Za-z_$][\w$]*)&&")
assert len(pat.findall(s)) == 1, len(pat.findall(s))
out = pat.sub(lambda m: f"getBoundingClientRect();return {m.group(1)}.width>={m.group(2)}-1&&", s)
open(p, "w", encoding="utf-8").write(out)
PY
}

BUNDLE="$(find_bundle)"
BACKUP="$BUNDLE$SUFFIX"

case "${1:-status}" in
  status)
    read -r eq ge <<<"$(counts "$BUNDLE")"
    echo "app:    $APP"
    echo "bundle: $BUNDLE"
    echo "unpatched marker (===): $eq"
    echo "patched marker   (>=): $ge"
    if [ "$ge" -ge 1 ] && [ "$eq" -eq 0 ]; then echo "state:  PATCHED"
    elif [ "$eq" -ge 1 ]; then echo "state:  NOT PATCHED"
    else echo "state:  UNKNOWN (expected expression not found)"; fi
    if [ -f "$BACKUP" ]; then echo "backup: $BACKUP"; fi
    ;;
  patch)
    read -r eq ge <<<"$(counts "$BUNDLE")"
    if [ "$ge" -ge 1 ] && [ "$eq" -eq 0 ]; then
      echo "already patched, nothing to do."; exit 0
    fi
    if [ "$eq" -ne 1 ]; then
      echo "error: expected exactly 1 unpatched expression, found $eq. Aborting." >&2
      exit 1
    fi
    [ -f "$BACKUP" ] || cp -p "$BUNDLE" "$BACKUP"
    apply_patch "$BUNDLE"
    echo "patched: $BUNDLE"
    echo "backup:  $BACKUP"
    # A pre-compressed sibling would be served instead of the patched file.
    siblings=""
    for cand in "$BUNDLE".br "$BUNDLE".gz; do
      [ -f "$cand" ] && siblings="$siblings $cand"
    done
    if [ -n "$siblings" ]; then
      echo "WARNING: compressed siblings found; remove them so the patched bundle is served:"
      for s in $siblings; do echo "  $s"; done
    fi
    echo
    echo "Next: fully quit Paseo (Cmd+Q) and reopen it."
    echo "If macOS reports the app is damaged, restore with: $0 restore"
    ;;
  restore)
    [ -f "$BACKUP" ] || { echo "error: no backup at $BACKUP" >&2; exit 1; }
    cp -p "$BACKUP" "$BUNDLE"
    echo "restored: $BUNDLE"
    ;;
  *)
    echo "usage: $0 {status|patch|restore}" >&2; exit 2;;
esac
