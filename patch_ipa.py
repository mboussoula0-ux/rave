#!/usr/bin/env python3
"""Patch an unpacked Rave.app folder: app name -> Layan, icons -> Layan icons.
Usage:  python3 patch_ipa.py /path/to/Payload/Rave.app [Name]
"""
import sys, os, shutil, plistlib
app = sys.argv[1]; name = sys.argv[2] if len(sys.argv) > 2 else "Layan"
here = os.path.dirname(os.path.abspath(__file__)); icons = os.path.join(here, "..", "icons")
pl = os.path.join(app, "Info.plist")
p = plistlib.load(open(pl, "rb"))
p["CFBundleDisplayName"] = name
p["CFBundleName"] = name
# Remove CFBundleIconName so iOS uses the loose PNG files instead of the icon inside Assets.car
for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
    prim = p.get(key, {}).get("CFBundlePrimaryIcon")
    if prim is not None:
        prim.pop("CFBundleIconName", None)
        files = prim.setdefault("CFBundleIconFiles", [])
        for f in ("AppIcon60x60", "AppIcon76x76", "AppIcon83.5x83.5"):
            if key == "CFBundleIcons" and f != "AppIcon60x60": continue
            if f not in files: files.append(f)
plistlib.dump(p, open(pl, "wb"), fmt=plistlib.FMT_BINARY)
for f in os.listdir(icons):
    if f.startswith("AppIcon"): shutil.copy(os.path.join(icons, f), os.path.join(app, f))
print("done: name =", name)
