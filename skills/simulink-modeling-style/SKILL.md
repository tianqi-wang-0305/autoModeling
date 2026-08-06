---
name: simulink-modeling-style
description: "Builds and edits Simulink models in the user's modeling style: typed port/calibration naming ({type}{Name} / cal_{type}{Name}), single-precision only (no double), no library composite blocks (PID Controller etc.), fixed layered architecture (top-level ports + MainSubsystem with SignalAcquisition, functional subsystems, OutputArbitration), requirement decomposition into a spec JSON that drives the build, detailed implementation of every subsystem's logic, state machines via basic blocks or boolean-gated Stateflow (all logic judgments in Simulink, boolean-only chart inputs), block Description attributes on ports/calibrations/subsystems, and automatic layout of every scope after generation. Use when transforming natural-language software requirements into a Simulink model, or when building/editing Simulink models that must follow these standards."
---

# Simulink Modeling Style

Build Simulink models that follow the user's modeling standards: typed naming, single-precision data types, no library composite blocks, fixed layered architecture, requirement decomposition into a spec JSON, detailed implementation of every subsystem's logic, state machines with low-complexity Stateflow (boolean-gated) or basic blocks, self-documenting block attributes, and automatic layout of every scope after generation.

## Required Reading (before any edit)

1. Read the base workflow skill `building-simulink-models` (at `../building-simulink-models/SKILL.md`, the sibling skill folder) for the `model_read` / `model_edit` / `model_check` workflow and its guardrails.
2. Read all six standards in `references/`:
   - `naming.md` — port, calibration, signal, and block naming
   - `data-types.md` — single-precision rule and enforcement
   - `block-policy.md` — allowed and forbidden blocks
   - `architecture.md` — fixed model architecture
   - `requirement-spec.md` — spec JSON schema and documentation-attribute rules
   - `state-machine.md` — state machine implementation rules (Stateflow boolean-gated pattern)

## Workflow

1. **Parse requirements into a spec JSON.** Write `<ModelName>.spec.json` into the model output directory. The spec must contain: model info; every top-level input and output with name, type, and a description definition (含义 / 单位 / 范围); every calibration with name, type, and description; every subsystem with responsibilities and its internal implementation logic; and the signal flow. Follow the schema and example in `references/requirement-spec.md`. If an ambiguity changes the architecture, ask one focused question; otherwise make a reasonable assumption and record it in the spec JSON.
2. **Present a concise plan** derived from the spec JSON before editing: model name, port table, calibration list, subsystem list, signal flow.
3. **Build with `model_edit`** following the `building-simulink-models` workflow, strictly from the spec JSON. Every element in the spec must be realized; do not add top-level elements that are absent from the spec. **Implement the detailed logic of every functional subsystem** from the spec's `logic` field: counters, comparisons, arithmetic, and state machines must be actually built. A pass-through placeholder is allowed only when the spec explicitly marks the item as deferred (e.g., an undocumented requirement) and the user accepts it. Create the `MainSubsystem` wrapper first, then populate one subsystem level at a time. Use `layout_mode: "full"` for empty scopes and `"incremental"` when adding to existing scopes.
4. **Write documentation attributes.** Mirror the spec into Simulink block attributes:
   - Every top-level `Inport` / `Outport` and every calibration `Constant` must have its `Description` set to the definition from the spec (type, meaning, unit, range).
   - Every `SubSystem` (`MainSubsystem`, `SignalAcquisition`, functional modules, `OutputArbitration`) must have its `Description` set to the responsibility plus the internal implementation logic (which blocks realize the behavior and how).
   - Use configure operations, e.g. `{"op": "configure", "block": "#x", "params": {"Description": "..."}}`.
5. **Implement state machines** per `references/state-machine.md`: either basic-block composition (Unit Delay state register + Switch priority chain) or a Stateflow Chart. If Stateflow is used, compute **all** logic judgments in Simulink and feed **only boolean** condition signals into the chart.
6. **Wire the flow** `In -> SignalAcquisition -> functional subsystems -> OutputArbitration -> Out` inside `MainSubsystem`.
7. **Auto-layout every scope.** After generation, no scope may remain as a clumped blob:
   - For the model root and every subsystem scope, run `Simulink.BlockDiagram.arrangeSystem(scope)` (for `model_edit`-built models, `layout_mode` already runs the autolayout engine; still verify the final result).
   - For every Stateflow chart, arrange the chart's states programmatically by setting each `Stateflow.State` `Position` in a grid, because `arrangeSystem` does not lay out chart internals.
8. **Verify.** Use `model_read` to confirm structure, then `model_check` to catch errors (run `stateflow_lint` where charts exist). Finally run the Style Checklist below; fix any violation before reporting completion.

## Style Checklist

Every model must pass all of these before it is considered complete:

- All ports follow `{type}{Name}` and calibrations follow `cal_{type}{Name}` (see `naming.md`).
- No `double` anywhere: every float signal, parameter, and block output is `single` (see `data-types.md`).
- No library composite blocks used — only basic blocks plus, for state machines only, Stateflow Charts following the boolean-gated pattern (see `block-policy.md` and `state-machine.md`).
- Architecture matches `architecture.md`: top-level ports + `MainSubsystem` wrapper with `SignalAcquisition`, functional subsystems, and `OutputArbitration`, wired `In -> Acquisition -> Functions -> Arbitration -> Out`.
- Top-level ports and `MainSubsystem` ports match 1:1 in name, type, and order.
- Names are code-generation-safe: `a-z A-Z 0-9 _`, no leading digit, no leading/trailing/consecutive underscores, preferably under 32 characters.
- `<ModelName>.spec.json` exists in the output directory; the model implements every input, output, calibration, and subsystem in the spec, and has no extra top-level elements (see `requirement-spec.md`).
- Every functional subsystem implements the detailed logic from its spec `logic` field — no pass-through placeholders except explicitly deferred items recorded in spec `assumptions`.
- If a Stateflow chart exists: every chart input is `boolean`; all comparisons, counters, threshold checks, and condition combinations are computed in Simulink before the chart (see `state-machine.md`).
- Every scope is auto-arranged after generation: no overlapping blocks in any subsystem, and Stateflow chart states are positioned in a readable grid (see workflow step 7).
- Every top-level port and every calibration block has a non-empty `Description` containing the definition (type, meaning, unit, range).
- Every subsystem has a non-empty `Description` documenting its responsibility and internal implementation logic.

## Example

Request: "Build a motor speed closed-loop control model. Inputs: vehicle speed (uint16), temperature (single), enable (boolean). Outputs: motor command (uint8), position (int16)."

Step 1 — write `MotorSpeedControl.spec.json`:

- Model: `MotorSpeedControl`
- Inputs: `u16VehicleSpeed` (uint16, 车速 km/h), `f32Temperature` (single, 温度 °C), `bEnable` (boolean, 使能)
- Outputs: `u8MotorCmd` (uint8, 电机指令), `s16Position` (int16, 位置反馈)
- Calibrations: `cal_f32Kp`, `cal_f32Ki` (single), `cal_u16SpeedLimit` (uint16) — each with a description
- Subsystems: `SignalAcquisition` (类型转换/裁剪), `SpeedControl` (PI，`Sum`/`Gain`/`Integrator` 组合，无 PID 块), `OutputArbitration` (使能门控与限幅) — each with logic description and the logic actually implemented
- Flow: `In -> SignalAcquisition -> SpeedControl -> OutputArbitration -> Out`

Then build per the workflow above, mirroring every spec field into block `Description` attributes and implementing every subsystem's logic, not just its interface.
