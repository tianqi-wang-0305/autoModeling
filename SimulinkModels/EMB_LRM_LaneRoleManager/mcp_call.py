#!/usr/bin/env python3
"""Minimal MCP client that drives the configured MATLAB MCP Server via stdio.

Usage:
  mcp_call.py list
  mcp_call.py call <toolname> '<json-args>'

All model construction still goes through the server's model_edit tool
(autolayout, undo tracking and error recovery are inside model_edit).
"""
import json
import select
import subprocess
import sys

SERVER = "/Users/wangtianqi/.matlab/agentic-toolkits/bin/matlab-mcp-server"
EXT = "/Users/wangtianqi/.matlab/agentic-toolkits/simulink/tools/tools.json"


def send(proc, obj):
    payload = json.dumps(obj).encode("utf-8")
    proc.stdin.write(payload + b"\n")
    proc.stdin.flush()


def recv(proc, timeout=240.0):
    f = proc.stdout
    line = f.readline()
    if not line:
        return None
    return json.loads(line)


def wait_for(proc, wanted_id):
    while True:
        msg = recv(proc)
        if msg is None:
            return None
        if msg.get("id") == wanted_id:
            return msg


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "list"
    proc = subprocess.Popen(
        [
            SERVER,
            "--matlab-session-mode=existing",
            "--extension-file=%s" % EXT,
            "--disable-telemetry=true",
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        send(proc, {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "codex-agent-driver", "version": "1.0"},
            },
        })
        init_resp = wait_for(proc, 1)
        if init_resp is None:
            print("ERROR: no initialize response; stderr:",
                  proc.stderr.read().decode()[:2000])
            return 2
        send(proc, {"jsonrpc": "2.0", "method": "notifications/initialized"})

        if mode == "list":
            send(proc, {"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
            resp = wait_for(proc, 2)
            tools = (resp or {}).get("result", {}).get("tools", [])
            for t in tools:
                print(t["name"])
            return 0

        tool = sys.argv[2]
        if len(sys.argv) > 3 and sys.argv[3].startswith("@"):
            with open(sys.argv[3][1:]) as f:
                args = json.load(f)
        else:
            args = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
        if isinstance(args.get("operations"), list):
            args["operations"] = json.dumps(args["operations"], ensure_ascii=False)
        send(proc, {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": {"name": tool, "arguments": args},
        })
        resp = wait_for(proc, 2)
        if resp is None:
            print("ERROR: no tools/call response; stderr:",
                  proc.stderr.read().decode()[:2000])
            return 2
        if "error" in resp and resp["error"]:
            print("MCP_ERROR:", json.dumps(resp["error"], ensure_ascii=False))
            return 1
        result = resp.get("result", {})
        print(json.dumps(result, ensure_ascii=False, indent=1)[:120000])
        if result.get("isError"):
            return 1
        return 0
    finally:
        try:
            proc.terminate()
        except Exception:
            pass


if __name__ == "__main__":
    sys.exit(main())
