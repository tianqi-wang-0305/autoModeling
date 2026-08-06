# Model Architecture

## Fixed Structure

```
ModelName
├── Inports:  {type}{Name}   e.g., u16VehicleSpeed, f32Temperature, bEnable
├── Outports: {type}{Name}   e.g., u8MotorCmd, s16Position
└── SubSystem: MainSubsystem (wrapper containing all logic)
    ├── Inports  (1:1 with top level: same names, types, order)
    ├── Outports (1:1 with top level)
    ├── SubSystem: SignalAcquisition   <- signal conditioning / type conversion
    ├── SubSystem: <FunctionalModule>  <- one per requirement (may chain)
    ├── SubSystem: OutputArbitration   <- output arbitration / merge / limit
    └── wiring: In -> SignalAcquisition -> FunctionalModules -> OutputArbitration -> Out
```

## Rules

- The top level contains only ports and the `MainSubsystem` wrapper — no other blocks or logic.
- `MainSubsystem` ports mirror the top-level ports exactly (names, types, order).
- Signal flow is unidirectional through the chain: `In -> SignalAcquisition -> functional modules -> OutputArbitration -> Out`.
- Type conversions and conditioning happen in `SignalAcquisition`.
- Multiple functional modules are chained only when requirements imply sequential processing; `OutputArbitration` always feeds the outports.
- A role with no logic still exists as a pass-through (wire through) so the architecture is preserved.
- Build one subsystem level at a time with `model_edit`, using `model_read` between levels to discover IDs.
