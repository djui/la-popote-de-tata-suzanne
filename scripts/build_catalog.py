#!/usr/bin/env python3
"""Builds Popote/Resources/Localizable.xcstrings (source: French) from the strings the compiler extracted.

English comes from, in order: scripts/translations_en.json (hand-maintained overrides), then the website's
own translations (docs/spec/i18n/fr_to_en.json). Prints the keys still missing an English translation.
Usage: build the app first (SWIFT_EMIT_LOC_STRINGS=YES), then: python3 scripts/build_catalog.py build/dd
"""
import json, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent
dd = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else root / "build/dd")
keys = {}
for f in dd.rglob("*.stringsdata"):
    if not any(t in str(f) for t in ("/Popote.build/", "/PopoteWidgets.build/")):
        continue
    data = json.loads(f.read_text())
    for table, entries in data.get("tables", {}).items():
        if table != "Localizable":
            continue
        for e in entries:
            keys.setdefault(e["key"], e.get("comment"))

web = json.loads((root / "docs/spec/i18n/fr_to_en.json").read_text())
over_path = root / "scripts/translations_en.json"
over = json.loads(over_path.read_text()) if over_path.exists() else {}

def to_web_form(key):
    # Swift format specifiers (%@, %lld, %1$@…) vs i18next {{x}}: compare with placeholders stripped.
    return re.sub(r"%(\d+\$)?(lld|ld|d|@|f|\.\d+f)", "{}", key)

web_norm = {re.sub(r"\{\{\w+\}\}", "{}", k): v for k, v in web.items()}

strings, missing = {}, []
for key in sorted(keys):
    if not re.search(r"[A-Za-zÀ-ÿ]", key):
        strings[key] = {"shouldTranslate": False}
        continue
    en = over.get(key) or web.get(key)
    if en is None and to_web_form(key) in web_norm:
        en = web_norm[to_web_form(key)]
        if "{{" in en:
            en = None  # placeholder order may differ; leave for a manual translation
    entry = {}
    if keys[key]:
        entry["comment"] = keys[key]
    if en:
        entry["localizations"] = {"en": {"stringUnit": {"state": "translated", "value": en}}}
    else:
        missing.append(key)
    strings[key] = entry

catalog = {"sourceLanguage": "fr", "strings": strings, "version": "1.0"}
out = root / "Popote/Resources/Localizable.xcstrings"
out.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
print(f"{len(keys)} keys, {len(missing)} missing English")
(root / "build/missing_en.json").write_text(json.dumps({k: "" for k in missing}, ensure_ascii=False, indent=1))
