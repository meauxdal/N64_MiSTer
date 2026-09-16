# N64 region, PIF bank, and video profile

These are independent selections and must not be represented by one PAL flag:

- **Region** identifies the console to software: NTSC (`00`), PAL (`01`), or MPAL (`10`).
- **PIF bank** selects the uploaded PIF ROM used by the console region.
- **Video timing profile** selects VI constants and the matching clock profile.

Part 1 only introduces the three-value region signal. The legacy `ISPAL` signal is
derived from `region == PAL`, so NTSC and PAL behavior is unchanged and MPAL uses
the existing non-PAL path. PIF-bank and video-profile selection remain unchanged.
