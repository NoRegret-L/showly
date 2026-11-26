#!/usr/bin/env python3
"""Validate build provenance and prepare a non-production unsigned preview."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import zipfile


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def main():
    p = argparse.ArgumentParser()
    for name in ("source", "hap-dir", "upstream", "output"):
        p.add_argument("--" + name, type=Path, required=True)
    p.add_argument("--commit", required=True)
    p.add_argument("--run", required=True)
    args = p.parse_args()
    root = args.source / "harmonyos"
    app = load_json(root / "AppScope/app.json5")["app"]
    version, code = app["versionName"], app["versionCode"]
    require(isinstance(version, str) and re.fullmatch(r"\d+\.\d+\.\d+(?:\.\d+)?", version), "Invalid version")
    require(type(code) is int and 0 < code <= 2147483647, "Invalid versionCode")
    require(app["bundleName"] == "com.noregret.showly.harmony", "Unexpected bundle")
    require(load_json(root / "package.json")["version"] == version, "Project version mismatch")
    require(load_json(root / "entry/oh-package.json5")["version"] == version, "Module version mismatch")
    require(load_json(root / "build-profile.json5")["app"]["signingConfigs"] == [], "Expected unsigned preview")
    baseline = (root / "upstream-baseline.txt").read_text().strip()
    info = (root / "entry/src/main/ets/config/BuildInfo.ets").read_text()
    require(f"APP_VERSION: string = '{version}';" in info, "Update version mismatch")
    require(f"APP_VERSION_CODE: number = {code};" in info, "Update versionCode mismatch")
    require(f"UPSTREAM_BASELINE: string = '{baseline}';" in info, "Upstream baseline mismatch")
    revision = args.upstream.read_text().strip().split()
    require(len(revision) == 2 and revision[1] == "refs/heads/master", "Unexpected upstream record")
    upstream = revision[0]
    for sha in (baseline, upstream, args.commit):
        require(re.fullmatch(r"[0-9a-f]{40}", sha), "Invalid source SHA")
    require(re.fullmatch(r"[1-9][0-9]*", args.run), "Invalid build run ID")
    candidates = [x for x in args.hap_dir.rglob("*.hap") if x.is_file() and not x.is_symlink()]
    require(len(candidates) == 1, "Expected exactly one HAP, no ambiguous signed/unsigned choice")
    hap = candidates[0]
    require(hap.stat().st_size > 0, "Empty HAP")
    with zipfile.ZipFile(hap) as archive:
        require(archive.testzip() is None, "Corrupt HAP")
        require("module.json" in archive.namelist(), "Missing HAP module manifest")
        module = json.loads(archive.read("module.json"))
        manifest = module.get("app", {})
        require(manifest.get("bundleName") == app["bundleName"], "HAP bundle mismatch")
        require(manifest.get("versionCode") == code and manifest.get("versionName") == version, "HAP version mismatch")
    tag = f"harmonyos-v{version}-b{code}"
    args.output.mkdir(parents=True, exist_ok=True)
    name = f"showly-{tag}-unsigned.hap"
    target = args.output / name
    shutil.copyfile(hap, target)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    (args.output / "SHA256SUMS.txt").write_text(f"{digest}  {name}\n")
    metadata = {
        "version": version, "versionCode": code, "bundleName": app["bundleName"],
        "tag": tag, "commit": args.commit, "upstreamRevision": upstream,
        "upstreamObservationBaseline": baseline, "upstreamChanged": upstream != baseline,
        "buildRun": args.run, "signed": False, "asset": name,
        "bytes": target.stat().st_size, "sha256": digest,
    }
    (args.output / "release-info.json").write_text(json.dumps(metadata, indent=2) + "\n")
    (args.output / "release-notes.md").write_text(
        f"Experimental unsigned personal-use HarmonyOS HAP {version} (versionCode {code}).\n\n"
        "Not a production-signed app or a device-tested guarantee. Use your existing installation method; "
        "preserve application data and verify SHA256SUMS.txt. No bundled Trakt API credentials.\n\n"
        f"Native source: {args.commit}\n\nAndroid upstream observed: {upstream}\n\n"
        f"Observation baseline: {baseline} (not proof of port coverage).\n\n"
        f"Build: https://github.com/NoRegret-L/showly/actions/runs/{args.run}\n"
    )
    print(f"tag={tag}")


if __name__ == "__main__":
    main()
