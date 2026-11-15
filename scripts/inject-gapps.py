#!/usr/bin/env python3
"""Inject a GApps (or any) tree into a raw ext4 system image using debugfs.

No mount, no root, no loop devices.

    python3 scripts/inject-gapps.py \
        --img td_a15_arm64-ab-vanilla.img \
        --src gapps/ \
        --include manifests/gapps-minimal.txt \
        --out td_a15_gapps.img

Paths in --include are relative to --src. '#' starts a comment.
Run label-selinux.py afterwards (mandatory for Google apps).
"""
import argparse
import os
import shutil
import subprocess
import sys


def read_include(path):
    roots = []
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            roots.append(line.strip("/"))
    if not roots:
        sys.exit(f"no paths in {path}")
    return roots


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--img", required=True, help="raw ext4 system image (modified in place)")
    ap.add_argument("--src", required=True, help="directory containing system/...")
    ap.add_argument("--include", required=True, help="file listing roots relative to --src")
    ap.add_argument("--out", help="copy --img to this path first, then modify the copy")
    ap.add_argument("--cmdfile", default="gapps-debugfs.txt", help="debugfs script output")
    ap.add_argument("--dry-run", action="store_true", help="generate the script but do not run")
    args = ap.parse_args()

    if not os.path.isfile(args.img):
        sys.exit(f"image not found: {args.img}")

    img = args.img
    if args.out:
        if os.path.exists(args.out) and not args.out.endswith(".tmp"):
            sys.exit(f"refusing to overwrite {args.out}")
        print(f"copying {img} -> {args.out}")
        shutil.copyfile(img, args.out)
        img = args.out

    roots = read_include(args.include)
    missing = [r for r in roots if not os.path.isdir(os.path.join(args.src, r))]
    if missing:
        sys.exit("missing in --src:\n  " + "\n  ".join(missing))

    cmds, made_dirs, files, links = [], set(), 0, 0

    def mkdirs(target):
        parts = target.strip("/").split("/")
        for i in range(1, len(parts) + 1):
            d = "/" + "/".join(parts[:i])
            if d not in made_dirs:
                made_dirs.add(d)
                cmds.append(f'mkdir "{d}"')

    for root in roots:
        host_root = os.path.join(args.src, root)
        for dirpath, dirnames, filenames in os.walk(host_root):
            dirnames.sort()
            rel = os.path.relpath(dirpath, args.src).replace(os.sep, "/")
            target = "/" + rel
            mkdirs(target)
            for fn in sorted(filenames):
                hp = os.path.join(dirpath, fn)
                tp = target + "/" + fn
                if os.path.islink(hp):
                    cmds.append(f'symlink "{tp}" "{os.readlink(hp)}"')
                    links += 1
                else:
                    cmds.append(f'write "{hp}" "{tp}"')
                    files += 1

    with open(args.cmdfile, "w", encoding="utf-8") as fh:
        fh.write("\n".join(cmds) + "\n")

    print(f"{files} files, {links} symlinks, {len(made_dirs)} dirs, {len(cmds)} commands")
    print(f"debugfs script: {args.cmdfile}")

    if args.dry_run:
        print("dry run: not executing")
        return

    res = subprocess.run(["debugfs", "-w", "-f", args.cmdfile, img],
                         capture_output=True, text=True)
    out = (res.stdout + res.stderr).splitlines()
    bad = [l for l in out
           if any(k in l.lower() for k in ("error", "failed", "not found", "invalid"))]
    exists = [l for l in out if "exists" in l.lower()]
    print(f"debugfs rc={res.returncode}, lines={len(out)}, "
          f"suspicious={len(bad)}, exists={len(exists)}")
    for line in bad[:40]:
        print("  !", line)
    if res.returncode != 0:
        sys.exit("debugfs failed")

    print("\nNEXT STEP (mandatory): python3 scripts/label-selinux.py "
          f"--img {img} --src {args.src} --include {args.include}")


if __name__ == "__main__":
    main()
