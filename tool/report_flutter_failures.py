"""Turns failures in a `flutter test --reporter json` log into GitHub
annotations, so the error text is visible on the run page.

Flutter prints the useful part ("EXCEPTION CAUGHT BY ...") as test output,
so printed messages are collected per test and included with each failure.

Usage: python3 tool/report_flutter_failures.py <json-log> <title>
"""
import json
import sys

path, title = sys.argv[1], sys.argv[2]
names = {}
prints = {}
failures = []
for line in open(path, encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        event = json.loads(line)
    except ValueError:
        continue
    kind = event.get("type")
    if kind == "testStart":
        names[event["test"]["id"]] = event["test"]["name"]
    elif kind == "print":
        prints.setdefault(event.get("testID"), []).append(event.get("message", ""))
    elif kind == "error":
        failures.append(event)


def exception_text(test_id):
    """First 'EXCEPTION CAUGHT' block printed by this test, trimmed."""
    text = "\n".join(prints.get(test_id, []))
    start = text.find("EXCEPTION CAUGHT")
    if start < 0:
        return text[:1500]
    block = text[start:]
    lines = [l for l in block.splitlines() if l.strip()]
    return "\n".join(lines[:28])[:2600]


seen = set()
reported = 0
for event in failures:
    test_id = event.get("testID")
    detail = exception_text(test_id) or (event.get("error") or "")
    key = detail[:400]
    if key in seen or reported >= 9:
        continue
    seen.add(key)
    body = f"[{names.get(test_id, '?')}] {detail}"
    body = body.replace("%", "%25").replace("\r", "").replace("\n", "%0A")
    print(f"::error title={title}::{body}")
    reported += 1

print(f"{reported} distinct failure(s) reported")
