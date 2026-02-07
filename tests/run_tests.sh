#!/bin/bash
# Run all NimPulseq tests
# Usage: cd nimpulseq && bash tests/run_tests.sh

set -e

TESTS=(
  tests/test_calc_duration.nim
  tests/test_make_trapezoid.nim
  tests/test_make_block_pulse.nim
  tests/test_make_gauss_pulse.nim
  tests/test_make_adiabatic_pulse.nim
  tests/test_make_extended_trapezoid_area.nim
  tests/test_scale_grad.nim
  tests/test_block.nim
  tests/test_check_timing.nim
  tests/test_sequence.nim
)

total_pass=0
total_fail=0
failed_tests=()

for t in "${TESTS[@]}"; do
  name=$(basename "$t" .nim)
  echo "=========================================="
  echo "Running: $name"
  echo "=========================================="
  if nim c -r --hints:off "$t"; then
    echo ""
  else
    failed_tests+=("$name")
  fi
  echo ""
done

echo "=========================================="
echo "SUMMARY"
echo "=========================================="
echo "Total test files: ${#TESTS[@]}"
if [ ${#failed_tests[@]} -gt 0 ]; then
  echo "Failed test files: ${failed_tests[*]}"
  exit 1
else
  echo "All test files passed."
fi
