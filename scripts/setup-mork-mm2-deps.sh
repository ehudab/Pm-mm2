#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 3 ]]; then
  echo "Usage: $0 /path/to/MORK /path/to/MM2-Helper /path/to/mm2-stdlib" >&2
  exit 1
fi

MORK_DIR="$(cd "$1" && pwd)"
HELPER_DIR="$(cd "$2" && pwd)"
STDLIB_DIR="$(cd "$3" && pwd)"

LIB_RS="$MORK_DIR/kernel/src/lib.rs"
SINKS_RS="$MORK_DIR/kernel/src/sinks.rs"
KERNEL_CARGO="$MORK_DIR/kernel/Cargo.toml"
WORKSPACE_CARGO="$MORK_DIR/Cargo.toml"
MACROS_RS="$MORK_DIR/expr/src/macros.rs"
HELPER_EXT_SRC="$HELPER_DIR/helper_ext.rs"
HELPER_EXT_DST="$MORK_DIR/kernel/src/helper_ext.rs"

for file in "$LIB_RS" "$SINKS_RS" "$KERNEL_CARGO" "$WORKSPACE_CARGO" "$MACROS_RS" "$HELPER_EXT_SRC"; do
  if [[ ! -f "$file" ]]; then
    echo "ERROR: expected file missing: $file" >&2
    exit 1
  fi
done

cp "$HELPER_EXT_SRC" "$HELPER_EXT_DST"

perl -0pi -e 's/^mod helper_ext;\n//mg' "$LIB_RS"
perl -0pi -e 's/mod pure;\n/mod pure;\nmod helper_ext;\n/' "$LIB_RS"

perl -0pi -e 's/^use crate::helper_ext;\n//mg; s/^use mm2_stdlib;\n//mg' "$SINKS_RS"
if grep -q 'use crate::{expr, pure};' "$SINKS_RS"; then
  perl -0pi -e 's/use crate::\{expr, pure\};/use crate::{expr, pure};\nuse crate::helper_ext;\nuse mm2_stdlib;/' "$SINKS_RS"
else
  echo "ERROR: could not find import anchor in $SINKS_RS" >&2
  exit 1
fi

perl -0pi -e 's/^\s*helper_ext::register\(&mut scope\);\n//mg; s/^\s*mm2_stdlib::register\(&mut scope\);\n//mg' "$SINKS_RS"
if grep -q 'pure::register(&mut scope);' "$SINKS_RS"; then
  perl -0pi -e 's/pure::register\(&mut scope\);\n?/pure::register\(\&mut scope\);\n        helper_ext::register\(\&mut scope\);\n        mm2_stdlib::register\(\&mut scope\);\n/' "$SINKS_RS"
else
  echo "ERROR: could not find pure::register(&mut scope); in $SINKS_RS" >&2
  exit 1
fi

stdlib_path="$(printf '%s' "$STDLIB_DIR" | sed 's/[\/&]/\\&/g')"
perl -0pi -e 's/^mm2-stdlib\s*=.*\n//mg' "$KERNEL_CARGO"
perl -0pi -e "s/pathmap = \\{ workspace = true, features = \\[\"nightly\"\\] \\}\\n/\\0mm2-stdlib = { path = \"$stdlib_path\" }\\n/" "$KERNEL_CARGO"

if ! grep -q '^\[patch\."https://github.com/trueagi-io/MORK"\]' "$WORKSPACE_CARGO"; then
  cat >> "$WORKSPACE_CARGO" <<'PATCH'

[patch."https://github.com/trueagi-io/MORK"]
eval = { path = "experiments/eval" }
eval-ffi = { path = "experiments/eval-ffi" }
mork-expr = { path = "expr" }
PATCH
fi

python3 - "$MACROS_RS" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
if "impl DeserializableExpr for bool" not in text:
    block = """impl DeserializableExpr for bool {
    #[inline(always)]
    fn advanced(e: Expr) -> usize {
        unsafe {
            let Tag::SymbolSize(arity) = byte_item(*e.ptr) else { panic!("wrong symbol for bool") };
            1usize + (arity as usize)
        }
    }

    #[inline(always)]
    fn check(e: Expr) -> bool {
        unsafe {
            let Tag::SymbolSize(arity) = byte_item(*e.ptr) else { return false; };
            let s = std::ptr::slice_from_raw_parts(e.ptr.add(1), arity as _);
            let bytes = s.as_ref().unwrap();
            bytes == b"true" || bytes == b"false"
        }
    }

    #[inline(always)]
    fn deserialize_unchecked(e: Expr) -> Self {
        unsafe {
            let Tag::SymbolSize(arity) = byte_item(*e.ptr) else { unreachable!() };
            let s = std::ptr::slice_from_raw_parts(e.ptr.add(1), arity as _);
            let bytes = s.as_ref().unwrap();
            bytes == b"true"
        }
    }
}

"""
    marker = "macro_rules! impl_deserializable {"
    if marker not in text:
        raise SystemExit(f"ERROR: could not find insertion marker in {path}")
    text = text.replace(marker, block + marker, 1)
    path.write_text(text)
PY

echo "MORK MM2 dependencies are wired:"
echo "  helper: $HELPER_EXT_SRC"
echo "  stdlib: $STDLIB_DIR"
