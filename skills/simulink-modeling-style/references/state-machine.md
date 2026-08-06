# State Machine Rules

## Allowed Approaches

1. **Basic-block composition** — Unit Delay state register + Switch priority chain (used for the EMB_LRM MLS / MLR / LSP state machines).
2. **Stateflow Chart** — allowed for state machines only, using the boolean-gated pattern below.

## Boolean-Gated Stateflow Pattern

Compute **all** logic judgments outside the chart, in Simulink:

- Relational comparisons (`>`, `>=`, `==`, `!=`) with Relational Operator blocks.
- Counter / timer arithmetic with `Unit Delay + Sum + Switch` counters.
- Threshold checks feeding booleans such as "watch window reached", "takeover time expired".
- Combination logic with Logical Operator blocks.

Only **boolean** condition signals enter the chart:

- Name chart inputs `b<Condition>` (e.g., `bHbFail`, `bWatchReached`, `bLclGtRmt`, `bRmtMaster`, `bOperShutdown`).
- The chart contains only states and transitions guarded by these booleans.
- The chart outputs state codes (`u8State`) or state-derived boolean flags; it does not perform arithmetic or comparisons.

## Wiring and Type Rules

- Every chart input port is `boolean`; do not route numeric signals into a chart.
- Counters stay in Simulink; the chart only receives the boolean "reached/expired" result.
- Place one chart per state machine, inside the functional subsystem.
- Run `model_check` with `stateflow_lint` before completing the model.

## Why

Keeping arithmetic and comparisons in Simulink keeps charts small, reviewable, and aligned with data-type and calibration rules; numeric logic stays visible with the blocks and calibrations that implement it.

## Chart Layout

`Simulink.BlockDiagram.arrangeSystem` arranges Simulink blocks but does not lay out the states inside a chart. After building a chart, set each state's `Position` programmatically so the chart is readable:

```matlab
st = find(chart, '-isa', 'Stateflow.State');
for i = 1:numel(st)
    st(i).Position = [50 + mod(i-1,3)*220, 50 + floor((i-1)/3)*160, 180, 100];
end
```

Also run `Simulink.BlockDiagram.arrangeSystem` on the scope containing the chart block so the chart and its condition blocks are arranged.
