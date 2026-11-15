#!/usr/bin/env python3
"""Set SELinux xattrs on files injected into a raw ext4 system image.

Files created by debugfs have no security.selinux attribute -> Android labels them
"unlabeled" and (with SELinux enforcing) blocks every reader. Google Play Services
crashes instantly in that state.

    python3 scripts/label-selinux.py \
        --img td_a15_gapps.img \
        --src gapps/ \
        --include manifests/gapps-minimal.txt

Label rules:
  * anything under lib/, lib64/, or a *.so file  -> system_lib_file
  * everything else (files and directories)      -> system_file

Use --list-only to print the plan without writing.
"""
import argparse
import os
import subprocess
import sys
import tempfile

LABELS = {
    "system_file": b"u:object_r:system_file:s0\x00",
    "system_lib_file": b"u:object_r:system_lib_file:s0\x00",
}


def read_include(path):
    roots = []
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if line and not line.startswith("#"):
                roots.append(line.strip("/"))
    if not roots:
        sys.exit(f"no paths in {path}")
    return roots


def label_for(rel_path):
    parts = rel_path.split("/")
    if "lib" in parts or "lib64" in parts or rel_path.endswith(".so"):
        return "system_lib_file"
    return "system_file"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--img", required=True)
    ap.add_argument("--src", required=True)
    ap.add_argument("--include", required=True)
    ap.add_argument("--cmdfile", default="gapps-labels.txt")
    ap.add_argument("--list-only", action="store_true")
    args = ap.parse_args()

    roots = read_include(args.include)
    seen, targets = set(), []          # (image_path, label)

    def add(fs_path, label):
        if fs_path not in seen:
            seen.add(fs_path)
            targets.append((fs_path, label))

    for root in roots:
        host_root = os.path.join(args.src, root)
        if not os.path.isdir(host_root):
            sys.exit(f"missing in --src: {host_root}")
        for dirpath, dirnames, filenames in os.walk(host_root):
            dirnames.sort()
            rel = os.path.relpath(dirpath, args.src).replace(os.sep, "/")
            add("/" + rel, label_for(rel))
            for fn in sorted(filenames):
                add(f"/{rel}/{fn}", label_for(f"{rel}/{fn}"))

    print(f"labeling {len(targets)} paths")
    counts = {}
    for _, lbl in targets:
        counts[lbl] = counts.get(lbl, 0) + 1
    for k, v in sorted(counts.items()):
        print(f"  {k}: {v}")

    if args.list_only:
        for p, l in targets:
            print(f"{l:16s} {p}")
        return

    tmpdir = tempfile.mkdtemp(prefix="sellabel-")
    valfile = {}
    for name, value in LABELS.items():
        path = os.path.join(tmpdir, name)
        with open(path, "wb") as fh:
            fh.write(value)
        valfile[name] = path

    with open(args.cmdfile, "w", encoding="utf-8") as fh:
        for path, label in targets:
            fh.write(f'ea_set -f {valfile[label]} "{path}" security.selinux\n')

    res = subprocess.run(["debugfs", "-w", "-f", args.cmdfile, args.img],
                         capture_output=True, text=True)
    out = (res.stdout + res.stderr).splitlines()
    # debugfs echoes each command from a -f file as "debugfs: ea_set ...", which is not an
    # error. Real problems look like "/path: File not found by ext2_lookup".
    bad = [l for l in out
           if not l.startswith("debugfs:")
           and ("not found" in l.lower() or "no such file" in l.lower()
                or "invalid" in l.lower() or "error" in l.lower())]
    print(f"debugfs rc={res.returncode}, problems={len(bad)}")
    for line in bad[:30]:
        print("  !", line)
    if res.returncode != 0:
        sys.exit("debugfs failed")

    print("\nverify with:")
    print(f'  debugfs -R \'ea_list "/system/product/priv-app/Phonesky/Phonesky.apk"\' {args.img}')


if __name__ == "__main__":
    main()
