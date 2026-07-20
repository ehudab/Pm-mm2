#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="${TEST_ROOT:-$ROOT_DIR/tests}"
OUT_DIR="${OUT_DIR:-/tmp/hyperon-miner-mm2-tests}"
DEFAULT_MORK_BIN="/Users/tewodrosnibret/Documents/icog/MORK/target/release/mork"

if [[ -z "${MORK_BIN:-}" ]]; then
  if command -v mork >/dev/null 2>&1; then
    MORK_BIN="$(command -v mork)"
  else
    MORK_BIN="$DEFAULT_MORK_BIN"
  fi
fi

if [[ ! -x "$MORK_BIN" ]]; then
  echo "ERROR: mork binary not executable: $MORK_BIN" >&2
  echo "Set MORK_BIN=/path/to/mork and retry." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

total=0
failures=0

read_case_value() {
  local case_file="$1"
  local key="$2"
  local line
  line="$(grep -m 1 "^${key}=" "$case_file" || true)"
  printf '%s' "${line#${key}=}"
}

run_case() {
  local case_file="$1"
  local expected_file="${case_file%.test}.expected"
  local rel_case="${case_file#$TEST_ROOT/}"
  local out_file="$OUT_DIR/${rel_case%.test}.out.metta"
  local input_path
  local steps

  total=$((total + 1))

  if [[ ! -f "$expected_file" ]]; then
    echo "FAIL $rel_case"
    echo "  missing expected file: ${expected_file#$ROOT_DIR/}"
    failures=$((failures + 1))
    return
  fi

  input_path="$(read_case_value "$case_file" input)"
  steps="$(read_case_value "$case_file" steps)"
  steps="${steps:-100000}"

  if [[ -z "$input_path" ]]; then
    echo "FAIL $rel_case"
    echo "  missing input=... in test case"
    failures=$((failures + 1))
    return
  fi

  if [[ "$input_path" != /* ]]; then
    input_path="$ROOT_DIR/$input_path"
  fi

  mkdir -p "$(dirname "$out_file")"

  echo "RUN  $rel_case"
  if ! "$MORK_BIN" run "$input_path" "$out_file" --steps "$steps" --instrumentation 0 >/dev/null; then
    echo "FAIL $rel_case"
    echo "  mork run failed"
    failures=$((failures + 1))
    return
  fi

  while IFS= read -r expected || [[ -n "$expected" ]]; do
    [[ -z "$expected" ]] && continue
    [[ "$expected" == \#* ]] && continue

    if ! grep -F -- "$expected" "$out_file" >/dev/null; then
      echo "FAIL $rel_case"
      echo "  missing expected fact:"
      echo "  $expected"
      echo "  output: $out_file"
      failures=$((failures + 1))
      return
    fi
  done < "$expected_file"

  echo "PASS $rel_case"
}

while IFS= read -r case_file; do
  run_case "$case_file"
done < <(find "$TEST_ROOT" -name "*.test" | sort)

echo
echo "Total: $total"
echo "Failed: $failures"

if [[ "$failures" -ne 0 ]]; then
  exit 1
fi
