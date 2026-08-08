---
name: simulink-modeling-style
description: "Builds and edits Simulink models in the user's modeling style: typed port/calibration naming ({type}{Name} / cal_{type}{Name}), single-precision only (no double), no library composite blocks (PID Controller etc.), fixed layered architecture (top-level ports + MainSubsystem with SignalAcquisition, functional subsystems, OutputArbitration), requirement decomposition into a spec JSON that drives the build, detailed implementation of every subsystem's logic, state machines via basic blocks or boolean-gated Stateflow (all logic judgments in Simulink, boolean-only chart inputs), block Description attributes on ports/calibrations/subsystems, and automatic layout of every scope after generation. Use when transforming natural-language software requirements into a Simulink model, or when building/editing Simulink models that must follow these standards."
---

# Simulink Modeling Style

Build Simulink models that follow the user's modeling standards: typed naming, single-precision data types, no library composite blocks, fixed layered architecture, requirement decomposition into a spec JSON, detailed implementation of every subsystem's logic, state machines with low-complexity Stateflow (boolean-gated) or basic blocks, self-documenting block attributes, and automatic layout of every scope after generation.

## Required Reading (before any edit)

1. Read the base workflow skill `building-simulink-models` (bundled at `references/base-workflow/SKILL.md`) for the `model_read` / `model_edit` / `model_check` workflow and its guardrails.
2. Read all six standards in `references/`:
   - `naming.md` — port, calibration, signal, and block naming
   - `data-types.md` — single-precision rule and enforcement
   - `block-policy.md` — allowed and forbidden blocks
   - `architecture.md` — fixed model architecture
   - `requirement-spec.md` — spec JSON schema and documentation-attribute rules
   - `state-machine.md` — state machine implementation rules (Stateflow boolean-gated pattern)

## Build Policy — model_edit only

All model construction and structural edits must go through the `model_edit` MCP tool provided by the MATLAB MCP Server. This is the only allowed way to build or modify a model:

- **Allowed:** `model_edit` (with `layout_mode`), `model_read`, `model_check`, `model_overview`, `model_query_params`, `model_resolve_params`, and the other MATLAB MCP tools from the Simulink Agentic Toolkit.
- **Forbidden for building:** `matlab -batch` build scripts (e.g., `build_model.m`), and direct `set_param` / `add_block` / `add_line` / `delete_block` scripting that changes model structure. These bypass autolayout, undo tracking, and error recovery, and are not to be used for model construction.
- **Allowed as scripts:** simulation and verification scripts (e.g., `sim_test.m`, `verify_rules.m`) that only run or inspect an already-built model without changing its structure.
- **Prerequisite:** a MATLAB session with the Simulink Agentic Toolkit initialized must be running (`addpath("~/.matlab/agentic-toolkits/simulink"); satk_initialize`) so the MCP server can reach MATLAB. If `model_edit` fails, check that this initialization was done in the MATLAB session before anything else.

Never fall back to scripting a build just because it is easier or faster; if `model_edit` is unavailable, stop and report the blocker.

## Workflow

1. **Parse requirements into a spec JSON.** Write `<ModelName>.spec.json` into the model output directory. The spec must contain: model info; every top-level input and output with name, type, and a description definition (含义 / 单位 / 范围); every calibration with name, type, and description; every subsystem with responsibilities and its internal implementation logic; and the signal flow. Follow the schema and example in `references/requirement-spec.md`. If an ambiguity changes the architecture, ask one focused question; otherwise make a reasonable assumption and record it in the spec JSON.
2. **Present a concise plan** derived from the spec JSON before editing: model name, port table, calibration list, subsystem list, signal flow.
3. **Build exclusively with `model_edit`** following the bundled `building-simulink-models` workflow (`references/base-workflow/SKILL.md`) and the Build Policy above, strictly from the spec JSON. Every element in the spec must be realized; do not add top-level elements that are absent from the spec. **Implement the detailed logic of every functional subsystem** from the spec's `logic` field: counters, comparisons, arithmetic, and state machines must be actually built. A pass-through placeholder is allowed only when the spec explicitly marks the item as deferred (e.g., an undocumented requirement) and the user accepts it. Create the `MainSubsystem` wrapper first, then populate one subsystem level at a time. Use `layout_mode: "full"` for empty scopes and `"incremental"` when adding to existing scopes.
4. **Write documentation attributes.** Mirror the spec into Simulink block attributes:
   - Every top-level `Inport` / `Outport` and every calibration `Constant` must have its `Description` set to the definition from the spec (type, meaning, unit, range).
   - Every `SubSystem` (`MainSubsystem`, `SignalAcquisition`, functional modules, `OutputArbitration`) must have its `Description` set to the responsibility plus the internal implementation logic (which blocks realize the behavior and how).
   - Use configure operations, e.g. `{"op": "configure", "block": "#x", "params": {"Description": "..."}}`.
5. **Implement state machines** per `references/state-machine.md`: either basic-block composition (Unit Delay state register + Switch priority chain) or a Stateflow Chart. If Stateflow is used, compute **all** logic judgments in Simulink and feed **only boolean** condition signals into the chart.
6. **Wire the flow** `In -> SignalAcquisition -> functional subsystems -> OutputArbitration -> Out` inside `MainSubsystem`.
7. **Final layout pass after the build completes.** Once every subsystem is implemented and wired, run the layout pass over the whole model: for each scope — the model root and every `SubSystem`, innermost first, root last — call `model_edit` once per scope with `operations: []` and `layout_mode: "full"` to trigger the built-in autolayout engine (an empty `operations` array still triggers layout, with undo tracking and error recovery). Verify with `model_read` that no scope remains a clumped blob. Do not call `Simulink.BlockDiagram.arrangeSystem` from scripts and do not use script-based layout helpers — they bypass `model_edit`, and bulk Stateflow `Position` scripting can flatten chart hierarchy (sub-states become direct chart children; `stateflow_lint` then reports unreachable states / transition shadowing).
   - **The full-layout engine resets some block parameters to defaults** (observed: `Logical Operator.IconShape` and `Relational Operator.Operator` return to `distinctive` / `<=`). Therefore set style parameters (`IconShape = 'rectangular'`, comparison operators such as `>=` / `>`) **after** the final layout pass, then re-verify them (e.g., by querying the blocks) before reporting completion.
   - For every Stateflow chart, arrange the chart's states in a readable grid through `model_edit` configure operations on each `Stateflow.State` `Position` (in the Stateflow scope), keeping sub-states inside their parent state's bounds; run `stateflow_lint` after positioning. The Simulink autolayout engine does not lay out chart internals, and raw Stateflow API `Position` writes are not allowed.
8. **Verify.** Use `model_read` to confirm structure, then `model_check` to catch errors (run `stateflow_lint` where charts exist). Finally run the Style Checklist below; fix any violation before reporting completion.

## Style Checklist

Every model must pass all of these before it is considered complete:

- All structural changes were made through `model_edit` MCP tools; no `matlab -batch` build script or direct `set_param` / `add_block` scripting was used to construct the model (see Build Policy).
- All ports follow `{type}{Name}` and calibrations follow `cal_{type}{Name}` (see `naming.md`).
- No `double` anywhere: every float signal, parameter, and block output is `single` (see `data-types.md`).
- No library composite blocks used — only basic blocks plus, for state machines only, Stateflow Charts following the boolean-gated pattern (see `block-policy.md` and `state-machine.md`).
- Architecture matches `architecture.md`: top-level ports + `MainSubsystem` wrapper with `SignalAcquisition`, functional subsystems, and `OutputArbitration`, wired `In -> Acquisition -> Functions -> Arbitration -> Out`.
- Top-level ports and `MainSubsystem` ports match 1:1 in name, type, and order.
- Names are code-generation-safe: `a-z A-Z 0-9 _`, no leading digit, no leading/trailing/consecutive underscores, preferably under 32 characters.
- `<ModelName>.spec.json` exists in the output directory; the model implements every input, output, calibration, and subsystem in the spec, and has no extra top-level elements (see `requirement-spec.md`).
- Every functional subsystem implements the detailed logic from its spec `logic` field — no pass-through placeholders except explicitly deferred items recorded in spec `assumptions`.
- If a Stateflow chart exists: every chart input is `boolean`; all comparisons, counters, threshold checks, and condition combinations are computed in Simulink before the chart (see `state-machine.md`).
- Final layout pass ran after the build: `model_edit` with `operations: []` and `layout_mode: "full"` on every scope (innermost → root); no overlapping blocks in any subsystem, and Stateflow chart states are positioned in a readable grid (see workflow step 7).
- All boolean logic uses the standard Simulink `Logical Operator` / `Relational Operator` blocks configured via the `Operator` parameter (`AND` / `OR` / `NOT` / comparisons), displayed with `IconShape = 'rectangular'` text — no gate-icon-shaped logic blocks (see `block-policy.md`).
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
