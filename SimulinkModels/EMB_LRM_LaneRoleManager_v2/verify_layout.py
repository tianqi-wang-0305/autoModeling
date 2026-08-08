#!/usr/bin/env python3
"""Quantitative layout verification: overlaps, port alignment, flow order."""
import json
import os
import sys

PREVIEW = "/Users/wangtianqi/SimulinkModels/EMB_LRM_LaneRoleManager_v2/layout_preview"
NAMES = ["root", "main", "sa", "mls", "hbf", "stm", "mlr", "lsp", "oa"]


def overlap(a, b):
    ix = min(a[2], b[2]) - max(a[0], b[0])
    iy = min(a[3], b[3]) - max(a[1], b[1])
    return ix > 0 and iy > 0


def main():
    total = 0
    ok = True
    for name in NAMES:
        with open(os.path.join(PREVIEW, name + ".json")) as f:
            data = json.load(f)
        blks = data["blocks"]
        pos = {b["name"]: b["pos"] for b in blks}
        ov = 0
        names = list(pos)
        for i in range(len(names)):
            for j in range(i + 1, len(names)):
                if overlap(pos[names[i]], pos[names[j]]):
                    ov += 1
                    if ov <= 3:
                        print(f"  overlap {name}: {names[i]} x {names[j]}")
        total += ov
        ins = [b for b in blks if b["type"] == "Inport"]
        outs = [b for b in blks if b["type"] == "Outport"]
        if ins:
            minx = min(b["pos"][0] for b in ins)
            others = [b for b in blks if b["type"] not in ("Inport", "Outport")]
            if others and min(others, key=lambda b: b["pos"][0])["pos"][0] < minx - 1:
                ok = False
                print(f"  {name}: Inport not leftmost")
        if outs:
            maxx = max(b["pos"][2] for b in outs)
            others = [b for b in blks if b["type"] not in ("Inport", "Outport")]
            if others and max(others, key=lambda b: b["pos"][2])["pos"][2] > maxx + 1:
                ok = False
                print(f"  {name}: Outport not rightmost")
        print(f"{name}: blocks={len(blks)} overlaps={ov}")
    # flow order in MainSubsystem
    with open(os.path.join(PREVIEW, "main.json")) as f:
        main = json.load(f)
    flow = ["SignalAcquisition", "LRM_MLS_ManageLaneStatus", "LRM_MLR_ManageLaneRole",
            "LRM_LSP_LaneSwitchInProgs", "OutputArbitration"]
    xs = {b["name"]: b["pos"][0] for b in main["blocks"] if b["name"] in flow}
    order = sorted(flow, key=lambda n: xs[n])
    print("MainSubsystem pipeline x-order:", order)
    if order != flow:
        ok = False
    print("TOTAL overlaps:", total)
    print("RESULT:", "PASS" if (total == 0 and ok) else "FAIL")


if __name__ == "__main__":
    main()
