# Naming Standards

## Ports

Format: `{type}{Name}` — a type prefix followed by a PascalCase name.

Examples: `u16VehicleSpeed`, `f32Temperature`, `bEnable`, `u8MotorCmd`, `s16Position`.

## Calibration Parameters

Format: `cal_{type}{Name}` — the `cal_` prefix, a type prefix, and a PascalCase name.

Examples: `cal_f32Kp`, `cal_f32Ki`, `cal_u16SpeedLimit`.

Calibrations are implemented as Constant blocks or workspace variables whose names keep the `cal_` prefix.

## Type Prefixes

| Prefix | Simulink/MATLAB type |
|--------|---------------------|
| `b`    | boolean             |
| `u8`   | uint8               |
| `u16`  | uint16              |
| `u32`  | uint32              |
| `s8`   | int8                |
| `s16`  | int16               |
| `s32`  | int32               |
| `f32`  | single              |

The prefix must match the actual signal type. A mismatch is a style violation.

## Internal Signals

Use the same `{type}{Name}` convention, e.g., `f32FilteredTemp`, `bEnableValid`.

## Blocks and Subsystems

- Subsystem names: PascalCase. Fixed roles use fixed names: `SignalAcquisition`, `OutputArbitration`. Functional modules describe their purpose, e.g., `SpeedControl`, `TemperatureFilter`.
- Block names: PascalCase with a meaningful role, e.g., `Gain_Kp`, `Sum_Error`, `Integrator_Err`.
- All names must be code-generation-safe: only `a-z A-Z 0-9 _`, no leading digit, no leading/trailing/consecutive underscores, preferably under 32 characters.
