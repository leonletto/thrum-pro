#!/usr/bin/env python3
"""Archive roster watcher captures as private, byte-preserving records."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = "roster-capture-archive-v2"
TRAINING_VIEW_SCHEMA_VERSION = "roster-capture-training-view-v2"
HEADER_RE = re.compile(r"^=== ([^=\n]+) ===\s*$")
FILENAME_TS_RE = re.compile(r"roster-capture-(\d{8}-\d{6})(?:-(\d{6}))?\.txt$")
DEFAULT_REQUESTED_LINES = 30
LINE_SEMANTICS = (
    "tmux capture text from existing watcher behavior and joined logical lines; direct records preserve "
    "raw bytes, legacy assembled import preserves full source bytes but only "
    "derives per-agent text from column-1 delimiters"
)


class ArchiveError(RuntimeError):
    """Archive operation failed after preserving whatever source bytes existed."""


class ArchiveWriteConflictError(ArchiveError):
    """An immutable archive path already exists with different content."""


class AmbiguousHeaderError(ArchiveError):
    """A legacy assembled import saw a roster-looking header it cannot trust."""


@dataclass(frozen=True)
class RosterSection:
    index: int
    agent: str
    line_start: int
    line_end: int
    raw_response: str


@dataclass(frozen=True)
class ArchiveWrite:
    path: Path
    status: str


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_text(text: str) -> str:
    return sha256_bytes(text.encode("utf-8"))


def stable_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def chmod_private_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    os.chmod(path, stat.S_IRWXU)


def fsync_dir(path: Path) -> None:
    try:
        fd = os.open(path, os.O_RDONLY)
    except OSError:
        return
    try:
        os.fsync(fd)
    except OSError:
        pass
    finally:
        os.close(fd)


def private_subdir(root: Path, *parts: str) -> Path:
    path = root.joinpath(*parts)
    chmod_private_dir(path)
    return path


def write_idempotent_bytes(path: Path, data: bytes) -> ArchiveWrite:
    """Create a private file, or accept an exact same-content retry."""

    chmod_private_dir(path.parent)
    tmp = path.parent / f".{path.name}.{os.getpid()}.{uuid.uuid4().hex}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        try:
            os.link(tmp, path)
        except FileExistsError:
            if path.read_bytes() == data:
                return ArchiveWrite(path=path, status="existing")
            existing_sha = sha256_bytes(path.read_bytes())
            incoming_sha = sha256_bytes(data)
            raise ArchiveWriteConflictError(
                stable_json(
                    {
                        "reason": "archive_write_conflict",
                        "path": str(path),
                        "existing_sha256": existing_sha,
                        "incoming_sha256": incoming_sha,
                        "retry_backfill_strategy": "preserve both inputs; move conflicting incoming capture to a new capture_id/source path and rerun archive-agent/archive-source, or backfill from raw-ticks after resolving the duplicate filename source",
                    }
                )
            ) from None
        os.chmod(path, 0o600)
        fsync_dir(path.parent)
        return ArchiveWrite(path=path, status="written")
    except Exception:
        raise
    finally:
        try:
            tmp.unlink()
        except FileNotFoundError:
            pass


def write_idempotent_json(path: Path, value: dict[str, Any]) -> ArchiveWrite:
    return write_idempotent_bytes(path, (stable_json(value) + "\n").encode("utf-8"))


def write_immutable_json(path: Path, value: dict[str, Any]) -> None:
    """Compatibility wrapper retained for existing tests/callers."""

    write_idempotent_json(path, value)


def store_blob(root: Path, family: str, digest: str, suffix: str, data: bytes) -> ArchiveWrite:
    return write_idempotent_bytes(private_subdir(root, family) / f"{digest}{suffix}", data)


def parse_roster_sections(
    text: str,
    *,
    known_agents: Iterable[str] | None = None,
    fail_unknown_headers: bool = False,
) -> list[RosterSection]:
    known = set(known_agents or [])
    sections: list[RosterSection] = []
    current_agent: str | None = None
    current_start = 0
    current_lines: list[str] = []
    lines = text.splitlines()
    for lineno, line in enumerate(lines, start=1):
        match = HEADER_RE.match(line)
        if match:
            name = match.group(1)
            if known and name not in known and fail_unknown_headers:
                raise AmbiguousHeaderError(
                    f"legacy roster header at line {lineno} is not a known agent; it may be pane content"
                )
            if current_agent is not None:
                sections.append(
                    RosterSection(
                        index=len(sections) + 1,
                        agent=current_agent,
                        line_start=current_start,
                        line_end=lineno - 1,
                        raw_response="\n".join(current_lines),
                    )
                )
            current_agent = name
            current_start = lineno
            current_lines = []
            continue
        if current_agent is not None:
            current_lines.append(line)
    if current_agent is not None:
        sections.append(
            RosterSection(
                index=len(sections) + 1,
                agent=current_agent,
                line_start=current_start,
                line_end=len(lines),
                raw_response="\n".join(current_lines),
            )
        )
    return sections


def capture_timestamp_from_name(path: Path) -> str | None:
    match = FILENAME_TS_RE.match(path.name)
    if not match:
        return None
    stamp = match.group(1)
    micros = match.group(2)
    base = f"{stamp[0:4]}-{stamp[4:6]}-{stamp[6:8]}T{stamp[9:11]}:{stamp[11:13]}:{stamp[13:15]}"
    if micros:
        return f"{base}.{micros}Z"
    return f"{base}Z"


def classify_failure_state(raw_response: str, capture_rc: int = 0) -> tuple[str, str | None]:
    lower = raw_response.lower()
    if capture_rc != 0:
        return "capture_failed", first_nonempty(raw_response)
    if "error: tmux.capture" in lower or "failed to connect to daemon" in lower:
        return "error_text", first_nonempty(raw_response)
    if "degraded-known" in lower:
        return "degraded_known", first_marker(raw_response)
    if "fallback skipped" in lower:
        return "fallback_skipped", first_marker(raw_response)
    if "fallback deferred" in lower:
        return "fallback_deferred", first_marker(raw_response)
    if "capture failed" in lower:
        return "capture_failed", first_marker(raw_response)
    return "success", None


def first_marker(text: str) -> str | None:
    for line in text.splitlines():
        if line.startswith("---"):
            return line[:240]
    return first_nonempty(text)


def first_nonempty(text: str) -> str | None:
    for line in text.splitlines():
        if line.strip():
            return line[:240]
    return None


def parse_geometry_json(value: str | None) -> tuple[dict[str, Any] | None, str]:
    if not value:
        return None, "unmeasured"
    parsed = json.loads(value)
    if not isinstance(parsed, dict):
        raise ValueError("geometry JSON must be an object")
    allowed = {"pane_width", "pane_height", "cursor_x", "cursor_y", "pane_in_mode", "source", "target", "measured_at_unix"}
    extra = set(parsed) - allowed
    if extra:
        raise ValueError(f"unexpected geometry keys: {sorted(extra)}")
    return parsed, "measured"


def record_filename(record: dict[str, Any]) -> str:
    ts = record.get("capture_timestamp_utc") or "unknown-time"
    safe_agent = re.sub(r"[^A-Za-z0-9_.-]+", "_", str(record["agent"]))[:80]
    source_digest = str(record.get("source_file_sha256") or "direct")[:12]
    raw_digest = record["raw_response_sha256"][:16]
    index = int(record.get("section_index") or 0)
    return f"{ts.replace(':', '').replace('-', '')}_{index:04d}_{safe_agent}_{source_digest}_{raw_digest}.json"


def build_direct_record(
    *,
    archive_dir: Path,
    agent: str,
    raw_response_bytes: bytes,
    requested_lines: int = DEFAULT_REQUESTED_LINES,
    capture_rc: int = 0,
    capture_timestamp_utc: str | None = None,
    capture_id: str | None = None,
    source_file: Path | None = None,
    source_bytes: bytes | None = None,
    source_blob: Path | None = None,
    source_sha256: str | None = None,
    section_index: int | None = None,
    line_start: int | None = None,
    line_end: int | None = None,
    runtime: str | None = None,
    box: str | None = None,
    geometry: dict[str, Any] | None = None,
    geometry_provenance: str = "unmeasured",
    capture_route: str | None = None,
    primary_rc: int | None = None,
    ssh_rc: int | None = None,
    final_rc: int | None = None,
    split_provenance: str = "direct_per_agent_capture_time",
    split_reliable: bool = True,
) -> dict[str, Any]:
    raw_sha = sha256_bytes(raw_response_bytes)
    raw_blob = store_blob(archive_dir, "raw", raw_sha, ".bin", raw_response_bytes)
    raw_text = raw_response_bytes.decode("utf-8", errors="replace")
    failure_state, error_excerpt = classify_failure_state(raw_text, capture_rc)
    if source_bytes is not None and source_sha256 is None:
        source_sha256 = sha256_bytes(source_bytes)
    return {
        "schema_version": SCHEMA_VERSION,
        "capture_id": capture_id,
        "capture_timestamp_utc": capture_timestamp_utc,
        "agent": agent,
        "runtime": runtime,
        "box": box,
        "requested_lines": requested_lines,
        "line_semantics": LINE_SEMANTICS,
        "geometry": geometry,
        "geometry_provenance": geometry_provenance,
        "capture_rc": capture_rc,
        "final_rc": final_rc if final_rc is not None else capture_rc,
        "primary_rc": primary_rc,
        "ssh_rc": ssh_rc,
        "capture_route": capture_route,
        "failure_state": failure_state,
        "error_excerpt": error_excerpt,
        "section_index": section_index,
        "line_start": line_start,
        "line_end": line_end,
        "split_provenance": split_provenance,
        "split_reliable": split_reliable,
        "source_file": str(source_file) if source_file is not None else None,
        "source_file_name": source_file.name if source_file is not None else None,
        "source_file_sha256": source_sha256,
        "source_blob": str(source_blob) if source_blob is not None else None,
        "raw_response_sha256": raw_sha,
        "raw_response_bytes": len(raw_response_bytes),
        "raw_response_blob": str(raw_blob.path),
        "joined_logical_line_count": len(raw_text.splitlines()),
    }


def archive_agent_capture(
    *,
    archive_dir: Path,
    agent: str,
    raw_response_bytes: bytes,
    requested_lines: int = DEFAULT_REQUESTED_LINES,
    capture_rc: int = 0,
    capture_timestamp_utc: str | None = None,
    capture_id: str | None = None,
    source_file: Path | None = None,
    source_bytes: bytes | None = None,
    source_blob: Path | None = None,
    source_sha256: str | None = None,
    section_index: int | None = None,
    line_start: int | None = None,
    line_end: int | None = None,
    runtime: str | None = None,
    box: str | None = None,
    geometry: dict[str, Any] | None = None,
    geometry_provenance: str = "unmeasured",
    capture_route: str | None = None,
    primary_rc: int | None = None,
    ssh_rc: int | None = None,
    final_rc: int | None = None,
    split_provenance: str = "direct_per_agent_capture_time",
    split_reliable: bool = True,
) -> ArchiveWrite:
    chmod_private_dir(archive_dir)
    record = build_direct_record(
        archive_dir=archive_dir,
        agent=agent,
        raw_response_bytes=raw_response_bytes,
        requested_lines=requested_lines,
        capture_rc=capture_rc,
        capture_timestamp_utc=capture_timestamp_utc,
        capture_id=capture_id,
        source_file=source_file,
        source_bytes=source_bytes,
        source_blob=source_blob,
        source_sha256=source_sha256,
        section_index=section_index,
        line_start=line_start,
        line_end=line_end,
        runtime=runtime,
        box=box,
        geometry=geometry,
        geometry_provenance=geometry_provenance,
        capture_route=capture_route,
        primary_rc=primary_rc,
        ssh_rc=ssh_rc,
        final_rc=final_rc,
        split_provenance=split_provenance,
        split_reliable=split_reliable,
    )
    out = private_subdir(archive_dir, "records") / record_filename(record)
    return write_idempotent_json(out, record)


def write_import_error(archive_dir: Path, *, source_path: Path, source_sha: str, source_blob: Path, error: str, reason: str) -> Path:
    payload = {
        "schema_version": "roster-capture-import-error-v1",
        "source_file": str(source_path),
        "source_file_name": source_path.name,
        "source_file_sha256": source_sha,
        "source_blob": str(source_blob),
        "error": error,
        "reason": reason,
    }
    out = private_subdir(archive_dir, "errors") / f"{source_sha}_{reason}.json"
    write_idempotent_json(out, payload)
    return out


def archive_roster_file(
    source_path: Path,
    archive_dir: Path,
    requested_lines: int = DEFAULT_REQUESTED_LINES,
    *,
    known_agents: Iterable[str] | None = None,
    fail_unknown_headers: bool = False,
) -> list[Path]:
    source_bytes = source_path.read_bytes()
    source_sha = sha256_bytes(source_bytes)
    chmod_private_dir(archive_dir)
    source_blob = store_blob(archive_dir, "sources", source_sha, ".txt", source_bytes)
    source_text = source_bytes.decode("utf-8", errors="replace")
    try:
        sections = parse_roster_sections(source_text, known_agents=known_agents, fail_unknown_headers=fail_unknown_headers)
    except AmbiguousHeaderError as exc:
        write_import_error(
            archive_dir,
            source_path=source_path,
            source_sha=source_sha,
            source_blob=source_blob.path,
            error=str(exc),
            reason="ambiguous_header",
        )
        raise
    if not sections:
        write_import_error(
            archive_dir,
            source_path=source_path,
            source_sha=source_sha,
            source_blob=source_blob.path,
            error="legacy assembled roster file contained zero parseable column-1 headers",
            reason="zero_headers",
        )
        raise ArchiveError("zero parseable roster headers; source bytes preserved")
    written: list[Path] = []
    for section in sections:
        result = archive_agent_capture(
            archive_dir=archive_dir,
            agent=section.agent,
            raw_response_bytes=section.raw_response.encode("utf-8"),
            requested_lines=requested_lines,
            capture_timestamp_utc=capture_timestamp_from_name(source_path),
            capture_id=source_path.stem,
            source_file=source_path,
            source_bytes=source_bytes,
            source_blob=source_blob.path,
            source_sha256=source_sha,
            section_index=section.index,
            line_start=section.line_start,
            line_end=section.line_end,
            capture_route="legacy_assembled_import",
            split_provenance="legacy_assembled_column1_headers",
            split_reliable=False,
        )
        written.append(result.path)
    return written


def load_record_text(record: dict[str, Any]) -> str:
    blob_path = record.get("raw_response_blob")
    if blob_path:
        return Path(blob_path).read_bytes().decode("utf-8", errors="replace")
    return str(record.get("raw_response") or "")


def derive_training_view(records_dir: Path, out_path: Path) -> int:
    rows: list[dict[str, Any]] = []
    for path in sorted(records_dir.glob("*.json")):
        record = json.loads(path.read_text(encoding="utf-8"))
        text = load_record_text(record)
        rows.append(
            {
                "schema_version": TRAINING_VIEW_SCHEMA_VERSION,
                "record_path": str(path),
                "source_file": record.get("source_file"),
                "source_file_sha256": record.get("source_file_sha256"),
                "source_blob": record.get("source_blob"),
                "agent": record["agent"],
                "capture_timestamp_utc": record.get("capture_timestamp_utc"),
                "requested_lines": record["requested_lines"],
                "line_semantics": record["line_semantics"],
                "geometry": record.get("geometry"),
                "geometry_provenance": record.get("geometry_provenance"),
                "failure_state": record["failure_state"],
                "split_provenance": record.get("split_provenance"),
                "split_reliable": record.get("split_reliable"),
                "text": f"=== {record['agent']} ===\n{text}",
            }
        )
    chmod_private_dir(out_path.parent)
    tmp = out_path.with_name(f".{out_path.name}.{os.getpid()}.tmp")
    with tmp.open("w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(stable_json(row) + "\n")
        fh.flush()
        os.fsync(fh.fileno())
    os.chmod(tmp, 0o600)
    os.replace(tmp, out_path)
    fsync_dir(out_path.parent)
    return len(rows)


def cmd_archive_agent(args: argparse.Namespace) -> int:
    geometry, geometry_provenance = parse_geometry_json(args.geometry_json)
    source_bytes = args.source_file.read_bytes() if args.source_file and args.source_file.exists() else None
    source_sha = sha256_bytes(source_bytes) if source_bytes is not None else None
    source_blob = None
    if source_bytes is not None and source_sha is not None:
        source_blob = store_blob(args.archive_dir, "sources", source_sha, ".txt", source_bytes).path
    result = archive_agent_capture(
        archive_dir=args.archive_dir,
        agent=args.agent,
        raw_response_bytes=args.raw_file.read_bytes(),
        requested_lines=args.requested_lines,
        capture_rc=args.capture_rc,
        capture_timestamp_utc=args.capture_timestamp_utc,
        capture_id=args.capture_id,
        source_file=args.source_file,
        source_bytes=source_bytes,
        source_blob=source_blob,
        source_sha256=source_sha,
        runtime=args.runtime,
        box=args.box,
        geometry=geometry,
        geometry_provenance=geometry_provenance,
        capture_route=args.capture_route,
        primary_rc=args.primary_rc,
        ssh_rc=args.ssh_rc,
        final_rc=args.final_rc,
    )
    print(json.dumps({"record": str(result.path), "status": result.status}, sort_keys=True))
    return 0


def cmd_archive_source(args: argparse.Namespace) -> int:
    source_bytes = args.source.read_bytes()
    source_sha = sha256_bytes(source_bytes)
    result = store_blob(args.archive_dir, "sources", source_sha, ".txt", source_bytes)
    manifest = {
        "schema_version": "roster-capture-source-v1",
        "capture_id": args.capture_id,
        "capture_timestamp_utc": args.capture_timestamp_utc,
        "source_file": str(args.source),
        "source_file_name": args.source.name,
        "source_file_sha256": source_sha,
        "source_blob": str(result.path),
    }
    safe_capture = re.sub(r"[^A-Za-z0-9_.-]+", "_", args.capture_id or source_sha)[:120]
    out = private_subdir(args.archive_dir, "source-records") / f"{safe_capture}_{source_sha}.json"
    written = write_idempotent_json(out, manifest)
    print(json.dumps({"source": str(result.path), "source_status": result.status, "record": str(written.path)}, sort_keys=True))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)
    archive = sub.add_parser("archive-roster-file")
    archive.add_argument("--source", required=True, type=Path)
    archive.add_argument("--archive-dir", required=True, type=Path)
    archive.add_argument("--requested-lines", type=int, default=DEFAULT_REQUESTED_LINES)
    archive.add_argument("--known-agent", action="append", default=[])
    archive.add_argument("--fail-unknown-headers", action="store_true")
    agent = sub.add_parser("archive-agent")
    agent.add_argument("--archive-dir", required=True, type=Path)
    agent.add_argument("--agent", required=True)
    agent.add_argument("--raw-file", required=True, type=Path)
    agent.add_argument("--source-file", type=Path)
    agent.add_argument("--requested-lines", type=int, default=DEFAULT_REQUESTED_LINES)
    agent.add_argument("--capture-rc", type=int, default=0)
    agent.add_argument("--capture-timestamp-utc")
    agent.add_argument("--capture-id")
    agent.add_argument("--runtime")
    agent.add_argument("--box")
    agent.add_argument("--geometry-json")
    agent.add_argument("--capture-route")
    agent.add_argument("--primary-rc", type=int)
    agent.add_argument("--ssh-rc", type=int)
    agent.add_argument("--final-rc", type=int)
    source = sub.add_parser("archive-source")
    source.add_argument("--archive-dir", required=True, type=Path)
    source.add_argument("--source", required=True, type=Path)
    source.add_argument("--capture-timestamp-utc")
    source.add_argument("--capture-id")
    view = sub.add_parser("derive-training-view")
    view.add_argument("--records-dir", required=True, type=Path)
    view.add_argument("--out", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        if args.cmd == "archive-roster-file":
            paths = archive_roster_file(
                args.source,
                args.archive_dir,
                args.requested_lines,
                known_agents=args.known_agent,
                fail_unknown_headers=args.fail_unknown_headers,
            )
            print(json.dumps({"records_written": len(paths), "archive_dir": str(args.archive_dir)}, sort_keys=True))
            return 0
        if args.cmd == "archive-agent":
            return cmd_archive_agent(args)
        if args.cmd == "archive-source":
            return cmd_archive_source(args)
        if args.cmd == "derive-training-view":
            count = derive_training_view(args.records_dir, args.out)
            print(json.dumps({"rows_written": count, "out": str(args.out)}, sort_keys=True))
            return 0
    except ArchiveError as exc:
        print(json.dumps({"error": str(exc), "archive_dir": str(getattr(args, "archive_dir", ""))}, sort_keys=True), file=sys.stderr)
        return 1
    return 2


if __name__ == "__main__":
    sys.exit(main())
