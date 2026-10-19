#!/usr/bin/env bash
# run_tests.sh — build and run the Reczipes2 unit tests on macOS, and compile them for
# the iOS Simulator, writing compiler errors and test results to _testlogs/ (gitignored)
# so a session that cannot run Xcode can read them.
#   bash ~/Developer/GitHub/reczipes/scripts/run_tests.sh          # macOS run + iOS compile
#   bash ~/Developer/GitHub/reczipes/scripts/run_tests.sh mac      # macOS only
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=_testlogs; mkdir -p "$OUT"; rm -f "$OUT"/*.log "$OUT"/*.txt
SUM="$OUT/summary.txt"; : > "$SUM"
PROJ=Reczipes2.xcodeproj; SCHEME=Reczipes2Tests
run() { # name, then xcodebuild args
  local name=$1; shift
  echo "== $name" | tee -a "$SUM"
  xcodebuild -project "$PROJ" -scheme "$SCHEME" -allowProvisioningUpdates "$@" > "$OUT/$name.log" 2>&1
  local rc=$?
  grep -E ': (error|fatal error):' "$OUT/$name.log" | sed "s#$PWD/##" | sort -u > "$OUT/$name.errors.txt"
  grep -E "✘|Test .* failed|Test case .* failed|recorded an issue|\*\* TEST|\*\* BUILD|Executed [0-9]+ test|Test run with [0-9]+ test" "$OUT/$name.log" | sed "s#$PWD/##" | tail -60 > "$OUT/$name.results.txt"
  echo "   exit $rc · $(wc -l < "$OUT/$name.errors.txt" | tr -d ' ') compile errors" | tee -a "$SUM"
  tail -3 "$OUT/$name.results.txt" | sed 's/^/   /' | tee -a "$SUM"
  return $rc
}
run mac-test -destination 'platform=macOS' -only-testing:Reczipes2Tests test
if [ "${1:-}" != "mac" ]; then
  run ios-build -destination 'generic/platform=iOS Simulator' build-for-testing
fi
echo; echo "Logs: $PWD/$OUT  (tell Claude: \"tests ran\")"
