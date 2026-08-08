#!/usr/bin/env python3
"""Render dumped Simulink scope data to PNG for layout inspection."""
import json
import math
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, Rectangle

PREVIEW = "/Users/wangtianqi/SimulinkModels/EMB_LRM_LaneRoleManager_v2/layout_preview"


def color_for(bt):
    return {
        "Inport": "#b7e1cd", "Outport": "#f9c8c8", "SubSystem": "#aed6f1",
        "Constant": "#fde0ac", "Logic": "#e2b8e0", "RelationalOperator": "#e2b8e0",
        "Switch": "#d7d7d7", "UnitDelay": "#d5f0e0", "Sum": "#d8e6f8",
        "Chart": "#c9b8e8", "Terminator": "#eeeeee", "DataTypeConversion": "#cfe8f0",
        "Abs": "#d8e6f8", "Gain": "#d8e6f8", "Ground": "#eeeeee",
    }.get(bt, "#ffffff")


def render(name):
    with open(os.path.join(PREVIEW, name + ".json")) as f:
        data = json.load(f)
    blks = data["blocks"]
    conns = data["conns"]
    if not blks:
        print(name, "no blocks")
        return
    pos = {b["name"]: b["pos"] for b in blks}
    xs0 = min(b["pos"][0] for b in blks)
    ys0 = min(b["pos"][1] for b in blks)
    xs1 = max(b["pos"][2] for b in blks)
    ys1 = max(b["pos"][3] for b in blks)
    W = max(xs1 - xs0, 200) + 60
    H = max(ys1 - ys0, 150) + 60
    aspect = W / H
    fig_w = 13.0
    fig_h = max(4.0, min(13.0, fig_w / aspect))
    fig, ax = plt.subplots(figsize=(fig_w, fig_h))
    ax.set_xlim(xs0 - 30, xs1 + 30)
    ax.set_ylim(ys1 + 30, ys0 - 30)  # invert y for Simulink coords
    ax.set_aspect("equal")
    ax.axis("off")
    ax.set_title(data["scope"], fontsize=10)
    drawn = set()
    for c in conns:
        s = c["src"]
        d = c["dst"]
        if s not in pos or d not in pos:
            continue
        (sx, sy) = (pos[s][2], (pos[s][1] + pos[s][3]) / 2)
        (dx, dy) = (pos[d][0], (pos[d][1] + pos[d][3]) / 2)
        if (s, d) in drawn:
            continue
        drawn.add((s, d))
        try:
            arr = FancyArrowPatch((sx, sy), (dx, dy), arrowstyle="-|>",
                                  mutation_scale=6, lw=0.5, color="#888888", alpha=0.45)
            ax.add_patch(arr)
        except Exception:
            pass
    for b in blks:
        x0, y0, x1, y1 = b["pos"]
        w = x1 - x0
        h = y1 - y0
        ax.add_patch(Rectangle((x0, y0), w, h, facecolor=color_for(b["type"]),
                               edgecolor="#444444", lw=0.6, zorder=3))
        label = b["name"]
        if len(label) > 18:
            label = label[:17] + "~"
        fs = max(3.0, min(6.5, w / (len(label) * 0.62)))
        ax.text(x0 + w / 2, y0 + h / 2, label, ha="center", va="center",
                fontsize=fs, zorder=4, wrap=True)
    fig.savefig(os.path.join(PREVIEW, name + ".png"), dpi=110, bbox_inches="tight")
    plt.close(fig)
    print("rendered", name)


if __name__ == "__main__":
    names = sys.argv[1:] or ["root", "main", "sa", "mls", "hbf", "stm", "mlr", "lsp", "oa"]
    for n in names:
        render(n)
