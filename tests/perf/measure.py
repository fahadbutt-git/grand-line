#!/usr/bin/env python3
"""Measures what Grand Line's apps cost while idle and after use.

tests/perf/run.sh drives it; each subcommand prints or writes JSON, and
`report` turns the results into the budget table (tests/perf/budgets.env
holds every limit). Standard library only, so it runs on any Mac with the
system Python 3, and the parsers run on Linux too (their tests are in
tests/run-all.sh through `selftest`).

  measure.py pids NAME...                    the process tree of each program
  measure.py snapshot NAME...                CPU time, RSS, footprint, FDs now
  measure.py idle --budgets F --out FILE NAME...
  measure.py sampler --stop FILE --out FILE NAME...   peak CPU while a burst runs
  measure.py decay --budgets F --out FILE NAME...     seconds back under budget
  measure.py powermetrics --out FILE NAME...          wakeups and GPU (sudo)
  measure.py shell --zshrc FILE --runs N --out FILE
  measure.py agents --out FILE PLIST...
  measure.py report --budgets F --results DIR
  measure.py selftest
"""

import json
import os
import plistlib
import re
import shutil
import statistics
import subprocess
import sys
import threading
import time


def read_budgets(path):
    budgets = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            try:
                budgets[key.strip()] = float(value.strip())
            except ValueError:
                budgets[key.strip()] = value.strip()
    return budgets


def run(args, timeout=30):
    try:
        out = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return out.returncode, out.stdout
    except (OSError, subprocess.TimeoutExpired):
        return 1, ""


# --- processes


def split_name(spec):
    """NAME, or NAME=PID for a process found another way (the index's
    launchd job, when the installed agent runs beside it)."""
    name, _, pid = spec.partition("=")
    return name, (int(pid) if pid.isdigit() else None)


def pids_of(spec):
    """The program's processes and their children (Iceberg's Now Playing
    helper runs under it, and counts as Iceberg)."""
    name, pid = split_name(spec)
    if pid is not None:
        roots = [pid]
    else:
        code, out = run(["pgrep", "-x", name])
        roots = [int(p) for p in out.split()] if code == 0 else []
    found = list(roots)
    queue = list(roots)
    while queue:
        parent = queue.pop()
        code, out = run(["pgrep", "-P", str(parent)])
        for child in (int(p) for p in out.split()) if code == 0 else []:
            if child not in found:
                found.append(child)
                queue.append(child)
    return found


def parse_cputime(text):
    """ps TIME: [[dd-]hh:]mm:ss[.cc], in seconds."""
    text = text.strip()
    days = 0
    if "-" in text:
        d, text = text.split("-", 1)
        days = int(d)
    parts = text.split(":")
    seconds = 0.0
    for part in parts:
        seconds = seconds * 60 + float(part)
    return days * 86400 + seconds


def ps_rows(pids):
    if not pids:
        return {}
    code, out = run(["ps", "-o", "pid=,time=,rss=,%cpu=", "-p", ",".join(str(p) for p in pids)])
    rows = {}
    for line in out.splitlines():
        cols = line.split()
        if len(cols) < 4:
            continue
        rows[int(cols[0])] = {"cpu_s": parse_cputime(cols[1]), "rss_kb": int(cols[2]), "pcpu": float(cols[3])}
    return rows


def parse_footprint(text):
    """MB from `footprint` or `vmmap --summary`, or None."""
    m = re.search(r"(?i)(?:phys_footprint|physical footprint|footprint)\s*[:=]?\s*([\d.]+)\s*([KMG])i?B?\b", text)
    if not m:
        return None
    value = float(m.group(1))
    return value * {"K": 1 / 1024, "M": 1, "G": 1024}[m.group(2).upper()]


def footprint_mb(pid):
    if shutil.which("footprint"):
        code, out = run(["footprint", "-p", str(pid)], timeout=20)
        if code != 0:
            code, out = run(["footprint", str(pid)], timeout=20)
        found = parse_footprint(out)
        if found is not None:
            return found
    if shutil.which("vmmap"):
        _, out = run(["vmmap", "--summary", str(pid)], timeout=30)
        return parse_footprint(out)
    return None


def fd_count(pid):
    code, out = run(["lsof", "-n", "-P", "-p", str(pid)], timeout=20)
    lines = out.splitlines()
    return max(0, len(lines) - 1)


def snapshot(specs, details=True):
    result = {}
    for spec in specs:
        name = split_name(spec)[0]
        pids = pids_of(spec)
        rows = ps_rows(pids)
        entry = {
            "pids": pids,
            "cpu_s": sum(r["cpu_s"] for r in rows.values()),
            "rss_mb": sum(r["rss_kb"] for r in rows.values()) / 1024,
            "pcpu": sum(r["pcpu"] for r in rows.values()),
            "time": time.time(),
        }
        if details and pids:
            prints = [footprint_mb(p) for p in pids]
            entry["footprint_mb"] = sum(p for p in prints if p is not None) if any(p is not None for p in prints) else None
            entry["fds"] = sum(fd_count(p) for p in pids)
        result[name] = entry
    return result


def cpu_percent(before, after):
    """Percent of one core over the time between two snapshots."""
    wall = after["time"] - before["time"]
    if wall <= 0:
        return 0.0
    return max(0.0, (after["cpu_s"] - before["cpu_s"]) / wall * 100)


# --- top


def parse_top(text, interval):
    """`top -l 2 -s N -c d -stats pid,cpu,idlew`: the second sample's idle
    wakeups per second, by pid."""
    blocks = re.split(r"(?m)^PID\s", text)
    if len(blocks) < 3:
        return {}
    wake = {}
    for line in blocks[-1].splitlines()[1:]:
        cols = line.split()
        if len(cols) >= 3 and cols[0].isdigit():
            try:
                wake[int(cols[0])] = float(cols[2].rstrip("+")) / interval
            except ValueError:
                pass
    return wake


def top_wakeups(pids, seconds):
    if not pids or not shutil.which("top"):
        return {}
    args = ["top", "-l", "2", "-s", str(int(seconds)), "-c", "d", "-stats", "pid,cpu,idlew"]
    for p in pids:
        args += ["-pid", str(p)]
    _, out = run(args, timeout=seconds + 30)
    return parse_top(out, seconds)


# --- powermetrics


def expand_header(header):
    cols = re.split(r"\s{2,}", header.strip())
    names = []
    for col in cols[1:]:
        if "(" in col and "," in col:
            inner = col[col.index("(") + 1:col.rindex(")")]
            base = col[:col.index("(")].strip()
            names += ["%s %s" % (base, part.strip()) for part in inner.split(",")]
        else:
            names.append(col)
    return names  # without Name


def parse_powermetrics(text, names):
    """Average per-program numbers over every sample in the tasks section:
    CPU ms/s, wakeups per second (interrupt and package idle) and GPU ms/s."""
    per = {n: [] for n in names}
    header = None
    for line in text.splitlines():
        if line.startswith("Name") and "ID" in line:
            header = expand_header(line)
            continue
        if header is None or not line.strip():
            if not line.strip():
                header = None if header is None else header
            continue
        tokens = line.split()
        width = len(header)
        if len(tokens) < width + 1:
            continue
        values = tokens[-width:]
        name = " ".join(tokens[:-width])
        if name not in per:
            continue
        try:
            row = dict(zip(header, (float(v) for v in values)))
        except ValueError:
            continue
        per[name].append(row)
    result = {}
    for name, rows in per.items():
        if not rows:
            continue

        def avg(pick):
            vals = [pick(r) for r in rows]
            vals = [v for v in vals if v is not None]
            return sum(vals) / len(vals) if vals else None

        def col(row, *starts):
            for k, v in row.items():
                if any(k.lower().startswith(s) for s in starts):
                    return v
            return None

        result[name] = {
            "cpu_ms_s": avg(lambda r: col(r, "cpu ms/s")),
            "wakeups_s": avg(lambda r: (col(r, "wakeups intr") or 0) + (col(r, "wakeups pkg idle") or 0)),
            "gpu_ms_s": avg(lambda r: col(r, "gpu ms/s")),
            "samples": len(rows),
        }
    return result


def powermetrics(names, samples=3, interval_ms=5000):
    names = [split_name(n)[0] for n in names]
    if not shutil.which("powermetrics"):
        return {"skipped": "powermetrics is not on this Mac"}
    args = ["sudo", "-n", "powermetrics", "--samplers", "tasks,gpu_power", "--show-process-energy",
            "--show-process-gpu", "-n", str(samples), "-i", str(interval_ms)]
    code, out = run(args, timeout=samples * interval_ms / 1000 + 60)
    if code != 0 or "Name" not in out:
        # Older or restricted runners: the tasks sampler alone.
        args = ["sudo", "-n", "powermetrics", "--samplers", "tasks", "--show-process-energy",
                "-n", str(samples), "-i", str(interval_ms)]
        code, out = run(args, timeout=samples * interval_ms / 1000 + 60)
    if code != 0 or "Name" not in out:
        return {"skipped": "powermetrics needs sudo without a password, or gave no task list"}
    parsed = parse_powermetrics(out, names)
    has_gpu = "GPU ms/s" in out
    return {"processes": parsed, "gpu": has_gpu}


# --- subcommands


def cmd_idle(budgets, names, out):
    specs, names = names, [split_name(n)[0] for n in names]
    seconds = float(budgets.get("IDLE_SECONDS", 60))
    every = float(budgets.get("SAMPLE_EVERY", 5))
    before = snapshot(specs, details=False)
    all_pids = [p for n in names for p in before[n]["pids"]]
    wake = {}
    t = threading.Thread(target=lambda: wake.update(top_wakeups(all_pids, seconds)))
    t.start()
    samples = {n: [] for n in names}
    end = time.time() + seconds
    while time.time() < end:
        time.sleep(min(every, max(0.0, end - time.time())))
        now = snapshot(specs, details=False)
        for n in names:
            samples[n].append(now[n]["pcpu"])
    t.join()
    after = snapshot(specs, details=True)
    result = {}
    for n in names:
        result[n] = {
            "running": bool(after[n]["pids"]),
            "cpu_pct": cpu_percent(before[n], after[n]),
            "ps_avg_pct": statistics.mean(samples[n]) if samples[n] else 0.0,
            "top_wakeups_s": sum(wake.get(p, 0.0) for p in after[n]["pids"]) if wake else None,
            "rss_mb": after[n]["rss_mb"],
            "footprint_mb": after[n].get("footprint_mb"),
            "fds": after[n].get("fds"),
        }
    write(out, result)


def cmd_sampler(names, stop, out):
    specs, names = names, [split_name(n)[0] for n in names]
    """CPU over each second until the stop file appears: the burst's peak."""
    peak = {n: 0.0 for n in names}
    last = snapshot(specs, details=False)
    rss_peak = {n: last[n]["rss_mb"] for n in names}
    while not os.path.exists(stop):
        time.sleep(1)
        now = snapshot(specs, details=False)
        for n in names:
            peak[n] = max(peak[n], cpu_percent(last[n], now[n]))
            rss_peak[n] = max(rss_peak[n], now[n]["rss_mb"])
        last = now
    write(out, {n: {"peak_cpu_pct": peak[n], "peak_rss_mb": rss_peak[n], "rss_mb": last[n]["rss_mb"]} for n in names})


def cmd_decay(budgets, names, out):
    specs, names = names, [split_name(n)[0] for n in names]
    """Seconds until each program's CPU over a two-second window stays under
    DECAY_CPU, looking for DECAY_SECONDS plus a margin to report how late."""
    limit = float(budgets.get("DECAY_CPU", 1.0))
    window = float(budgets.get("DECAY_SECONDS", 30))
    start = time.time()
    settled = {n: None for n in names}
    last = snapshot(specs, details=False)
    while time.time() - start < window * 2 and any(v is None for v in settled.values()):
        time.sleep(2)
        now = snapshot(specs, details=False)
        for n in names:
            if settled[n] is None and cpu_percent(last[n], now[n]) < limit:
                settled[n] = round(time.time() - start, 1)
        last = now
    final = snapshot(specs, details=False)
    write(out, {n: {"settled_after_s": settled[n], "rss_mb": final[n]["rss_mb"]} for n in names})


def cmd_shell(zshrc, runs, out):
    """Median wall time of `zsh -i -c exit` with ZDOTDIR holding zshrc. The
    first start (which fills the init caches) is not counted."""
    if not shutil.which("zsh"):
        write(out, {"skipped": "zsh is not installed"})
        return
    zdot = os.path.dirname(os.path.abspath(zshrc))
    env = dict(os.environ, ZDOTDIR=zdot)
    times = []
    for i in range(runs + 1):
        t = time.perf_counter()
        subprocess.run(["zsh", "-i", "-c", "exit"], env=env, stdin=subprocess.DEVNULL,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
        if i:
            times.append((time.perf_counter() - t) * 1000)
    write(out, {"median_ms": statistics.median(times), "max_ms": max(times), "runs": runs})


def check_agent(plist):
    """Problems with one launch agent: a KeepAlive that restarts it forever,
    a watch with no throttle, work at normal priority."""
    problems = []
    label = plist.get("Label", "?")
    keep = plist.get("KeepAlive")
    if keep is True and label != "com.grandline.index":
        problems.append("KeepAlive true restarts it without end")
    if isinstance(keep, dict) and keep.get("SuccessfulExit") is True:
        problems.append("KeepAlive SuccessfulExit true restarts it after every clean exit")
    if ("WatchPaths" in plist or "QueueDirectories" in plist) and int(plist.get("ThrottleInterval", 10)) < 10:
        problems.append("a watched job needs a ThrottleInterval of 10 s or more")
    process = plist.get("ProcessType")
    if label == "com.grandline.index":
        if process not in ("Adaptive", "Background"):
            problems.append("the index runs Adaptive or Background")
        if keep is not None and not isinstance(keep, dict):
            problems.append("the index restarts only after a crash (KeepAlive SuccessfulExit false)")
    else:
        if process != "Background":
            problems.append("ProcessType must be Background")
        if plist.get("LowPriorityIO") is not True:
            problems.append("LowPriorityIO must be true")
    interval = plist.get("StartInterval")
    if interval is not None and int(interval) < 900:
        problems.append("StartInterval under 15 minutes")
    return problems


def cmd_agents(paths, out):
    result = {}
    for path in paths:
        with open(path, "rb") as f:
            plist = plistlib.load(f)
        schedule = {k: plist[k] for k in ("RunAtLoad", "StartInterval", "StartCalendarInterval", "WatchPaths",
                                          "KeepAlive", "ThrottleInterval", "ProcessType", "LowPriorityIO", "Nice")
                    if k in plist}
        result[plist.get("Label", os.path.basename(path))] = {"schedule": schedule, "problems": check_agent(plist)}
    write(out, result)
    return result


def write(path, data):
    text = json.dumps(data, indent=2, sort_keys=True, default=str)
    if path in (None, "-"):
        print(text)
    else:
        with open(path, "w") as f:
            f.write(text + "\n")


def load(results, name):
    path = os.path.join(results, name)
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return json.load(f)


def fmt(value, digits=1):
    if value is None:
        return "-"
    if isinstance(value, float):
        return ("%." + str(digits) + "f") % value
    return str(value)


def build_report(budgets, results):
    """Rows for the table and the list of budgets exceeded."""
    names = ["GrandLineIndex", "Nexus", "Sight", "Iceberg"]
    idle = load(results, "idle.json") or {}
    power = load(results, "power-idle.json") or {}
    power_after = load(results, "power-after.json") or {}
    rounds = [load(results, "burst-%d.json" % i) for i in range(1, int(budgets.get("BURST_ROUNDS", 3)) + 1)]
    decays = [load(results, "decay-%d.json" % i) for i in range(1, int(budgets.get("BURST_ROUNDS", 3)) + 1)]
    fixture = load(results, "fixture.json") or {}
    failures, notes, rows = [], [], []
    procs = power.get("processes", {})
    procs_after = power_after.get("processes", {})
    if "skipped" in power:
        notes.append("wakeups and GPU from powermetrics skipped: " + power["skipped"])
    elif not power.get("gpu"):
        notes.append("this runner shows no per-process GPU counters; GPU budget not checked")

    total = 0.0
    for n in names:
        i = idle.get(n, {})
        if not i.get("running"):
            failures.append("%s was not running during the idle minute" % n)
        cpu = i.get("cpu_pct", 0.0)
        total += cpu
        wake = procs.get(n, {}).get("wakeups_s")
        if wake is None:
            wake = i.get("top_wakeups_s")
        gpu = procs.get(n, {}).get("gpu_ms_s")
        rss = i.get("rss_mb")
        peak = max((r or {}).get(n, {}).get("peak_cpu_pct", 0.0) for r in rounds) if any(rounds) else None
        settle = [(d or {}).get(n, {}).get("settled_after_s") for d in decays if d]
        settle_worst = None if not settle else (None if None in settle else max(settle))
        rss_rounds = [(d or {}).get(n, {}).get("rss_mb") for d in decays if d]
        growth = None
        if len(rss_rounds) >= 3 and rss_rounds[1]:
            growth = (rss_rounds[2] - rss_rounds[1]) / rss_rounds[1] * 100

        if cpu > budgets["IDLE_CPU_PER_APP"]:
            failures.append("%s idle CPU %.2f%% (budget %.2f%%)" % (n, cpu, budgets["IDLE_CPU_PER_APP"]))
        if wake is not None and wake > budgets["IDLE_WAKEUPS_PER_APP"]:
            failures.append("%s idle wakeups %.1f/s (budget %g/s)" % (n, wake, budgets["IDLE_WAKEUPS_PER_APP"]))
        if gpu is not None and power.get("gpu") and gpu > budgets["IDLE_GPU_MS_PER_S"]:
            failures.append("%s idle GPU %.2f ms/s (budget %g ms/s)" % (n, gpu, budgets["IDLE_GPU_MS_PER_S"]))
        gpu_after = procs_after.get(n, {}).get("gpu_ms_s")
        if gpu_after is not None and power_after.get("gpu") and gpu_after > budgets["IDLE_GPU_MS_PER_S"]:
            failures.append("%s GPU %.2f ms/s after the burst (budget %g ms/s)" % (n, gpu_after, budgets["IDLE_GPU_MS_PER_S"]))
        limit = budgets.get("RSS_MB_" + n)
        if rss is not None and limit is not None and rss > limit:
            failures.append("%s RSS %.0f MB (budget %g MB)" % (n, rss, limit))
        if decays and any(decays) and settle_worst is None:
            failures.append("%s stayed above %g%% CPU after a burst" % (n, budgets["DECAY_CPU"]))
        elif settle_worst is not None and settle_worst > budgets["DECAY_SECONDS"]:
            failures.append("%s took %.0f s to settle after a burst (budget %g s)" % (n, settle_worst, budgets["DECAY_SECONDS"]))
        if growth is not None and growth > budgets["RSS_GROWTH_PCT"]:
            failures.append("%s RSS grew %.1f%% from burst 2 to 3 (budget %g%%)" % (n, growth, budgets["RSS_GROWTH_PCT"]))
        fds = i.get("fds")
        if fds is not None and fds > budgets.get("FDS_PER_APP", 1e9):
            failures.append("%s has %d open files (budget %g)" % (n, fds, budgets["FDS_PER_APP"]))
        rows.append([n, fmt(cpu, 2), fmt(i.get("ps_avg_pct"), 2), fmt(wake), fmt(gpu, 2), fmt(rss, 0),
                     fmt(i.get("footprint_mb"), 0), fmt(fds), fmt(peak, 0), fmt(settle_worst, 0),
                     " / ".join(fmt(r, 0) for r in rss_rounds) or "-", fmt(growth)])
    if total > budgets["IDLE_CPU_TOTAL"]:
        failures.append("all apps together idle CPU %.2f%% (budget %.2f%%)" % (total, budgets["IDLE_CPU_TOTAL"]))
    index_rss = idle.get("GrandLineIndex", {}).get("rss_mb")
    files = fixture.get("files")
    if index_rss and files:
        notes.append("index: %.0f bytes per file in the fixture (%d files, %.0f MB resident)"
                     % (index_rss * 1024 * 1024 / files, files, index_rss))
    shell = load(results, "shell.json") or {}
    if "skipped" in shell:
        notes.append("shell startup skipped: " + shell["skipped"])
    elif shell:
        if shell["median_ms"] > budgets["SHELL_MEDIAN_MS"]:
            failures.append("shell startup median %.0f ms (budget %g ms)" % (shell["median_ms"], budgets["SHELL_MEDIAN_MS"]))
        notes.append("shell startup: median %.0f ms, slowest %.0f ms over %d starts" % (shell["median_ms"], shell["max_ms"], shell["runs"]))
    agents = load(results, "agents.json") or {}
    for label, entry in sorted(agents.items()):
        for problem in entry["problems"]:
            failures.append("launch agent %s: %s" % (label, problem))
        notes.append("launch agent %s: %s" % (label, ", ".join("%s=%s" % kv for kv in sorted(entry["schedule"].items()))))
    focus = load(results, "focus.json")
    if focus:
        if not focus.get("front_kept"):
            failures.append("focus: %s came to the front while TextEdit was being typed in" % focus.get("front_after"))
        if not focus.get("text_kept"):
            failures.append("focus: keystrokes were lost (typed %d characters, TextEdit has %d)"
                            % (focus.get("typed", 0), focus.get("received", 0)))
        if focus.get("skipped"):
            notes.append("focus check skipped: " + focus["skipped"])
    stalls = load(results, "stalls.json") or {}
    for app, ms in sorted(stalls.items()):
        if ms > 1000:
            failures.append("%s logged a main-thread stall of %d ms" % (app, ms))
    total_row = ["all", fmt(total, 2), "", "", "", "", "", "", "", "", "", ""]
    return rows + [total_row], failures, notes


HEADERS = ["Process", "Idle CPU %", "ps avg %", "Wakeups/s", "GPU ms/s", "RSS MB", "Footprint MB", "FDs",
           "Burst peak %", "Settle s", "RSS after bursts MB", "Growth 2-3 %"]


def cmd_report(budgets, results):
    rows, failures, notes = build_report(budgets, results)
    table = ["| " + " | ".join(HEADERS) + " |", "|" + "---|" * len(HEADERS)]
    table += ["| " + " | ".join(r) + " |" for r in rows]
    limits = ("Budgets (tests/perf/budgets.env): idle CPU < %g%% per app and < %g%% in all; wakeups < %g/s; "
              "GPU < %g ms/s; RSS Sight %g, Nexus %g, Iceberg %g, index %g MB; back under %g%% CPU within %g s "
              "of a burst; RSS growth < %g%% from burst 2 to 3; shell < %g ms."
              % (budgets["IDLE_CPU_PER_APP"], budgets["IDLE_CPU_TOTAL"], budgets["IDLE_WAKEUPS_PER_APP"],
                 budgets["IDLE_GPU_MS_PER_S"], budgets["RSS_MB_Sight"], budgets["RSS_MB_Nexus"],
                 budgets["RSS_MB_Iceberg"], budgets["RSS_MB_GrandLineIndex"], budgets["DECAY_CPU"],
                 budgets["DECAY_SECONDS"], budgets["RSS_GROWTH_PCT"], budgets["SHELL_MEDIAN_MS"]))
    text = "\n".join(table)
    print(text)
    print()
    print(limits)
    for note in notes:
        print("note: " + note)
    for failure in failures:
        print("OVER BUDGET: " + failure)
    if os.environ.get("GITHUB_ACTIONS"):
        for row in rows:
            print("::notice title=budget %s::%s" % (row[0], ", ".join("%s %s" % (h, v) for h, v in zip(HEADERS[1:], row[1:]) if v)))
        for note in notes:
            print("::notice title=budgets::" + note)
        for failure in failures:
            print("::error title=over budget::" + failure)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write("## Resource budgets\n\n" + text + "\n\n" + limits + "\n\n")
            for note in notes:
                f.write("- " + note + "\n")
            f.write("\n" + ("**Over budget:**\n\n" + "\n".join("- " + x for x in failures) if failures else "All within budget.") + "\n")
    return 1 if failures else 0


def selftest():
    """The parsers, on output captured from macOS tools."""
    assert parse_cputime("0:01.50") == 1.5
    assert parse_cputime("1:02:03.00") == 3723
    assert parse_cputime("2-00:00:01") == 172801
    assert abs(parse_footprint("phys_footprint: 45 MB") - 45) < 1e-9
    assert abs(parse_footprint("Physical footprint:         12.5M") - 12.5) < 1e-9
    assert abs(parse_footprint("Footprint: 512 KB") - 0.5) < 1e-9
    pm = """*** Running tasks ***

Name                               ID     CPU ms/s  User%  Deadlines (<2 ms, 2-5 ms)  Wakeups (Intr, Pkg idle)  GPU ms/s  Energy Impact
Sight                              812    0.40      60.00  0.00    0.00              1.20    0.40              0.00      0.10
GrandLineIndex                     640    0.10      40.00  0.00    0.00              0.20    0.00              0.00      0.02
Some Other App                     100    5.00      50.00  0.00    0.00              9.00    2.00              3.00      4.00
ALL_TASKS                          -2     12.00     50.00  0.00    0.00              20.00   5.00              3.00      9.00

*** Running tasks ***

Name                               ID     CPU ms/s  User%  Deadlines (<2 ms, 2-5 ms)  Wakeups (Intr, Pkg idle)  GPU ms/s  Energy Impact
Sight                              812    0.20      60.00  0.00    0.00              0.80    0.20              0.50      0.10
"""
    got = parse_powermetrics(pm, ["Sight", "GrandLineIndex", "Iceberg"])
    assert abs(got["Sight"]["wakeups_s"] - 1.3) < 1e-9, got
    assert abs(got["Sight"]["gpu_ms_s"] - 0.25) < 1e-9, got
    assert got["Sight"]["samples"] == 2
    assert "Iceberg" not in got
    top = """Processes: 2 total
PID    %CPU IDLEW
812    0.0  0
Processes: 2 total
PID    %CPU IDLEW
812    0.1  120
640    0.0  6
"""
    wake = parse_top(top, 60)
    assert wake == {812: 2.0, 640: 0.1}, wake
    good = {"Label": "com.grandline.downloads", "WatchPaths": ["/x"], "ThrottleInterval": 20,
            "ProcessType": "Background", "LowPriorityIO": True, "StartInterval": 3600}
    assert check_agent(good) == []
    assert check_agent(dict(good, KeepAlive=True))
    assert check_agent(dict(good, ThrottleInterval=1))
    assert check_agent(dict(good, ProcessType="Interactive"))
    index = {"Label": "com.grandline.index", "KeepAlive": {"SuccessfulExit": False}, "ProcessType": "Adaptive"}
    assert check_agent(index) == []
    assert check_agent(dict(index, KeepAlive=True))
    print("measure.py selftest: ok")


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    cmd, rest = argv[0], argv[1:]

    def opt(name, default=None):
        if name in rest:
            i = rest.index(name)
            value = rest[i + 1]
            del rest[i:i + 2]
            return value
        return default

    if cmd == "selftest":
        selftest()
        return 0
    if cmd == "pids":
        write("-", {split_name(n)[0]: pids_of(n) for n in rest})
        return 0
    if cmd == "snapshot":
        write("-", snapshot(rest))
        return 0
    if cmd == "agents":
        out = opt("--out", "-")
        result = cmd_agents(rest, out)
        return 1 if any(e["problems"] for e in result.values()) else 0
    if cmd == "shell":
        zshrc, runs, out = opt("--zshrc"), int(opt("--runs", "10")), opt("--out", "-")
        cmd_shell(zshrc, runs, out)
        return 0
    if cmd == "powermetrics":
        out = opt("--out", "-")
        write(out, powermetrics(rest))
        return 0
    if cmd == "sampler":
        stop, out = opt("--stop"), opt("--out", "-")
        cmd_sampler(rest, stop, out)
        return 0
    budgets = read_budgets(opt("--budgets", os.path.join(os.path.dirname(os.path.abspath(__file__)), "budgets.env")))
    if cmd == "idle":
        cmd_idle(budgets, rest, opt("--out", "-"))
        return 0
    if cmd == "decay":
        cmd_decay(budgets, rest, opt("--out", "-"))
        return 0
    if cmd == "report":
        return cmd_report(budgets, opt("--results", "."))
    print("measure.py: unknown command " + cmd, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
