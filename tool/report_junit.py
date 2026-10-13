"""Prints each failed JUnit test as a GitHub annotation (::error::).

Annotations are readable through the GitHub API even where raw logs are not.
Usage: python3 tool/report_junit.py <folder with TEST-*.xml> [gradle output log]
"""
import pathlib
import re
import sys
import xml.etree.ElementTree as ET


def esc(text: str) -> str:
    return text.replace("%", "%25").replace("\r", "").replace("\n", "%0A")


root = pathlib.Path(sys.argv[1])
failures = 0
reports = list(root.rglob("TEST-*.xml"))
print(f"report_junit: found {len(reports)} report file(s)")
for xml in reports:
    for case in ET.parse(xml).getroot().iter("testcase"):
        for problem in list(case.findall("failure")) + list(case.findall("error")):
            failures += 1
            message = (problem.get("message") or problem.text or "").strip()
            print(f"::error title=Test failed: {case.get('name')}::{esc(message[:900])}")

if failures == 0 and len(sys.argv) > 2:
    # No test reports: probably a compile error. Report Kotlin "e:" lines.
    log = pathlib.Path(sys.argv[2])
    if log.exists():
        all_lines = [l for l in log.read_text(errors="replace").splitlines() if l.strip()]
        lines = [l for l in all_lines if re.match(r"^e: ", l) or "error:" in l.lower()]
        for line in lines[:15]:
            print(f"::error title=Android build error::{esc(line[:900])}")
        # Include the end of the Gradle output when the build itself failed.
        if any("BUILD FAILED" in l for l in all_lines):
            tail = "\n".join(all_lines[-30:])
            print(f"::error title=Gradle output (last lines)::{esc(tail[-3500:])}")

total = sum(len(list(ET.parse(x).getroot().iter("testcase"))) for x in reports)
print(f"::notice title=Android unit tests::{total} run, {failures} failed")
print(f"report_junit: {failures} failed test(s)")
