"""Turns failures in a `flutter test --reporter json` log into GitHub
annotations, so the error text is visible on the run page.

Usage: python3 tool/report_flutter_failures.py <json-log> <title>
"""
import json
import sys

path, title = sys.argv[1], sys.argv[2]
names = {}
reported = 0
seen = set()
for line in open(path, encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        event = json.loads(line)
    except ValueError:
        continue
    if event.get("type") == "testStart":
        names[event["test"]["id"]] = event["test"]["name"]
    if event.get("type") == "error" and reported < 9:
        message = (event.get("error") or "").strip()
        key = message[:300]
        if key in seen:
            continue
        seen.add(key)
        test = names.get(event.get("testID"), "?")
        stack = (event.get("stackTrace") or "").strip().splitlines()[:6]
        body = f"[{test}] {message[:1500]}\n" + "\n".join(stack)
        body = body.replace("%", "%25").replace("\r", "").replace("\n", "%0A")
        print(f"::error title={title}::{body}")
        reported += 1

print(f"{reported} distinct failure(s) reported")
