# Video regressions

Run `bash tests/run-video-tests.sh` from Linux/WSL with GHDL, Verilator,
a C++ compiler and make. Generated files stay under `local/`.

* `vi_linefetch_tb`: BattleZone's mission VI layout (`WIDTH=640`,
  `SERRATE=1`, `X_SCALE=Y_SCALE=0x400`) must fetch one source row per
  output line. The one-row offset in the odd field's supplied origin is
  compensated independently of row count, so both fields start at the same
  source row. Layouts with explicitly halved stride still fetch two rows.
  Y scaling by two still fetches two rows; progressive origins are unchanged.
* `vi_crop_tb`: framebuffer width follows the programmed horizontal
  window, including scale and subpixel offset, rather than a fixed
  640-pixel processing pass.
* `vi_courtside_tb`: captured Courtside menu layout (`WIDTH=576`,
  `X_SCALE=0x400`, `Y_SCALE=0x800`, origins `0x200480/0x200900`),
  using the real line processor. Checks all 454 framebuffer rows and their
  source-row tags in both fields, not just memory request counts.
* `vi_static_mode_tb`: the complete VI runs beyond the 30-field static-origin
  timeout with Courtside's alternating same-page origins. Checks that the
  `Y_SCALE=0x800` title retains rotating buffers and writes 454 contiguous rows,
  that `Y_SCALE=0x400` static interlacing still weaves, and that changing back
  to `0x800` leaves weave mode without an origin page change. Blank warmup
  fields shorten simulation; RAM and disabled overlays use zero-output stubs.
  Pixel contents remain covered separately by `vi_courtside_tb`.
* `vi_fb_queue_tb`: sustained CPU/RDP contention while streaming 3,000
  framebuffer words, including DDR busy cycles. Requires every word to
  reach DDR in order and other clients to continue receiving service.
* `vi_field_crop_tb`: the captured interlaced `35:509` / `37:511` windows
  produce one stable Clean HDMI blanking window. Also checks PAL fields,
  genuine crop changes, progressive menus and the Original/fixed-blank paths.
* `auto_crt_ar_tb`: measured NTSC/PAL geometry, horizontal and vertical
  crops, alternating interlaced field lengths, half-line VS phase,
  one-frame transient rejection, synchronized standard-change reset, and
  Clean HDMI disable/re-enable through the actual control synchronizer.
* `clean_aspect_cdc_tb`: two-stage enable/PAL latency, asynchronous reset
  assertion with a stopped video clock, capture of a short reset pulse,
  and reset release after two video clock edges.
* `auto_crt_ar_math_tb`: exact numerator/denominator products for maximum
  supported standard coefficients, boundary values and 256 random geometry
  snapshots. Checks arithmetic before normalization independently of raster
  acquisition and approximate aspect-ratio comparisons.

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

## Clean HDMI control timing

`clean_aspect_cdc` captures Clean HDMI enable and PAL selection in two
video-clock registers. Core reset asserts the reset synchronizer
asynchronously and releases it after two video-clock edges; the aspect
calculator still resets synchronously. Disable holds the calculator in
reset through the synchronized enable. NTSC and MPAL both select standard A.

The two new `N64.sdc` exceptions target only the reset synchronizer's
`clrn` pins and the enable/PAL first-stage `d` pins. They do not cut the
second-stage data pins or the paths to the aspect calculator. When changing
the synchronizer hierarchy, verify these four pins resolve in TimeQuest
and all three first-stage-to-second-stage setup and hold paths remain
analyzed. Aspect results use the existing `CLK_VIDEO`/`VIDEO_ARX`/`VIDEO_ARY`
interface, whose scaler consumer runs on that same video clock.
