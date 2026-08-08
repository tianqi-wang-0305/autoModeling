# Block Policy — Basic Blocks Only

## Forbidden

Library/composite blocks whose behavior must be assembled from basic blocks. Examples:

- `PID Controller`, `Discrete PID Controller`
- `Transfer Fcn`, `State-Space`, `Zero-Pole`
- `Lookup Table` families used to replace analytic blocks
- Any other composite library block that can be composed from basic blocks

## Allowed

Basic Simulink blocks, including:

- `Inport`, `Outport`, `Constant`, `Ground`
- `Gain`, `Sum`, `Product`, `Divide`, `Abs`, `Bias`, `Saturation`, `MinMax`
- `Integrator`, `Unit Delay`
- `Data Type Conversion`
- `Relational Operator`, `Logical Operator`, `Switch`
- `Scope`, `To Workspace` (for verification only)
- `Chart` (Stateflow) — only for state machines, and only with the boolean-gated pattern in `state-machine.md` (all logic judgments computed in Simulink, boolean inputs only)

## Composition Rules

- Compose behavior from basic blocks. Example: a PI controller is `Sum(Error) -> Gain(Kp)` parallel with `Gain(Ki) -> Integrator`, then a final `Sum`; never the `PID Controller` block.
- All boolean logic (AND / OR / NOT / NAND / NOR / XOR and comparisons) must use the standard Simulink library blocks `Logical Operator` (BlockType `Logic`, i.e. the library block `simulink/Logic and Bit Operations/Logical Operator`) or `Relational Operator`, configured via the `Operator` parameter (`AND`, `OR`, `NOT`, `==`, `>=`, ...). Set `IconShape` to `'rectangular'` so the block displays the operator text (AND / OR / NOT) — do not use gate-circuit-shaped blocks (`IconShape 'distinctive'`) or any custom/combinatorial logic blocks.
- State machines may be built from basic blocks (Unit Delay state register + Switch priority chain) or with a Stateflow Chart; a Chart must receive only boolean conditions computed in Simulink — never numeric signals or in-chart arithmetic.
- When unsure whether a block is allowed, prefer the basic-block composition. If the requirement genuinely requires a library block, ask the user before using it.
