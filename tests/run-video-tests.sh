#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p local/vi-test
(
  cd local/vi-test
  ghdl -a --std=08 --work=mem ../../rtl/VI_package.vhd
  ghdl -a --std=08 ../../rtl/VI_package.vhd ../../rtl/functions.vhd \
    ../../rtl/VI_sqrt.vhd ../../rtl/VI_linefetch.vhd ../../rtl/VI_outProcess.vhd \
    ../../rtl/VI_videoout_async.vhd \
    ../../tests/vi_linefetch_tb.vhd ../../tests/vi_crop_tb.vhd ../../tests/vi_field_crop_tb.vhd
  for bench in vi_linefetch_tb vi_crop_tb vi_field_crop_tb; do
    ghdl -e --std=08 "$bench"
    ghdl -r --std=08 "$bench" --assert-level=error > "$bench.log" 2>&1
    tail -n 2 "$bench.log"
  done
)
verilator --binary --timing -Wno-fatal --top-module auto_crt_ar_tb \
  --Mdir local/ar-test rtl/clean_aspect_cdc.sv rtl/auto_crt_ar.sv tests/auto_crt_ar_tb.sv \
  > local/ar-test-build.log 2>&1
local/ar-test/Vauto_crt_ar_tb
verilator --binary --timing -Wno-fatal --top-module clean_aspect_cdc_tb \
  --Mdir local/cdc-test rtl/clean_aspect_cdc.sv tests/clean_aspect_cdc_tb.sv \
  > local/cdc-test-build.log 2>&1
local/cdc-test/Vclean_aspect_cdc_tb
verilator --binary --timing -Wno-fatal --top-module auto_crt_ar_math_tb \
  --Mdir local/ar-math-test rtl/auto_crt_ar.sv tests/auto_crt_ar_math_tb.sv \
  > local/ar-math-test-build.log 2>&1
local/ar-math-test/Vauto_crt_ar_math_tb
