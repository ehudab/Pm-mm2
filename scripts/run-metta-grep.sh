#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_MORK_BIN="$ROOT_DIR/../MORK/target/release/mork"

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
  echo "Usage: scripts/run-metta-grep.sh <case-file> [output-file]" >&2
  exit 2
fi

case_file="$1"
out_file="${2:-}"

if [[ "$case_file" != /* ]]; then
  case_file="$ROOT_DIR/$case_file"
fi

if [[ ! -f "$case_file" ]]; then
  echo "ERROR: missing file: $case_file" >&2
  exit 1
fi

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

read_test_value() {
  local key="$1"
  local line
  line="$(grep -m 1 "^;; ${key} " "$case_file" || true)"
  printf '%s' "${line#;; ${key} }"
}

# --- EXPECTED-PATTERN extraction ---------------------------------------
pattern_name=""
pattern_expr=""
functor=""
pattern_line="$(grep -m 1 '^(EXPECTED-PATTERN ' "$case_file" || true)"
if [[ -n "$pattern_line" ]]; then
  body="${pattern_line#(EXPECTED-PATTERN }"
  body="${body%)}"
  read -r pattern_name pattern_expr <<< "$body"
  if [[ -z "$pattern_expr" ]]; then
    echo "ERROR: could not parse EXPECTED-PATTERN line: $pattern_line" >&2
    exit 1
  fi
  functor="$(printf '%s' "$pattern_expr" | sed -E 's/^\(([^ )]+).*/\1/')"
  echo "Filtering enabled (grep): '$pattern_name' -> $pattern_expr (functor: $functor)" >&2
fi

aux_args=()
while IFS= read -r aux_path || [[ -n "$aux_path" ]]; do
  [[ -z "$aux_path" ]] && continue
  if [[ "$aux_path" != /* ]]; then
    aux_path="$ROOT_DIR/$aux_path"
  fi
  aux_args+=("--aux-path" "$aux_path")
done < <(sed -n 's/^;; TEST-AUX[[:space:]]\{1,\}//p' "$case_file")

steps="$(read_test_value TEST-STEPS)"
steps="${steps:-100000}"

# --- No pattern: identical to the original script -----------------------
if [[ -z "$pattern_expr" ]]; then
  if [[ -n "$out_file" ]]; then
    "$MORK_BIN" run "$case_file" "$out_file" "${aux_args[@]}" --instrumentation 0
  else
    "$MORK_BIN" run "$case_file" "${aux_args[@]}" --instrumentation 0
  fi
  exit 0
fi

# --- Pattern present: run mork, then grep-filter the dumped output ------
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

work_case_file="$tmp_dir/case_without_pattern.mm2"
grep -v '^(EXPECTED-PATTERN ' "$case_file" > "$work_case_file"

raw_out="$tmp_dir/raw_output.mm2"
"$MORK_BIN" run "$work_case_file" "$raw_out" "${aux_args[@]}" --instrumentation 0

# Anchored to the START of the line, so a fact like
#   (iterative-candidate-pattern $a $b $d $e)
# matches, but that same subexpression nested inside
#   (DEF iterative-miner-continue-fn (, (iter-parent ...) (iterative-candidate-pattern ...) ...
# does not, since the line begins with "(DEF ", not "(iterative-candidate-pattern ".
if [[ -n "$out_file" ]]; then
  grep -E "^\($functor " "$raw_out" > "$out_file" || true
else
  grep -E "^\($functor " "$raw_out" || true
fi