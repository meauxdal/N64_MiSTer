# Video regressions

Run `bash tests/run-video-tests.sh` from Linux/WSL with GHDL, Verilator,
a C++ compiler and make. Generated files stay under `local/`.

* `vi_linefetch_tb`: BattleZone's mission VI layout (`WIDTH=640`,
  `SERRATE=1`, `X_SCALE=Y_SCALE=0x400`) must fetch one source row per
  output line. The odd field must retain its supplied origin. Layouts
  with explicitly halved stride still fetch two rows and adjust the odd
  field origin. Y scaling by two still fetches two rows.
* `vi_crop_tb`: framebuffer width follows the programmed horizontal
  window, including scale and subpixel offset, rather than a fixed
  640-pixel processing pass.
* `auto_crt_ar_tb`: measured NTSC/PAL geometry, horizontal and vertical
  crops, alternating interlaced field lengths, half-line VS phase,
  one-frame transient rejection and standard-change reset.

## BattleZone capture

The local HailToDodongo Ares source was instrumented at `VI::refresh()`
to log origin, width, SERRATE, X/Y scale and offset, H/V start/end and
field. The headless runner used the local USA ROM; rendered checkpoints
confirmed progression through the Controller Pak and Rumble Pak prompts
into the mission. Source, ROM, runner, screenshots and logs remain in
`local/` and are not test dependencies.

Menus used width 320, progressive, X scale 0x200 and Y scale 0x400.
The mission changed to width 640, SERRATE, X/Y scale 0x400, H 108:748,
and alternating V 35:509 / 37:511. Field origins included 0x6C2D00 and
0x6C3200 (one 640-pixel 16-bit row apart). The previous Clean HDMI logic
requested two rows even though this layout did not halve VI_WIDTH.

## Hardware check

Boot BattleZone in Clean HDMI and start a mission. Check that the
picture no longer repeats or reads beyond the field, and that Original
aspect follows the cropped VI window. Compare with Original (VI).
Also check an existing interlaced game that uses halved stride, NTSC/PAL
games with narrow or short VI windows, mode transitions, and the Full
Screen/custom aspect overrides.

Simulation and Quartus elaboration do not establish FPGA timing closure
or replace this on-device check.
