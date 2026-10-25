#!/usr/bin/env bash
# Proves Tools/lint.sh catches what it claims to catch.
# Usage: Tools/lint-selftest.sh
# Copies the repo (tracked + untracked-not-ignored files) to a temp dir, runs lint on
# a clean copy, then injects one violation per check into fresh copies.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/eagar-selftest.XXXXXX")"
trap 'rm -rf "$TMPROOT"' EXIT

# Secret-shaped strings are assembled at run time so this file itself stays clean.
SK="sk-ant-""api03-AAAAAAAAAAAAAAAA"
PK="-----BEGIN ""RSA PRIVATE KEY-----"

LIST="$TMPROOT/list"
if [ -e "$ROOT/.git" ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git ls-files -co --exclude-standard | sort -u | while IFS= read -r f; do
    if [ -f "$f" ]; then printf '%s\n' "$f"; fi
  done > "$LIST"
else
  find . -type f -not -path './.git/*' -not -path '*/.build/*' -not -path '*/node_modules/*' | sed 's|^\./||' > "$LIST"
fi

N=0
fresh_copy() {
  N=$((N + 1))
  CP="$TMPROOT/copy$N"
  mkdir -p "$CP"
  tar -cf - -T "$LIST" | tar -xf - -C "$CP"
}

# Make sure the copy has the minimal pieces some injections build on.
write_file() { # path content
  mkdir -p "$CP/$(dirname "$1")"
  printf '%s\n' "$2" > "$CP/$1"
}

FAILS=0
DETECTED=0
TOTAL=0

expect_detect() { # name, regex-for-output-line
  local name="$1" needle="$2" out rc=0
  TOTAL=$((TOTAL + 1))
  out="$(bash "$CP/Tools/lint.sh" "$CP" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -qE "$needle"; then
    DETECTED=$((DETECTED + 1))
    echo "ok    detected: $name"
  else
    FAILS=$((FAILS + 1))
    echo "FAIL  not detected: $name (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/        /'
  fi
}

# 0. Clean baseline.
fresh_copy
rc=0
base_out="$(bash "$CP/Tools/lint.sh" "$CP" 2>&1)" || rc=$?
if [ "$rc" -eq 0 ]; then
  echo "ok    clean baseline passes"
else
  FAILS=$((FAILS + 1))
  echo "FAIL  clean baseline does not pass (exit $rc); the repo itself has violations:"
  printf '%s\n' "$base_out" | sed 's/^/        /'
fi

CORE="Packages/EagarCore/Sources/EagarCore"

# 0b. Negatives that must not be flagged.
fresh_copy
write_file "Packages/EagarCore/Tests/EagarCoreTests/LintNeg.swift" 'func t() { print("fine in tests") }'
write_file "$CORE/LintNeg.swift" '// print("in a comment")
func blueprint(_ x: Int) {}
func use() { blueprint(1) }
// SAFETY: guarded by a lock
final class Neg: @unchecked Sendable {}'
rc=0
neg_out="$(bash "$CP/Tools/lint.sh" "$CP" 2>&1)" || rc=$?
if printf '%s\n' "$neg_out" | grep -q 'LintNeg.swift'; then
  FAILS=$((FAILS + 1))
  echo "FAIL  false positive on allowed code"
  printf '%s\n' "$neg_out" | grep 'LintNeg.swift' | sed 's/^/        /'
else
  echo "ok    allowed code not flagged"
fi

# 1. no-print.
fresh_copy
write_file "$CORE/LintInject.swift" 'func f() { print("x") }'
expect_detect "no-print" 'LintInject\.swift:1: \[no-print\]'

# 2. secrets.
fresh_copy
write_file "$CORE/LintInject.swift" "let k = \"$SK\""
expect_detect "secrets: sk-ant- literal" 'LintInject\.swift:1: \[secrets\]'

fresh_copy
write_file "docs/LintInject.md" "$PK"
expect_detect "secrets: private key in markdown" 'LintInject\.md:1: \[secrets\]'

fresh_copy
write_file ".env" "A=b"
expect_detect "secrets: .env file" '\.env:1: \[secrets\]'

fresh_copy
write_file "Config/AuthKey_ABC.p8" "x"
expect_detect "secrets: .p8 file" 'AuthKey_ABC\.p8:1: \[secrets\]'

# 3. ai-boundary.
fresh_copy
write_file "$CORE/LintInject.swift" 'import FoundationModels'
expect_detect "ai-boundary: FoundationModels" 'LintInject\.swift:1: \[ai-boundary\]'

fresh_copy
write_file "$CORE/LintInject.swift" 'let h = "https://api.anthropic.com/v1/messages"'
expect_detect "ai-boundary: model host" 'LintInject\.swift:1: \[ai-boundary\]'

# 4. deps.
fresh_copy
write_file "Packages/LintDep/Package.swift" 'import PackageDescription
let package = Package(name: "X", dependencies: [
  .package(url: "https://github.com/x/y", from: "1.0.0"),
])'
expect_detect "deps: from: and off allow-list" 'LintDep/Package\.swift:3: \[deps\]'

fresh_copy
write_file "Packages/LintDep/Package.swift" 'import PackageDescription
let package = Package(name: "X", dependencies: [
  .package(url: "https://github.com/MailCore/mailcore2.git", from: "1.0.0"),
])'
expect_detect "deps: allow-listed but not exact" 'LintDep/Package\.swift:3: \[deps\] remote package must be pinned'

fresh_copy
write_file "Packages/LintDep/Package.swift" 'import PackageDescription
let package = Package(name: "X", dependencies: [
  .package(url: "https://github.com/MailCore/mailcore2.git", exact: "1.0.0"),
])'
expect_detect "deps: exact but no Package.resolved" 'LintDep/Package\.swift:1: \[deps\] remote packages require'

fresh_copy
write_file "App/project.yml" 'name: Eagar
packages:
  Foo:
    url: https://github.com/x/y
    from: 1.0.0'
expect_detect "deps: project.yml unpinned" 'App/project\.yml:3: \[deps\]'

# 5. unsafe-concurrency.
fresh_copy
write_file "$CORE/LintInject.swift" 'final class X: @unchecked Sendable {}'
expect_detect "unsafe-concurrency" 'LintInject\.swift:1: \[unsafe-concurrency\]'

# 6. string-catalog.
fresh_copy
write_file "App/Eagar/LintInject.swift" 'import SwiftUI
struct V: View { var body: some View { Text("Hello, " + name) } }'
expect_detect "string-catalog: concatenation" 'LintInject\.swift:2: \[string-catalog\]'

fresh_copy
write_file "App/Eagar/Localizable.xcstrings" '{"sourceLanguage":"en","strings":{"a":{"localizations":{"ga":{}}}},"version":"1.0"}'
expect_detect "string-catalog: wrong source language" 'Localizable\.xcstrings:1: \[string-catalog\]'

fresh_copy
write_file "App/Eagar/Localizable.xcstrings" '{"sourceLanguage":"en-GB","strings":{"a":{}},"version":"1.0"}'
expect_detect "string-catalog: no ga localization" 'Localizable\.xcstrings:1: \[string-catalog\].*ga'

fresh_copy
write_file "App/Eagar/Localizable.xcstrings" '{not json'
expect_detect "string-catalog: invalid JSON" 'Localizable\.xcstrings:1: \[string-catalog\].*JSON'

# 7. derivation-tests.
fresh_copy
if [ -f "$CP/$CORE/Taint.swift" ]; then
  awk '{ print } /enum[ \t]+DerivationID/ { print "    case zzLintInjected" }' "$CP/$CORE/Taint.swift" > "$CP/$CORE/Taint.swift.new"
  mv "$CP/$CORE/Taint.swift.new" "$CP/$CORE/Taint.swift"
else
  write_file "$CORE/Taint.swift" 'public enum DerivationID: String {
    case zzLintInjected
}'
fi
expect_detect "derivation-tests" 'Taint\.swift:[0-9]+: \[derivation-tests\] DerivationID\.zzLintInjected'

# 8. log-content.
fresh_copy
write_file "$CORE/LintInject.swift" 'import os
let l = Logger(subsystem: "x", category: "y")'
expect_detect "log-content" 'LintInject\.swift:2: \[log-content\]'

echo "selftest: $DETECTED/$TOTAL injected violations detected"
if [ "$FAILS" -ne 0 ]; then
  echo "selftest: $FAILS failure(s)" >&2
  exit 1
fi
echo "selftest: ok"
