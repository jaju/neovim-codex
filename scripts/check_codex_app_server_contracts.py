#!/usr/bin/env python3
"""Check the watched Codex app-server schema surface for drift.

Usage:
  python3 scripts/check_codex_app_server_contracts.py

  python3 scripts/check_codex_app_server_contracts.py \
    --codex-repo /path/to/codex

  python3 scripts/check_codex_app_server_contracts.py \
    --schema-dir /path/to/schema/typescript

  python3 scripts/check_codex_app_server_contracts.py \
    --generate

  python3 scripts/check_codex_app_server_contracts.py \
    --schema-dir /path/to/schema/typescript \
    --update
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

CODEX_REPO_ENV = "CODEX_REPO_ROOT"
CODEX_SCHEMA_SUBDIR = Path("codex-rs/app-server-protocol/schema/typescript")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--codex-repo",
        type=Path,
        help=f"Path to the Codex checkout root. Defaults to ${CODEX_REPO_ENV} when set.",
    )
    parser.add_argument(
        "--schema-dir",
        type=Path,
        help="Path to a generated TypeScript schema root containing v2/",
    )
    parser.add_argument(
        "--generate",
        action="store_true",
        help="Generate TypeScript schema with the local codex binary instead of reading an existing schema directory.",
    )
    parser.add_argument(
        "--codex-binary",
        default="codex",
        help="Codex executable to use with --generate (default: codex).",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("contracts/codex-app-server/watch-manifest.json"),
        help="Watch manifest relative to the repo root.",
    )
    parser.add_argument(
        "--snapshots-dir",
        type=Path,
        default=Path("contracts/codex-app-server/snapshots"),
        help="Snapshot root relative to the repo root.",
    )
    parser.add_argument(
        "--update",
        action="store_true",
        help="Replace the checked-in snapshots with the current schema.",
    )
    return parser.parse_args()


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def load_manifest(path: Path) -> dict:
    return json.loads(path.read_text())


def all_watched_files(manifest: dict) -> list[tuple[str, str]]:
    watched: list[tuple[str, str]] = []
    for relpath in manifest.get("stable", []):
        watched.append(("stable", relpath))
    for relpath in manifest.get("experimental", []):
        watched.append(("experimental", relpath))
    return watched


def require_schema_dir(schema_dir: Path, source: str) -> Path:
    schema_dir = schema_dir.resolve()
    if not (schema_dir / "v2").is_dir():
        raise SystemExit(f"{source} resolved to {schema_dir}, but it does not contain v2/.")
    return schema_dir


def schema_dir_from_codex_repo(codex_repo: Path, source: str) -> Path:
    codex_repo = codex_repo.resolve()
    if not codex_repo.is_dir():
        raise SystemExit(f"{source} {codex_repo} is not a directory.")
    schema_dir = codex_repo / CODEX_SCHEMA_SUBDIR
    return require_schema_dir(
        schema_dir,
        f"{source} {codex_repo} via {CODEX_SCHEMA_SUBDIR}",
    )


def resolve_schema_root(args: argparse.Namespace) -> tuple[Path, tempfile.TemporaryDirectory[str] | None]:
    explicit_modes = [
        args.codex_repo is not None,
        args.schema_dir is not None,
        args.generate,
    ]
    if sum(1 for enabled in explicit_modes if enabled) > 1:
        raise SystemExit("Choose only one of --codex-repo, --schema-dir, or --generate.")
    if args.codex_repo:
        return schema_dir_from_codex_repo(args.codex_repo, "--codex-repo"), None
    if args.schema_dir:
        return require_schema_dir(args.schema_dir, "--schema-dir"), None
    env_repo = os.environ.get(CODEX_REPO_ENV)
    if env_repo:
        return schema_dir_from_codex_repo(Path(env_repo), f"${CODEX_REPO_ENV}"), None
    if not args.generate:
        raise SystemExit(
            f"Provide --codex-repo, --schema-dir, or --generate, or set ${CODEX_REPO_ENV}."
        )

    tempdir: tempfile.TemporaryDirectory[str] = tempfile.TemporaryDirectory(prefix="neovim-codex-schema-")
    out_dir = Path(tempdir.name)
    command = [args.codex_binary, "app-server", "generate-ts", "--out", str(out_dir)]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise SystemExit(result.returncode)
    if not (out_dir / "v2").is_dir():
        raise SystemExit(f"Generated schema at {out_dir} did not contain v2/.")
    return out_dir, tempdir


def diff_text(expected: str, actual: str, relpath: str) -> str:
    return "".join(
        difflib.unified_diff(
            expected.splitlines(keepends=True),
            actual.splitlines(keepends=True),
            fromfile=f"snapshot/{relpath}",
            tofile=f"current/{relpath}",
        )
    )


def normalize_text(text: str) -> str:
    normalized = "\n".join(line.rstrip() for line in text.splitlines())
    if text.endswith("\n"):
        normalized += "\n"
    return normalized


def main() -> int:
    args = parse_args()
    root = repo_root()
    manifest_path = (root / args.manifest).resolve()
    snapshots_root = (root / args.snapshots_dir).resolve()
    manifest = load_manifest(manifest_path)
    watched = all_watched_files(manifest)
    schema_root, tempdir = resolve_schema_root(args)

    try:
        problems: list[str] = []
        checked = 0
        for category, relpath in watched:
            source_path = schema_root / relpath
            snapshot_path = snapshots_root / relpath
            if not source_path.is_file():
                problems.append(f"missing current schema file ({category}): {relpath}")
                continue
            current = normalize_text(source_path.read_text())
            if args.update:
                snapshot_path.parent.mkdir(parents=True, exist_ok=True)
                snapshot_path.write_text(current)
                checked += 1
                continue
            if not snapshot_path.is_file():
                problems.append(f"missing snapshot file ({category}): {relpath}")
                continue
            expected = normalize_text(snapshot_path.read_text())
            if expected != current:
                problems.append(diff_text(expected, current, relpath))
            checked += 1

        if args.update:
            print(f"Updated {checked} watched schema snapshots.")
            return 0

        if problems:
            print("Codex app-server contract drift detected.\n")
            for problem in problems:
                print(problem)
            return 1

        print(f"Codex app-server contract surface is stable ({checked} watched files).")
        return 0
    finally:
        if tempdir is not None:
            tempdir.cleanup()


if __name__ == "__main__":
    raise SystemExit(main())
