"""Registers the app's bundled fonts in a freshly generated pubspec.yaml.

Run from the generated project folder:  python3 ../tool/patch_pubspec.py
Fails loudly if the template changed, so a build never ships without fonts.
"""
import pathlib
import re
import sys

path = pathlib.Path("pubspec.yaml")
text = path.read_text()

if "family: Manrope" in text:
    print("patch_pubspec: fonts already registered")
    sys.exit(0)

FONTS = """  assets:
    - assets/images/logo.png
  fonts:
    - family: Manrope
      fonts:
        - asset: assets/fonts/Manrope-Regular.ttf
          weight: 400
        - asset: assets/fonts/Manrope-Medium.ttf
          weight: 500
        - asset: assets/fonts/Manrope-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Manrope-Bold.ttf
          weight: 700
        - asset: assets/fonts/Manrope-ExtraBold.ttf
          weight: 800
"""

# The top-level "flutter:" section (not the indented "flutter:" under dependencies).
text, n = re.subn(r"(?m)^flutter:[ \t]*\n", lambda m: m.group(0) + FONTS, text, count=1)
if n != 1:
    print("patch_pubspec: no top-level 'flutter:' section in pubspec.yaml", file=sys.stderr)
    sys.exit(1)

path.write_text(text)
print("patch_pubspec: Manrope registered")
