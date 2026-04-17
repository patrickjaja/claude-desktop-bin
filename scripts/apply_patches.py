#!/usr/bin/env python3
"""
Apply all patches in patches/ to the extracted app directory.

Runs every patch script inside a single Python process via runpy, instead of
spawning a fresh interpreter per patch. For patches that target the same file
(the vast majority target .vite/build/index.js), we stage the file once on
tmpfs and all patches mutate it in place there, so each patch still opens and
writes "its file" exactly the way it does standalone — but the underlying disk
round-trip only happens once per target.

Usage: apply_patches.py <patches_dir> <app_dir>

<app_dir> is the directory that contains app.asar.contents/, i.e. the same
path that build-patched-tarball.sh uses as "$WORK_DIR/app".
"""
import os
import re
import runpy
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HEADER_RE = re.compile(r"@patch-(target|type):\s*(\S+)")

# Location of compiled Nim patch binaries. If a patches-nim/<name> binary
# exists and is executable, we run that instead of the Python script —
# roughly 10× faster on the minified-JS regex workload.
NIM_DIR = Path(__file__).resolve().parent.parent / "patches-nim"


def parse_headers(path: Path):
    try:
        text = path.read_text(errors="ignore")
    except Exception:
        return None, None
    target = ptype = None
    for m in HEADER_RE.finditer(text):
        key, value = m.group(1), m.group(2)
        if key == "target" and target is None:
            target = value
        elif key == "type" and ptype is None:
            ptype = value
        if target and ptype:
            break
    return target, ptype


def resolve_target(app_dir: Path, target_spec: str):
    rel = Path(target_spec)
    if "*" in target_spec:
        base = app_dir / rel.parent
        matches = sorted(base.glob(rel.name))
        return matches[0] if matches else None
    return app_dir / rel


def run_patch(patch_file: Path, target_file: Path) -> bool:
    """Execute a patch. Prefer the compiled Nim binary when one exists;
    otherwise fall back to the Python script via runpy."""
    nim_bin = NIM_DIR / patch_file.stem
    if nim_bin.is_file() and os.access(nim_bin, os.X_OK):
        try:
            subprocess.run([str(nim_bin), str(target_file)], check=True)
            return True
        except subprocess.CalledProcessError as e:
            print(f"  [FAIL] {nim_bin.name} (nim) exited with code {e.returncode}", file=sys.stderr)
            return False

    saved_argv = sys.argv
    sys.argv = [str(patch_file), str(target_file)]
    try:
        runpy.run_path(str(patch_file), run_name="__main__")
        return True
    except SystemExit as e:
        code = e.code
        if code is None or code == 0:
            return True
        print(f"  [FAIL] {patch_file.name} exited with code {code}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"  [FAIL] {patch_file.name}: {e!r}", file=sys.stderr)
        return False
    finally:
        sys.argv = saved_argv


def main():
    if len(sys.argv) != 3:
        print("Usage: apply_patches.py <patches_dir> <app_dir>", file=sys.stderr)
        sys.exit(1)
    patches_dir = Path(sys.argv[1]).resolve()
    app_dir = Path(sys.argv[2]).resolve()

    if not patches_dir.is_dir():
        print(f"[ERROR] patches_dir not found: {patches_dir}", file=sys.stderr)
        sys.exit(1)
    if not app_dir.is_dir():
        print(f"[ERROR] app_dir not found: {app_dir}", file=sys.stderr)
        sys.exit(1)

    replace_jobs = []                   # list[(patch_file, real_target)]
    python_jobs_by_target = {}          # real_target -> list[patch_file]
    skipped = []                        # files with no/unknown headers

    for patch_file in sorted(patches_dir.iterdir()):
        if not patch_file.is_file():
            continue
        target_spec, ptype = parse_headers(patch_file)
        if not target_spec or not ptype:
            skipped.append(patch_file.name)
            continue

        if ptype == "replace":
            replace_jobs.append((patch_file, app_dir / target_spec))
        elif ptype == "python":
            real = resolve_target(app_dir, target_spec)
            if real is None or not real.is_file():
                print(
                    f"[ERROR] Target not found for {patch_file.name}: {target_spec}",
                    file=sys.stderr,
                )
                sys.exit(1)
            python_jobs_by_target.setdefault(real, []).append(patch_file)
        else:
            print(f"  [WARN] Unknown @patch-type '{ptype}' for {patch_file.name}")

    if skipped:
        # Not an error — patches/ may contain helper files without headers
        # (shared JS snippets have moved under js/, loaded by other patches).
        print(f"  Skipping {len(skipped)} file(s) without patch headers: {', '.join(skipped)}")

    failed = False

    for patch_file, target_path in replace_jobs:
        target_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(patch_file, target_path)
        print(f"  Applied replace: {patch_file.name} -> {target_path.relative_to(app_dir)}")

    # Pick a tmpfs staging dir if we can — keeps the per-patch open/read/write
    # sequence off the real disk.
    # staging_root = "/dev/shm" if os.path.isdir("/dev/shm") else None
    staging_root = None
    for target_path, patches in python_jobs_by_target.items():
        rel = target_path.relative_to(app_dir)
        print(f"\n=== Patching {rel} ({len(patches)} patch{'es' if len(patches) != 1 else ''}) ===")

        with tempfile.NamedTemporaryFile(
            prefix="apply_patches_",
            suffix=target_path.suffix,
            dir=staging_root,
            delete=False,
        ) as tmp:
            staged = Path(tmp.name)
            tmp.write(target_path.read_bytes())

        try:
            group_failed = False
            for patch_file in patches:
                if not run_patch(patch_file, staged):
                    group_failed = True
                    failed = True

            if not group_failed:
                shutil.copy(staged, target_path)
            else:
                print(f"  [SKIP-WRITE] {rel} not updated due to patch failure")
        finally:
            try:
                staged.unlink()
            except FileNotFoundError:
                pass

    if failed:
        print("\n[ERROR] One or more patches failed", file=sys.stderr)
        sys.exit(1)

    print("\nAll patches applied successfully.")


if __name__ == "__main__":
    main()
