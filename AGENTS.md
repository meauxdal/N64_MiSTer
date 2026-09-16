# Repository agent instructions

## Quartus

- Never run Quartus commands or launch any Quartus process for this repository.
- Do not run synthesis, fitting, timing analysis, or a full FPGA build. An N64 core synthesis takes more than 20 minutes, and the user will run it locally when needed.
- Validate HDL changes with targeted static inspection or lightweight non-Quartus checks only.
- Do not ask to run Quartus as part of routine verification. If a result can only be verified by Quartus, state that it remains for the user to run.
