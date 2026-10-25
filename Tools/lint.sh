#!/usr/bin/env bash
# Eagar lint: enforces CLAUDE.md invariants 2, 6, 7 and the dependency allow-list.
# Usage: Tools/lint.sh [repo-root]
# Output: one violation per line as `path:line: [check] message`; exit 1 if any.
# Compatible with bash 3.2 and BSD userland (macOS default).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/eagar-lint.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
ALL="$WORK/all"            # every candidate file
SWIFT="$WORK/swift"        # all swift files
SWIFT_NT="$WORK/swift-nt"  # non-test swift files
OUT="$WORK/out"

# File discovery: tracked + untracked-but-not-ignored when in git, else find.
if [ -e "$ROOT/.git" ] && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$ROOT" ls-files -co --exclude-standard | sort -u | while IFS= read -r f; do
    if [ -f "$f" ]; then printf '%s\n' "$f"; fi
  done > "$ALL"
else
  find . -type f \
    -not -path './.git/*' -not -path '*/.build/*' -not -path '*/node_modules/*' \
    -not -path '*/DerivedData/*' -not -path '*/.swiftpm/*' \
    | sed 's|^\./||' | sort > "$ALL"
fi

is_test_path() {
  case "$1" in
    Tests/*|*/Tests/*|*Tests/*|*UITests/*|Packages/EagarTestSupport/*) return 0 ;;
    *) return 1 ;;
  esac
}

: > "$SWIFT"; : > "$SWIFT_NT"
while IFS= read -r f; do
  case "$f" in
    *.swift)
      printf '%s\n' "$f" >> "$SWIFT"
      if ! is_test_path "$f"; then printf '%s\n' "$f" >> "$SWIFT_NT"; fi
      ;;
  esac
done < "$ALL"

# Shared awk prelude: strips a trailing // comment (not the // in a URL scheme).
AWK_STRIP='function strip(s) { if (match(s, /(^|[^:])\/\//)) s = substr(s, 1, RSTART + RLENGTH - 3); return s }'

# a, e, h, f(concat): per-line checks on non-test Swift.
check_swift_nontest() {
  local f
  while IFS= read -r f; do
    awk -v f="$f" "$AWK_STRIP"'
      function out(check, msg) { printf "%s:%d: [%s] %s\n", f, NR, check, msg }
      {
        line = $0; code = strip(line)
        if (code ~ /(^|[^A-Za-z0-9_.])(print|debugPrint|NSLog|dump)\(/)
          out("no-print", "print/debugPrint/NSLog/dump is forbidden outside tests; use EagarLog")
        if (code ~ /@unchecked[ \t]+Sendable|nonisolated\(unsafe\)/) {
          if (line !~ /SAFETY:/ && prev !~ /SAFETY:/)
            out("unsafe-concurrency", "@unchecked Sendable / nonisolated(unsafe) needs a SAFETY: comment on this or the previous line")
        }
        if (f !~ /Packages\/EagarCore\/Sources\/EagarCore\/EagarLog\.swift$/ && code ~ /(^|[^A-Za-z0-9_.])(Logger|os_log)\(/)
          out("log-content", "Logger/os_log outside EagarLog.swift; all logging goes through EagarLog")
        if (code ~ /(Text|Button|Label)\("[^"]*"[ \t]*\+/)
          out("string-catalog", "concatenated user-facing string; use a String Catalog key with interpolation")
        prev = line
      }' "$f"
  done < "$SWIFT_NT"
}

# c: AI boundary on all Swift.
check_ai_boundary() {
  local f
  while IFS= read -r f; do
    awk -v f="$f" "$AWK_STRIP"'
      function out(check, msg) { printf "%s:%d: [%s] %s\n", f, NR, check, msg }
      {
        code = strip($0)
        if (code ~ /import[ \t]+FoundationModels/ && f !~ /^Packages\/EagarAI\/Sources\//)
          out("ai-boundary", "import FoundationModels is allowed only under Packages/EagarAI/Sources/")
        if (f !~ /^Packages\/EagarAI\// && tolower(code) ~ /api\.anthropic\.com|:11434|ollama/)
          out("ai-boundary", "model host reference outside Packages/EagarAI/; all model calls go through AIRouter")
      }' "$f"
  done < "$SWIFT"
}

# b: secrets.
check_secrets() {
  local f base n name pat i
  local names=("anthropic-key" "private-key" "google-api-key" "google-oauth-token" "github-token" "slack-token")
  local pats=('sk-ant-[A-Za-z0-9_-]{10,}' '-----BEGIN [A-Z ]*PRIVATE KEY-----' 'AIza[0-9A-Za-z_-]{35}' 'ya29\.[0-9A-Za-z_-]{20,}' 'ghp_[A-Za-z0-9]{36}' 'xox[abprs]-[A-Za-z0-9-]{10,}')
  while IFS= read -r f; do
    base="${f##*/}"
    case "$base" in
      *.p8|*.p12|.env*|GoogleService-Info.plist)
        printf '%s:1: [secrets] forbidden secret-bearing file name\n' "$f" ;;
    esac
    i=0
    while [ "$i" -lt "${#pats[@]}" ]; do
      name="${names[$i]}"; pat="${pats[$i]}"
      i=$((i + 1))
      case "$f" in
        *.md) if [ "$name" != "private-key" ]; then continue; fi ;;
      esac
      grep -InE -e "$pat" "$f" 2>/dev/null | cut -d: -f1 | while IFS= read -r n; do
        printf '%s:%s: [secrets] matches %s pattern\n' "$f" "$n" "$name"
      done || true
    done
  done < "$ALL"
}

# d: dependency pinning and allow-list.
ALLOW="github.com/google/googlesignin-ios github.com/openid/appauth-ios github.com/azuread/microsoft-authentication-library-for-objc github.com/mailcore/mailcore2"

check_deps() {
  local f dir resolved rc
  while IFS= read -r f; do
    case "${f##*/}" in
      Package.swift)
        rc=0
        awk -v f="$f" -v allow="$ALLOW" "$AWK_STRIP"'
          function out(ln, msg) { printf "%s:%d: [deps] %s\n", f, ln, msg }
          function judge(buf, ln,   url, u, n, i, a, ok) {
            if (!match(buf, /"[^"]*"/)) { out(ln, "cannot read package URL"); return }
            url = substr(buf, RSTART + 1, RLENGTH - 2)
            if (buf !~ /exact:/ || buf ~ /(from|branch|revision):/ || buf ~ /upToNext|\.\.\.|\.\.</)
              out(ln, "remote package must be pinned with exact: (" url ")")
            u = tolower(url); sub(/^https?:\/\//, "", u); sub(/\/$/, "", u); sub(/\.git$/, "", u)
            n = split(allow, a, " "); ok = 0
            for (i = 1; i <= n; i++) if (a[i] == u) ok = 1
            if (!ok) out(ln, "package not on the allow-list: " url)
            remote = 1
          }
          {
            code = strip($0)
            if (!inpkg && code ~ /\.package\([ \t]*url:/) { inpkg = 1; buf = ""; depth = 0; start = NR }
            if (inpkg) {
              buf = buf " " code
              t = code; depth += gsub(/\(/, "(", t)
              t = code; depth -= gsub(/\)/, ")", t)
              if (depth <= 0) { judge(buf, start); inpkg = 0 }
            }
          }
          END { if (remote) exit 3 }' "$f" || rc=$?
        if [ "$rc" -eq 3 ]; then
          dir="$(dirname "$f")"
          if [ "$dir" = "." ]; then resolved="Package.resolved"; else resolved="$dir/Package.resolved"; fi
          if ! grep -qxF "$resolved" "$ALL"; then
            printf '%s:1: [deps] remote packages require a committed Package.resolved next to Package.swift\n' "$f"
          fi
        fi
        ;;
      project.yml)
        rc=0
        awk -v f="$f" -v allow="$ALLOW" '
          function out(ln, msg) { printf "%s:%d: [deps] %s\n", f, ln, msg }
          function flush(   u, n, i, a, ok) {
            if (url == "") return
            if (!exact || bad) out(eline, "package " name " must be pinned with exactVersion:/version: (no from/branch/revision/range)")
            u = tolower(url); sub(/^https?:\/\//, "", u); sub(/\/$/, "", u); sub(/\.git$/, "", u)
            n = split(allow, a, " "); ok = 0
            for (i = 1; i <= n; i++) if (a[i] == u) ok = 1
            if (!ok) out(eline, "package " name " not on the allow-list: " url)
            remote = 1
          }
          /^[A-Za-z]/ { flush(); url = ""; insec = ($0 ~ /^packages:/); next }
          insec && /^  [A-Za-z0-9_.-]+:/ { flush(); url = ""; exact = 0; bad = 0; name = $1; sub(/:$/, "", name); eline = NR; next }
          insec && /^[ \t]+url:/ { url = $2; gsub(/["\047]/, "", url); next }
          insec && /^[ \t]+(exactVersion|version):/ { exact = 1; next }
          insec && /^[ \t]+(from|branch|revision|minorVersion|majorVersion|minVersion|maxVersion):/ { bad = 1; next }
          END { flush(); if (remote) exit 3 }' "$f" || rc=$?
        if [ "$rc" -eq 3 ]; then
          if ! grep -q '/Package\.resolved$' "$ALL"; then
            printf '%s:1: [deps] remote packages require a committed Package.resolved\n' "$f"
          fi
        fi
        ;;
    esac
  done < "$ALL"
}

# f: string catalog.
check_catalog() {
  [ -d App/Eagar ] || return 0
  local cat
  cat="$(grep -E '^App/Eagar/(.*/)?Localizable\.xcstrings$' "$ALL" | head -1 || true)"
  if [ -z "$cat" ]; then
    printf 'App/Eagar:1: [string-catalog] missing Localizable.xcstrings\n'
    return 0
  fi
  python3 - "$cat" <<'PY'
import json, sys
p = sys.argv[1]
try:
    d = json.load(open(p, encoding="utf-8"))
except Exception as e:
    print("%s:1: [string-catalog] not valid JSON (%s)" % (p, type(e).__name__)); sys.exit(0)
if d.get("sourceLanguage") != "en-GB":
    print('%s:1: [string-catalog] sourceLanguage must be "en-GB"' % p)
has_ga = any("ga" in (v.get("localizations") or {}) for v in (d.get("strings") or {}).values() if isinstance(v, dict))
if not has_ga:
    print("%s:1: [string-catalog] needs at least one string with a ga (Irish) localization (NFR-L10N-02)" % p)
PY
}

# g: every DerivationID case has a Derivation_<case> test.
check_derivations() {
  local taint="Packages/EagarCore/Sources/EagarCore/Taint.swift" tests="$WORK/test-swift" f
  if [ ! -f "$taint" ]; then
    if [ -d Packages/EagarCore ]; then
      printf '%s:1: [derivation-tests] Taint.swift missing; DerivationID cannot be checked\n' "$taint"
    fi
    return 0
  fi
  : > "$tests"
  while IFS= read -r f; do
    if is_test_path "$f"; then printf '%s\n' "$f" >> "$tests"; fi
  done < "$SWIFT"
  awk '
    /enum[ \t]+DerivationID/ { inenum = 1; next }
    inenum && /^}/ { inenum = 0 }
    inenum && /^[ \t]*case[ \t]+[A-Za-z0-9_]+/ {
      s = $0; sub(/^[ \t]*case[ \t]+/, "", s); sub(/[^A-Za-z0-9_].*$/, "", s)
      printf "%d %s\n", NR, s
    }' "$taint" | while read -r ln c; do
      found=0
      while IFS= read -r t; do
        if grep -qE "Derivation_${c}([^A-Za-z0-9_]|\$)" "$t"; then found=1; break; fi
      done < "$tests"
      if [ "$found" -eq 0 ]; then
        printf '%s:%s: [derivation-tests] DerivationID.%s has no test containing Derivation_%s (FR-CORE-03)\n' "$taint" "$ln" "$c" "$c"
      fi
    done
}

run_all() {
  check_swift_nontest
  check_ai_boundary
  check_secrets
  check_deps
  check_catalog
  check_derivations
}

run_all | tee "$OUT"
if [ -s "$OUT" ]; then
  echo "lint: $(wc -l < "$OUT" | tr -d ' ') violation(s)" >&2
  exit 1
fi
echo "lint: clean"
