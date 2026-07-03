#!/bin/bash
#
# diagnose_em_field_uninit.sh
#
# Diagnoses the intermittent `mat6_calc_method_test::EM_FIELD1:Taylor:*` failure
# (PR #2044).  Root cause is an uninitialised-memory read in the PTC "pancake"
# code path (forest library) that is only reached for em_field elements with a
# gen_grad_map tracked via symp_lie_ptc / Taylor.  Because it reads uninitialised
# HEAP, it is invisible to gfortran -Wuninitialized and to -finit-* flags; it
# only misbehaves when the surrounding heap happens to hold non-zero garbage,
# which is why it is intermittent and platform specific.
#
# This script does two things:
#   (1) REPRODUCE it deterministically by poisoning freshly-allocated heap.
#   (2) PINPOINT the exact read (file:line + origin) with Valgrind (Linux only).
#
# Run it from inside the test directory, e.g.:
#   cd regression_tests/mat6_calc_method_test
#   ../../.github/scripts/diagnose_em_field_uninit.sh
#
# Prereq: a *debug* build (util/dist_build_debug), so binaries carry -g and the
# forest sources are compiled -O0 (cleaner Valgrind stacks).  Point BIN at it.
set -u

BIN="${BIN:-$(cd ../.. && pwd)/debug/bin/mat6_calc_method_test}"
LAT="${LAT:-em_field_min.bmad}"     # minimal lattice keeps the report focused
OS="$(uname -s)"

echo "== binary : $BIN"
echo "== lattice: $LAT"
echo "== os     : $OS"
[ -x "$BIN" ] || { echo "!! debug binary not found; build with util/dist_build_debug"; exit 2; }

echo
echo "############################################################"
echo "# (1) Reproduce deterministically by poisoning the heap"
echo "############################################################"
echo "# The correct EM_FIELD1:Taylor:MatrixRow1 col3 is ~ -3.0e-05."
echo "# If poisoning makes it jump/collapse, the bug is reproduced."
echo
# With a lattice argument the program prints the matrices to STDOUT (not
# output.now), so capture stdout.  Report the whole Taylor Row1 (R11..R16);
# the coupling terms (col 4 = R13) collapse toward 0 when the bug fires.
row_of () {  # args: env-prefix...
  env "$@" "$BIN" "$LAT" 2>/dev/null | \
    awk '/EM_FIELD1:Taylor:MatrixRow1/{$1="";print;exit}'
}
if [ "$OS" = "Linux" ]; then
  # glibc: fill malloc'd bytes with the given value, freed bytes with its complement.
  for p in 0 1 42 170 255; do
    echo "MALLOC_PERTURB_=$p ->$(row_of MALLOC_PERTURB_=$p)"
  done
else
  # macOS: scribble freshly-allocated (0xAA) and freed (0x55) heap.
  echo "scribble=off ->$(row_of)"
  echo "scribble=on  ->$(row_of MallocPreScribble=1 MallocScribble=1)"
  echo "# (also try Guard Malloc:  DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib )"
fi

echo
echo "############################################################"
echo "# (2) Pinpoint the read with Valgrind (Linux only)"
echo "############################################################"
if [ "$OS" = "Linux" ] && command -v valgrind >/dev/null 2>&1; then
  valgrind --tool=memcheck --track-origins=yes --num-callers=40 \
           --error-limit=no --log-file=valgrind_em_field.log \
           "$BIN" "$LAT" >/dev/null 2>&1
  echo "# Full log: valgrind_em_field.log"
  echo "# Uninitialised-value reads originating in the forest pancake path:"
  grep -nE "Use of uninitialised|depends on uninitialised|Uninitialised value|Conditional jump" \
       valgrind_em_field.log | head
  echo "----- first origin backtrace touching forest/PTC -----"
  awk '/uninitialised/{f=1} f{print} /^==.*$/{if(f && $0 ~ /^==[0-9]+== *$/) exit}' \
       valgrind_em_field.log | grep -iE "pancake|_tree|def_kind|mad_like|def_element|forest|ptc" | head
else
  echo "# Valgrind step skipped (needs Linux + valgrind)."
  echo "# On the ubuntu-latest CI runner:  sudo apt-get install -y valgrind"
fi
