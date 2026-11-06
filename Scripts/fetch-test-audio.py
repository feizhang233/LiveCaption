#!/usr/bin/env python3
"""Optional developer-only FLEURS fixture fetcher; never used by the App.

Streams pinned public archives, retains only the selected speech clips, and
checks the committed SHA-256 values. Requires only Python's standard library and
macOS curl. Default destination is /tmp, outside the source tree.
"""
import argparse
import hashlib
import json
import pathlib
import subprocess
import sys
import tarfile


def main():
    project = pathlib.Path(__file__).resolve().parent.parent
    manifest = json.loads((project / "Tests/Fixtures/manifest.json").read_text())
    languages = sorted({fixture["language"] for fixture in manifest})
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", nargs="?", default="/tmp/live-caption-verification-audio")
    parser.add_argument("--language", action="append", choices=languages,
                        help="Fetch only this language; repeat for multiple languages. Defaults to all.")
    args = parser.parse_args()
    selected = [fixture for fixture in manifest if not args.language or fixture["language"] in args.language]
    destination = pathlib.Path(args.destination)
    destination.mkdir(parents=True, exist_ok=True)
    archives = {}
    for fixture in selected:
        output = destination / pathlib.Path(fixture["path"]).name
        if output.is_file() and hashlib.sha256(output.read_bytes()).hexdigest() == fixture["audioSHA256"]:
            print(f"Reused verified {output}", flush=True)
            continue
        archives.setdefault(fixture["archiveURL"], {})[fixture["originalFileName"]] = fixture
    for url, expected in archives.items():
        remaining = dict(expected)
        transfer = subprocess.Popen(["curl", "-fLsS", url], stdout=subprocess.PIPE)
        try:
            with tarfile.open(fileobj=transfer.stdout, mode="r|gz") as archive:
                for member in archive:
                    name = pathlib.PurePosixPath(member.name).name
                    if not member.isfile() or name not in remaining:
                        continue
                    fixture = remaining[name]
                    if member.size > 4_000_000:
                        raise ValueError("Fixture exceeds expected small clip size")
                    audio = archive.extractfile(member).read()
                    digest = hashlib.sha256(audio).hexdigest()
                    if digest != fixture["audioSHA256"]:
                        raise ValueError(f"Checksum mismatch: {name}")
                    output = destination / pathlib.Path(fixture["path"]).name
                    # Never leave a truncated file under the reusable final name.
                    temporary = output.with_suffix(output.suffix + ".download")
                    temporary.write_bytes(audio)
                    temporary.replace(output)
                    print(f"Verified {output}: {fixture['durationSeconds']}s, {digest}", flush=True)
                    del remaining[name]
                    if not remaining:
                        break
            if remaining:
                raise ValueError(f"Missing fixtures: {list(remaining)}")
        finally:
            # Deliberately stop the archive transfer after the required clips.
            transfer.kill()
            transfer.wait()
    # Keep a complete catalog with paths reflecting this destination. Files for
    # unselected languages may not exist yet; filtering never rewrites source data.
    local_manifest = [dict(fixture, path=str(destination / pathlib.Path(fixture["path"]).name)) for fixture in manifest]
    (destination / "fixtures.json").write_text(json.dumps(local_manifest, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
