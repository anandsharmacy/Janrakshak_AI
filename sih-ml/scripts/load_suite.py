#!/usr/bin/env python
"""Run the API under gunicorn at several worker counts and load-test each.

    python scripts/load_suite.py --python deploy-venv/bin/python --date 2025-08-15 \
        --out reports/stage11/load.json

For every configuration: start gunicorn (production config, preload), wait for
/healthz, record the resident memory of master + workers, run scripts/load_test.py,
record memory again, stop. The client runs on the same machine as the server, so
results are LOWER BOUNDS for a dedicated host — stated in the output.
"""
from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def rss_tree_mb(pid: int) -> dict:
    out = subprocess.run(["ps", "-o", "pid=,ppid=,rss="], capture_output=True, text=True).stdout
    rows = [tuple(map(int, l.split())) for l in out.splitlines() if l.strip()]
    kids = [r for r in rows if r[1] == pid]
    master = next((r for r in rows if r[0] == pid), None)
    return {"master_mb": (master[2] / 1024) if master else None,
            "workers_mb": [k[2] / 1024 for k in kids],
            "total_mb": ((master[2] if master else 0) + sum(k[2] for k in kids)) / 1024}


def wait_up(url: str, timeout: float = 30) -> None:
    t = time.time()
    while time.time() - t < timeout:
        try:
            urllib.request.urlopen(url + "/healthz", timeout=1).read()
            return
        except Exception:                          # noqa: BLE001
            time.sleep(0.2)
    raise RuntimeError("server did not come up")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--python", required=True, help="interpreter of the deploy env")
    ap.add_argument("--date", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--duration", type=float, default=8)
    ap.add_argument("--plan", default="default")
    a = ap.parse_args()
    py = Path(a.python)
    gunicorn = py.parent / "gunicorn"
    ids_from = ROOT / "deploy" / "scores" / f"date={a.date}" / "scores.parquet"
    plans = {"default": [
        # (workers, scenarios, concurrency levels)
        (4, ["lookup_1", "lookup_100", "score_100", "whatif_100", "alerts"], [1, 8, 32, 64]),
        (1, ["lookup_100", "score_100"], [8, 32]),
        (2, ["lookup_100", "score_100"], [8, 32]),
        (8, ["lookup_100", "score_100"], [8, 32]),
        (4, ["lookup_1"], [128, 256]),            # stress: well past saturation
    ]}
    out = Path(a.out)
    if out.exists():
        out.unlink()
    env = {**os.environ, "PYTHONPATH": str(ROOT / "src"), "SIH_THREADS": "1",
           "SIH_MAX_FEED_LAG_DAYS": "100000",       # no live feed in this repo; see readyz test
           "SIH_LOG_LEVEL": "WARNING", "DYLD_LIBRARY_PATH": "/opt/homebrew/opt/libomp/lib"}
    results = []
    for workers, scenarios, levels in plans[a.plan]:
        port = 8090 + workers
        url = f"http://127.0.0.1:{port}"
        e = {**env, "SIH_WORKERS": str(workers), "SIH_BIND": f"127.0.0.1:{port}"}
        t0 = time.perf_counter()
        srv = subprocess.Popen([str(gunicorn), "-c", str(ROOT / "deploy" / "gunicorn.conf.py"),
                                "sih_ml.serve.api:create_app()"], env=e, cwd=ROOT,
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            wait_up(url)
            startup_s = time.perf_counter() - t0
            mem_idle = rss_tree_mb(srv.pid)
            tmp = out.with_suffix(f".w{workers}.json")
            if tmp.exists():
                tmp.unlink()
            subprocess.run([str(py), str(ROOT / "scripts" / "load_test.py"), "--url", url,
                            "--date", a.date, "--scenario", *scenarios,
                            "--concurrency", *map(str, levels), "--duration", str(a.duration),
                            "--ids-from", str(ids_from), "--label", f"gunicorn-{workers}w",
                            "--out", str(tmp)], env=e, check=True)
            mem_load = rss_tree_mb(srv.pid)
            for r in json.loads(tmp.read_text()):
                r.update({"workers": workers, "startup_s": startup_s,
                          "mem_idle": mem_idle, "mem_after_load": mem_load})
                results.append(r)
            tmp.unlink()
            alive = srv.poll() is None
            results.append({"workers": workers, "server_alive_after": alive})
        finally:
            srv.send_signal(signal.SIGTERM)
            try:
                srv.wait(15)
            except subprocess.TimeoutExpired:
                srv.kill()
    import platform
    out.write_text(json.dumps({"host": {"machine": platform.machine(), "cpus": os.cpu_count(),
                                        "note": "client and server share this machine"},
                               "results": results}, indent=1))


if __name__ == "__main__":
    main()
