#!/usr/bin/env python3
"""Replace the system UI font with a variable font, safely.

Two modes:

  # A) patch an extracted fonts.xml
  python3 scripts/patch-fonts.py --in fonts.xml --out fonts_inter.xml \
      --ttf InterVariable.ttf --family sans-serif --styles normal

  # B) do everything inside a raw ext4 image (dump, patch, write font+xml, label)
  python3 scripts/patch-fonts.py --img td_a15_gapps.img \
      --ttf InterVariable.ttf --out td_a15_ui.img

Why the axis juggling: a <font> entry that declares an axis the font does not contain
is invalid and Android falls back (or renders nothing). Inter has only 'opsz' and
'wght', so the usual Roboto entry lines for 'ital' and 'wdth' must be removed.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

TTF_TOKEN = re.compile(r"^(\s*)([A-Za-z0-9_.\-]+\.ttf)")
AXIS_LINE = re.compile(r"[\t ]*<axis\s+tag=\"([a-z0-9]+)\"[^>]*/>[\t ]*\n?")
FONT_BLOCK = re.compile(r"<font\b([^>]*)>(.*?)</font>", re.S)


def family_block(text, family):
    pat = re.compile(r'(<family\s+name="%s"[^>]*>)(.*?)(</family>)' % re.escape(family), re.S)
    m = pat.search(text)
    if not m:
        sys.exit(f'family "{family}" not found in fonts.xml')
    return m


def font_axes(ttf_path):
    """Return the set of fvar axis tags, or None if fontTools is unavailable."""
    try:
        from fontTools.ttLib import TTFont  # type: ignore
    except Exception:
        return None
    try:
        return {a.axisTag for a in TTFont(ttf_path)["fvar"].axes}
    except Exception:
        return None


def patch_xml(text, family, font_name, styles, drop_axes, verbose=True):
    m = family_block(text, family)
    head, body, tail = m.group(1), m.group(2), m.group(3)
    changed = 0

    def repl(mo):
        nonlocal changed
        attrs, inner = mo.group(1), mo.group(2)
        style_m = re.search(r'style="([^"]+)"', attrs)
        style = style_m.group(1) if style_m else "normal"
        if styles == "normal" and style != "normal":
            return mo.group(0)

        tm = TTF_TOKEN.match(inner)
        if not tm:
            return mo.group(0)

        indent, _old = tm.group(1), tm.group(2)
        new_inner = TTF_TOKEN.sub(lambda t: t.group(1) + font_name, inner, count=1)

        def axis_repl(am):
            return "" if am.group(1) in drop_axes else am.group(0)

        new_inner = AXIS_LINE.sub(axis_repl, new_inner)
        changed += 1
        return f"<font{attrs}>{new_inner}</font>"

    new_body = FONT_BLOCK.sub(repl, body)
    if changed == 0:
        sys.exit(f"no matching <font> entries patched in family {family}")

    out = text[:m.start(2)] + new_body + text[m.end(2):]
    # nothing else should reference the old file inside this family
    if verbose:
        print(f"patched {changed} entries -> {font_name}")
        print(f"  refs {font_name}: {out.count(font_name)}")
        print(f"  refs Roboto-Regular.ttf: {out.count('Roboto-Regular.ttf')}")
    if "Roboto-Regular.ttf</font>" in new_body:
        print("  warn: some sans-serif entries still point at Roboto")
    return out


def validate(path):
    import xml.dom.minidom
    xml.dom.minidom.parse(path)


def debugfs(args, img):
    return subprocess.run(["debugfs", "-w"] + args + [img],
                          capture_output=True, text=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--in", dest="inp", help="existing fonts.xml (mode A)")
    ap.add_argument("--out", help="output fonts.xml (mode A) or output image (mode B)")
    ap.add_argument("--img", help="raw ext4 image to edit in place (mode B)")
    ap.add_argument("--ttf", required=True, help="host path to the variable font file")
    ap.add_argument("--family", default="sans-serif")
    ap.add_argument("--styles", choices=["normal", "all"], default="normal")
    ap.add_argument("--drop-axes", default="ital,wdth",
                    help="comma list of axis tags to drop (default: ital,wdth)")
    ap.add_argument("--fonts-dir", default="/system/fonts")
    ap.add_argument("--dump-xml", help="with --img: also save the original fonts.xml here")
    args = ap.parse_args()

    if not os.path.isfile(args.ttf):
        sys.exit(f"font not found: {args.ttf}")
    font_name = os.path.basename(args.ttf)

    drop = {a.strip() for a in args.drop_axes.split(",") if a.strip()}
    axes = font_axes(args.ttf)
    if axes is not None:
        print(f"font axes: {sorted(axes)}")
        not_in_font = drop - axes
        if not_in_font:
            print(f"  note: {sorted(not_in_font)} not present in font; dropping is safe")
        # never drop an axis the font actually needs if user replaced the list
        if "wght" in drop:
            sys.exit("refusing to drop the 'wght' axis")

    # ---------- mode A ----------
    if not args.img:
        if not args.inp or not args.out:
            sys.exit("mode A needs --in and --out")
        with open(args.inp, encoding="utf-8") as fh:
            text = fh.read()
        out = patch_xml(text, args.family, font_name, args.styles, drop)
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(out)
        validate(args.out)
        print(f"Wrote {args.out} ({len(out)} bytes), XML OK")
        return

    # ---------- mode B ----------
    img = args.img
    if args.out and args.out != img:
        print(f"copying {img} -> {args.out}")
        shutil.copyfile(img, args.out)
        img = args.out

    tmpdir = tempfile.mkdtemp(prefix="fontpatch-")
    orig = os.path.join(tmpdir, "fonts.xml")
    patched = os.path.join(tmpdir, "fonts_inter.xml")

    res = debugfs(["-R", f"dump /system/etc/fonts.xml {orig}"], img)
    if not os.path.isfile(orig) or os.path.getsize(orig) == 0:
        sys.exit(f"could not dump /system/etc/fonts.xml from {img}\n{res.stdout}{res.stderr}")

    if args.dump_xml:
        shutil.copyfile(orig, args.dump_xml)
        print(f"original fonts.xml -> {args.dump_xml}")

    with open(orig, encoding="utf-8") as fh:
        text = fh.read()
    out = patch_xml(text, args.family, font_name, args.styles, drop)
    with open(patched, "w", encoding="utf-8") as fh:
        fh.write(out)
    validate(patched)

    target_font = f"{args.fonts_dir.rstrip('/')}/{font_name}"
    print(f"writing {target_font}")
    debugfs(["-R", f"write {args.ttf} {target_font}"], img)
    debugfs(["-R", "rm /system/etc/fonts.xml"], img)
    r2 = debugfs(["-R", f"write {patched} /system/etc/fonts.xml"], img)
    if r2.returncode != 0:
        print(r2.stdout, r2.stderr)

    # label both files (see docs/07)
    val = os.path.join(tmpdir, "sel_system_file")
    with open(val, "wb") as fh:
        fh.write(b"u:object_r:system_file:s0\x00")
    for p in (target_font, "/system/etc/fonts.xml"):
        debugfs(["-R", f'ea_set -f {val} "{p}" security.selinux'], img)

    print("done. verify on device with:")
    print(f"  adb shell 'grep -c {font_name} /system/etc/fonts.xml'")


if __name__ == "__main__":
    main()
