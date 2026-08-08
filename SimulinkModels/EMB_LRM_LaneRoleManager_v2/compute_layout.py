#!/usr/bin/env python3
"""Compute a flow-aware layered layout for every scope and emit target positions.

Algorithm per scope:
  1. Build dependency graph from dumped connections (deduplicated).
  2. Collapse strongly-connected components (feedback loops) into one node.
  3. Layer the component DAG by longest path from sources (inports/independent blocks).
  4. Force Inports to layer 0 and Outports to the last layer.
  5. Attach Constant blocks to the column of their (first) consumer.
  6. Order blocks inside a column by barycenter (median of predecessor rows).
  7. Emit [left, top, right, bottom] positions preserving each block's size.
"""
import collections
import json
import os
import sys

PREVIEW = "/Users/wangtianqi/SimulinkModels/EMB_LRM_LaneRoleManager_v2/layout_preview"
COL_GAP = 150
ROW_GAP = 90
MARGIN = 60


def tarjan_scc(nodes, edges):
    index = {}
    low = {}
    onstack = set()
    stack = []
    comp = {}
    counter = [0]

    def strongconnect(v):
        index[v] = low[v] = counter[0]
        counter[0] += 1
        stack.append(v)
        onstack.add(v)
        for w in edges.get(v, ()):
            if w not in index:
                strongconnect(w)
                low[v] = min(low[v], low[w])
            elif w in onstack:
                low[v] = min(low[v], index[w])
        if low[v] == index[v]:
            while True:
                w = stack.pop()
                onstack.discard(w)
                comp[w] = v
                if w == v:
                    break

    for n in nodes:
        if n not in index:
            strongconnect(n)
    return comp


def compute_scope(name):
    with open(os.path.join(PREVIEW, name + ".json")) as f:
        data = json.load(f)
    blocks = {b["name"]: b for b in data["blocks"]}
    names = list(blocks.keys())
    edges = set()
    for c in data["conns"]:
        if c["src"] in blocks and c["dst"] in blocks:
            edges.add((c["src"], c["dst"]))
    adj = collections.defaultdict(set)
    for s, d in edges:
        adj[s].add(d)
    comp = tarjan_scc(names, adj)

    # component-level DAG
    cids = sorted({comp[n] for n in names})
    cidx = {c: i for i, c in enumerate(cids)}
    csucc = collections.defaultdict(set)
    for s, d in edges:
        if comp[s] != comp[d]:
            csucc[cidx[comp[s]]].add(cidx[comp[d]])
    indeg = {i: 0 for i in range(len(cids))}
    for i in range(len(cids)):
        for j in csucc[i]:
            indeg[j] += 1
    q = collections.deque([i for i in range(len(cids)) if indeg[i] == 0])
    layer = {i: 0 for i in range(len(cids))}
    order = []
    indeg2 = dict(indeg)
    while q:
        i = q.popleft()
        order.append(i)
        for j in csucc[i]:
            layer[j] = max(layer[j], layer[i] + 1)
            indeg2[j] -= 1
            if indeg2[j] == 0:
                q.append(j)
    # any components left (should not happen with SCC) -> put at end
    for i in range(len(cids)):
        if i not in order:
            layer[i] = max(layer.values()) + 1

    # per-block layer
    blayer = {n: layer[cidx[comp[n]]] for n in names}
    for n in names:
        if blocks[n]["type"] == "Inport":
            blayer[n] = 0
    maxl = max(blayer.values()) if blayer else 0
    for n in names:
        if blocks[n]["type"] == "Outport":
            blayer[n] = maxl + 1
    maxl = max(blayer.values()) if blayer else 0

    # attach constants to consumer column
    for n in names:
        if blocks[n]["type"] == "Constant":
            cons = [d for (s, d) in edges if s == n]
            if cons:
                blayer[n] = min(blayer[d] for d in cons)
            else:
                blayer[n] = max(0, maxl - 1)

    # column blocks by layer
    cols = collections.defaultdict(list)
    for n in names:
        cols[blayer[n]].append(n)

    # row order per column: barycenter from predecessors
    row = {}
    preds = collections.defaultdict(list)
    for s, d in edges:
        preds[d].append(s)
    for L in sorted(cols):
        col = sorted(cols[L], key=lambda n: blocks[n]["name"].lower())
        ordered = []
        for n in col:
            pr = [row[p] for p in preds[n] if p in row and blayer[p] < L]
            ordered.append((n, (sorted(pr)[len(pr) // 2] if pr else 0)))
        ordered.sort(key=lambda t: (t[1], blocks[t[0]]["name"].lower()))
        # SCC members within same column: keep a stable topo-ish order by name
        for idx, (n, _) in enumerate(ordered):
            row[n] = idx
        cols[L] = [n for n, _ in ordered]

    # x positions
    colw = {}
    for L, col in cols.items():
        colw[L] = max(blocks[n]["pos"][2] - blocks[n]["pos"][0] for n in col) if col else 0
    xs = {}
    cur = MARGIN
    for L in sorted(cols):
        xs[L] = cur
        cur += colw[L] + COL_GAP
    # y positions per column
    ys = {}
    for L, col in cols.items():
        rowh = max(blocks[n]["pos"][3] - blocks[n]["pos"][1] for n in col) if col else 0
        for idx, n in enumerate(col):
            ys[n] = MARGIN + idx * (rowh + ROW_GAP)

    targets = {}
    for n in names:
        b = blocks[n]
        w = b["pos"][2] - b["pos"][0]
        h = b["pos"][3] - b["pos"][1]
        targets[n] = [xs[blayer[n]], ys[n], xs[blayer[n]] + w, ys[n] + h]
    return targets, len(names)


def main():
    names = sys.argv[1:] or ["root", "main", "sa", "mls", "hbf", "stm", "mlr", "lsp", "oa"]
    out = {}
    for n in names:
        targets, nblk = compute_scope(n)
        out[n] = targets
        print(f"{n}: {nblk} blocks -> {len(set(v[0] for v in targets.values()))} columns")
    with open(os.path.join(PREVIEW, "layout_targets.json"), "w") as f:
        json.dump(out, f, indent=1)
    print("layout_targets.json written")


if __name__ == "__main__":
    main()
