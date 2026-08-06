# Data Type Rules

## Core Rule

- **`double` is forbidden.** Every floating-point signal, parameter, and block output must be `single` (`f32`).
- Integer signals use the exact width from the naming prefix: `u8`/`u16`/`u32`/`s8`/`s16`/`s32`. Booleans use `boolean`.

## Enforcement

- Add `Data Type Conversion` blocks wherever a type changes; do this inside `SignalAcquisition` unless a conversion is functionally required elsewhere.
- Set `OutDataTypeStr` explicitly on blocks (e.g., `single`); never rely on a block inheriting `double`.
- Workspace/MATLAB variables are declared as `single`: `Kp = single(0.5);`. Never use `double(...)` or leave variables as default double.
- Constant blocks used as calibrations must set `OutputDataTypeStr` to the target type (e.g., `single` for `cal_f32...`).

## Verification

While planning and after `model_read`, check every float signal and parameter for `single`. Flag any `double` as a blocking style violation.
