# N64 region, PIF bank, and video profile

These are independent selections and must not be represented by one PAL flag:

- **Region** identifies the console to software: NTSC (`00`), PAL (`01`), or MPAL (`10`).
- **PIF bank** selects the uploaded PIF ROM used by the console region.
- **Video timing profile** selects VI constants and the matching clock profile.

Part 1 only introduces the three-value region signal. The legacy `ISPAL` signal is
derived from `region == PAL`, so NTSC and PAL behavior is unchanged and MPAL uses
the existing non-PAL path.

PIF ROM upload and runtime selection use the full two-bit region value:

- `00` selects the NTSC PIF bank (`boot.rom`).
- `01` selects the PAL PIF bank (`boot1.rom`).
- `10` selects the MPAL PIF bank (`boot2.rom`).
- Reserved value `11` falls back to the NTSC bank at runtime.

The video profile remains a separate selection from the PIF bank.
