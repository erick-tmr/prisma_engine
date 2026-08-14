#!/usr/bin/env python3

"""Render the TSV records emitted by deploy/vps-healthcheck.remote.sh into a
self-contained HTML report. Reads records on stdin, writes to $HTML_PATH."""

import html, os, sys

rows, meta = [], {}
for line in sys.stdin.read().splitlines():
    if not line.strip():
        continue
    parts = line.split("\t")
    if parts[0] == "meta" and len(parts) >= 3:
        meta[parts[1]] = "\t".join(parts[2:]).strip()
        continue
    if len(parts) < 3:
        continue
    section, status, name = parts[0], parts[1], parts[2]
    detail = "\t".join(parts[3:]) if len(parts) > 3 else ""
    rows.append((section, status, name, detail))

ok, warn, fail = 0, 0, 0
for _, status, _, _ in rows:
    if status == "OK":
        ok += 1
    elif status == "WARN":
        warn += 1
    elif status == "FAIL":
        fail += 1

verdict, verdict_class = ("All clear", "ok")
if fail:
    verdict, verdict_class = ("Action required", "fail")
elif warn:
    verdict, verdict_class = ("Warnings", "warn")

# A record whose name starts with "- " is a continuation of the one above it: the terminal
# prints it as its own indented line, the report folds it into the parent row so a failing
# job and everything known about it read as one block.
sections = []
for section, status, name, detail in rows:
    if not sections or sections[-1][0] != section:
        sections.append((section, []))
    entries = sections[-1][1]
    if name.startswith("- ") and entries:
        entries[-1][3].append((name[2:], detail))
    else:
        entries.append([status, name, detail, []])

LABEL = {"OK": "OK", "WARN": "WARN", "FAIL": "FAIL", "INFO": "INFO"}
CLASS = {"OK": "ok", "WARN": "warn", "FAIL": "fail", "INFO": "info"}

def esc(value):
    return html.escape(value, quote=True)

parts = ["""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>VPS health check | Prisma Games</title>
<style>
:root {
  --bg: #f7f7f5; --card: #fff; --ink: #1b1b1a; --muted: #6b6b66; --line: #e2e2dd;
  --ok: #1a7f4b; --ok-bg: #e7f4ec; --warn: #8a6100; --warn-bg: #fdf3dc;
  --fail: #a32020; --fail-bg: #fbeaea; --info: #4a5568; --info-bg: #eef0f3;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #16171a; --card: #1e2024; --ink: #e8e8e6; --muted: #9a9a94; --line: #2e3036;
    --ok: #57c98a; --ok-bg: #17301f; --warn: #e0b356; --warn-bg: #322611;
    --fail: #ef7676; --fail-bg: #331919; --info: #a8b3c2; --info-bg: #232830;
  }
}
* { box-sizing: border-box; }
body { margin: 0; padding: 2rem 1rem 4rem; background: var(--bg); color: var(--ink);
  font: 15px/1.55 ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
.wrap { max-width: 1000px; margin: 0 auto; }
h1 { font-size: 1.5rem; margin: 0 0 .25rem; letter-spacing: -.01em; }
.sub { color: var(--muted); font-size: .875rem; margin: 0 0 1.5rem; }
.sub code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
.verdict { display: inline-block; padding: .3rem .7rem; border-radius: 999px;
  font-weight: 650; font-size: .8rem; letter-spacing: .02em; }
.verdict.ok { background: var(--ok-bg); color: var(--ok); }
.verdict.warn { background: var(--warn-bg); color: var(--warn); }
.verdict.fail { background: var(--fail-bg); color: var(--fail); }
.tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
  gap: .75rem; margin: 1.25rem 0 2rem; }
.tile { background: var(--card); border: 1px solid var(--line); border-radius: 10px;
  padding: .9rem 1rem; }
.tile .n { font-size: 1.75rem; font-weight: 680; line-height: 1; }
.tile .l { color: var(--muted); font-size: .75rem; text-transform: uppercase;
  letter-spacing: .06em; margin-top: .35rem; }
.tile.ok .n { color: var(--ok); } .tile.warn .n { color: var(--warn); }
.tile.fail .n { color: var(--fail); }
section { background: var(--card); border: 1px solid var(--line); border-radius: 10px;
  margin-bottom: 1rem; overflow: hidden; }
section h2 { margin: 0; padding: .7rem 1rem; font-size: .78rem; letter-spacing: .08em;
  text-transform: uppercase; color: var(--muted); border-bottom: 1px solid var(--line); }
table { width: 100%; border-collapse: collapse; }
td { padding: .55rem 1rem; border-bottom: 1px solid var(--line); vertical-align: top; }
tr:last-child td { border-bottom: none; }
td.s { width: 4.5rem; }
td.n { width: 15rem; font-weight: 560; }
td.d { color: var(--muted); font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: .82rem; word-break: break-word; }
td.d .lead { color: var(--ink); }
dl.sub { display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: .3rem .9rem;
  margin: .5rem 0 0; padding: .1rem 0 .1rem .8rem; border-left: 2px solid var(--line); }
dl.sub dt { font-family: ui-sans-serif, system-ui, sans-serif; font-size: .68rem;
  text-transform: uppercase; letter-spacing: .07em; color: var(--muted); padding-top: .15rem; }
dl.sub dd { margin: 0; }
.pill { display: inline-block; min-width: 3.2rem; text-align: center; padding: .12rem .45rem;
  border-radius: 5px; font-size: .7rem; font-weight: 700; letter-spacing: .04em; }
.pill.ok { background: var(--ok-bg); color: var(--ok); }
.pill.warn { background: var(--warn-bg); color: var(--warn); }
.pill.fail { background: var(--fail-bg); color: var(--fail); }
.pill.info { background: var(--info-bg); color: var(--info); }
tr.warn td.n, tr.fail td.n { color: var(--ink); }
footer { color: var(--muted); font-size: .78rem; margin-top: 2rem; }
@media print { body { background: #fff; } section { break-inside: avoid; } }
</style></head><body><div class="wrap">"""]

parts.append("<h1>VPS health check</h1>")
parts.append(
    '<p class="sub"><code>{host}</code> &middot; {generated} &middot; {window}h log window'
    ' &middot; uptime {uptime}</p>'.format(
        host=esc(os.environ.get("REPORT_HOST", "")),
        generated=esc(meta.get("generated", "")),
        window=esc(meta.get("window", "")),
        uptime=esc(meta.get("uptime", "unknown")),
    )
)
parts.append(f'<p><span class="verdict {verdict_class}">{esc(verdict)}</span></p>')

parts.append('<div class="tiles">')
for count, label, cls in ((ok, "passing", "ok"), (warn, "warnings", "warn"), (fail, "failures", "fail")):
    parts.append(f'<div class="tile {cls}"><div class="n">{count}</div><div class="l">{label}</div></div>')
parts.append("</div>")

for section, entries in sections:
    parts.append(f"<section><h2>{esc(section)}</h2><table><tbody>")
    for status, name, detail, children in entries:
        cls = CLASS.get(status, "info")
        cell = esc(detail)
        if children:
            cell = f'<div class="lead">{cell}</div><dl class="sub">' + "".join(
                f"<dt>{esc(label)}</dt><dd>{esc(value)}</dd>" for label, value in children
            ) + "</dl>"
        parts.append(
            f'<tr class="{cls}"><td class="s"><span class="pill {cls}">{LABEL.get(status, status)}</span></td>'
            f'<td class="n">{esc(name)}</td><td class="d">{cell}</td></tr>'
        )
    parts.append("</tbody></table></section>")

parts.append(
    '<footer>Generated by <code>deploy/vps-healthcheck.sh</code>. Read-only: no check '
    "mutates the box. Runbook: <code>docs/vps-healthcheck.md</code>.</footer>"
)
parts.append("</div></body></html>")

with open(os.environ["HTML_PATH"], "w") as fh:
    fh.write("\n".join(parts))
