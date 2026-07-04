#!/usr/bin/env python3
"""Integration harness for GoLesson Bridge.

Runs T6/T8/T12 checks against a Supabase REST endpoint and a temporary
GoAlimi MockSender server. The harness avoids the operational GoAlimi DB by
using GOALIMI_DB_PATH under a temp directory.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
from pathlib import Path
import random
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from dataclasses import replace
from datetime import datetime, timedelta, timezone
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

import requests

from bridge.bridge import (  # noqa: E402
    Bridge,
    BridgeConfig,
    GoAlimiClient,
    SupabaseClient,
    load_config,
    now_kst,
)


MARKER = "CODEX_BRIDGE_HARNESS"
DEFAULT_GOALIMI_REPO = Path("/Users/nanbada/projects/GoAlimi")


class HarnessFailure(RuntimeError):
    pass


class ManagedGoAlimi:
    def __init__(self, repo: Path, port: int):
        self.repo = repo
        self.port = port
        self.tmpdir = Path(tempfile.mkdtemp(prefix="golesson-goalimi-mock-"))
        self.db_path = self.tmpdir / "goalimi_mock.db"
        self.log_path = self.tmpdir / "goalimi.log"
        self.proc: subprocess.Popen[bytes] | None = None

    @property
    def base_url(self) -> str:
        return f"http://127.0.0.1:{self.port}"

    def start(self) -> None:
        env = os.environ.copy()
        env.update({
            "GOALIMI_MOCK_SENDER": "1",
            "GOALIMI_DB_PATH": str(self.db_path),
            "PYTHONUNBUFFERED": "1",
        })
        log_file = self.log_path.open("ab")
        self.proc = subprocess.Popen(
            [
                sys.executable,
                "-m",
                "uvicorn",
                "app.main:app",
                "--host",
                "127.0.0.1",
                "--port",
                str(self.port),
                "--log-level",
                "info",
            ],
            cwd=self.repo,
            env=env,
            stdout=log_file,
            stderr=subprocess.STDOUT,
        )
        deadline = time.monotonic() + 25
        last_error = ""
        while time.monotonic() < deadline:
            if self.proc.poll() is not None:
                raise HarnessFailure(f"GoAlimi exited early; log={self.log_path}")
            try:
                resp = requests.get(f"{self.base_url}/api/health", timeout=1)
                if resp.status_code == 200:
                    return
                last_error = f"HTTP {resp.status_code}"
            except requests.RequestException as exc:
                last_error = str(exc)
            time.sleep(0.5)
        raise HarnessFailure(f"GoAlimi did not become healthy: {last_error}; log={self.log_path}")

    def stop(self) -> None:
        if not self.proc or self.proc.poll() is not None:
            return
        self.proc.terminate()
        try:
            self.proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait(timeout=5)

    def cleanup(self) -> None:
        self.stop()
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def restart(self) -> None:
        self.stop()
        self.start()

    def mock_send_count(self) -> int:
        if not self.log_path.exists():
            return 0
        return self.log_path.read_text(encoding="utf-8", errors="ignore").count("[MockSender]")


class Harness:
    def __init__(self, config: BridgeConfig, goalimi_repo: Path, port: int):
        self.goalimi = ManagedGoAlimi(goalimi_repo, port)
        self.config = replace(
            config,
            goalimi_base_url=self.goalimi.base_url,
            poll_sec=3,
            send_window=(0, 24),
        )
        self.supabase = SupabaseClient(self.config.supabase_url, self.config.service_key)
        self.bridge = Bridge(
            self.config,
            self.supabase,
            GoAlimiClient(self.config.goalimi_base_url),
            logging.getLogger("bridge.integration"),
        )
        self.run_id = datetime.now().strftime("%Y%m%d%H%M%S") + f"{random.randint(100, 999)}"
        self.student_goalimi_id = 770_700_000 + random.randint(1_000, 9_999)
        self.parent_goalimi_id = self.student_goalimi_id + 100_000
        self.attendance_goalimi_id = self.student_goalimi_id + 200_000
        self.local_student_id: int | None = None
        self.inserted_report_ids: list[int] = []
        self.inserted_outbox_ids: list[int] = []
        self.original_students: list[dict[str, Any]] = []

    def run(self) -> None:
        self.require_local_supabase()
        self.goalimi.start()
        self.cleanup_previous_marker_rows()
        self.abort_if_unrelated_pending()
        self.pick_non_conflicting_ids()
        self.original_students = self.supabase.select(
            "students",
            {"select": "id,goalimi_student_id,active,synced_at"},
        )
        self.seed_goalimi_db()
        try:
            self.test_t8_sync()
            self.test_t6_send_success()
            self.test_t6_goalimi_down_keeps_pending()
            self.test_t6_send_window_keeps_pending()
            self.test_t12_6_hard_delete_reconcile()
            self.test_t12_7_stale_processing_recovery_no_extra_send()
        finally:
            self.cleanup_supabase_rows()
            self.restore_student_snapshot()
            self.goalimi.cleanup()

    def require_local_supabase(self) -> None:
        if (
            self.config.supabase_url.startswith("http://127.0.0.1")
            or self.config.supabase_url.startswith("http://localhost")
        ):
            return
        raise HarnessFailure("integration harness requires local Supabase; refusing remote project")

    def pick_non_conflicting_ids(self) -> None:
        max_rows = self.supabase.select(
            "attendance",
            {"select": "goalimi_log_id", "order": "goalimi_log_id.desc", "limit": "1"},
        )
        current_max_log = int(max_rows[0]["goalimi_log_id"]) if max_rows else 0
        self.attendance_goalimi_id = max(self.attendance_goalimi_id, current_max_log + 10_000)
        for _ in range(20):
            existing = self.supabase.select(
                "students",
                {
                    "goalimi_student_id": f"eq.{self.student_goalimi_id}",
                    "select": "id",
                    "limit": "1",
                },
            )
            if not existing:
                return
            self.student_goalimi_id += random.randint(10_000, 99_999)
            self.parent_goalimi_id = self.student_goalimi_id + 100_000
        raise HarnessFailure("could not pick a non-conflicting goalimi_student_id")

    def seed_goalimi_db(self) -> None:
        with sqlite3.connect(self.goalimi.db_path) as conn:
            conn.execute("PRAGMA foreign_keys = ON")
            conn.execute(
                """
                insert into students(
                  id, name, grade, school, phone, checkin_code, remarks, active
                ) values (?, ?, ?, ?, ?, ?, ?, 1)
                """,
                (
                    self.student_goalimi_id,
                    "신성화",
                    "초6",
                    "Codex초",
                    "010-0000-7707",
                    str(self.student_goalimi_id)[-4:],
                    MARKER,
                ),
            )
            conn.execute(
                """
                insert into parents(
                  id, student_id, kakao_name, phone, relation, is_primary, notify_enabled
                ) values (?, ?, ?, ?, ?, 1, 1)
                """,
                (
                    self.parent_goalimi_id,
                    self.student_goalimi_id,
                    "신성화",
                    "010-0000-7707",
                    "운영자",
                ),
            )
            conn.execute(
                """
                insert into attendance_logs(
                  id, student_id, event_type, event_at, notification_status
                ) values (?, ?, 'IN', ?, 'sent')
                """,
                (
                    self.attendance_goalimi_id,
                    self.student_goalimi_id,
                    datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                ),
            )

    def update_goalimi_student_active(self, active: int) -> None:
        with sqlite3.connect(self.goalimi.db_path) as conn:
            conn.execute(
                "update students set active = ?, updated_at = datetime('now','localtime') where id = ?",
                (active, self.student_goalimi_id),
            )

    def test_t8_sync(self) -> None:
        self.bridge.sync_students()
        self.bridge.sync_parents()
        self.bridge.sync_attendance_incremental()

        student = self.require_one(
            "students",
            {
                "goalimi_student_id": f"eq.{self.student_goalimi_id}",
                "select": "id,name,active",
                "limit": "1",
            },
            "T8 student sync",
        )
        self.local_student_id = int(student["id"])
        self.assert_equal(student["name"], "신성화", "T8 student name")
        self.assert_equal(student["active"], True, "T8 student active")

        parent = self.require_one(
            "parents",
            {
                "goalimi_parent_id": f"eq.{self.parent_goalimi_id}",
                "select": "student_id,kakao_name,is_primary,notify_enabled",
                "limit": "1",
            },
            "T8 parent sync",
        )
        self.assert_equal(int(parent["student_id"]), self.local_student_id, "T8 parent local student mapping")
        self.assert_equal(parent["kakao_name"], "신성화", "T8 parent kakao_name")

        attendance = self.require_one(
            "attendance",
            {
                "goalimi_log_id": f"eq.{self.attendance_goalimi_id}",
                "select": "student_id,event_type,event_at",
                "limit": "1",
            },
            "T8 attendance sync",
        )
        self.assert_equal(int(attendance["student_id"]), self.local_student_id, "T8 attendance local mapping")
        self.assert_equal(attendance["event_type"], "IN", "T8 attendance event_type")

        self.update_goalimi_student_active(0)
        self.bridge.sync_students()
        inactive = self.require_one(
            "students",
            {
                "goalimi_student_id": f"eq.{self.student_goalimi_id}",
                "select": "active",
                "limit": "1",
            },
            "T8 inactive propagation",
        )
        self.assert_equal(inactive["active"], False, "T8 inactive propagated")

        self.update_goalimi_student_active(1)
        self.bridge.sync_students()
        reactivated = self.require_one(
            "students",
            {
                "goalimi_student_id": f"eq.{self.student_goalimi_id}",
                "select": "active",
                "limit": "1",
            },
            "T8 reactivation propagation",
        )
        self.assert_equal(reactivated["active"], True, "T8 reactivation propagated")

    def test_t6_send_success(self) -> None:
        report_id, outbox_id = self.create_ready_report_and_outbox("t6-success")
        before = self.goalimi.mock_send_count()
        self.abort_if_unrelated_pending()
        self.bridge.claim_and_send()
        self.wait_until(
            lambda: self.outbox(outbox_id).get("status") == "sent",
            "T6 pending->sent",
        )
        self.assert_equal(self.report(report_id)["status"], "sent", "T6 report sent")
        self.assert_true(self.outbox(outbox_id).get("goalimi_custom_id") is not None, "T6 custom id stored")
        self.assert_equal(self.goalimi.mock_send_count(), before + 1, "T6 MockSender count")

    def test_t6_goalimi_down_keeps_pending(self) -> None:
        _report_id, outbox_id = self.create_ready_report_and_outbox("t6-goalimi-down")
        self.goalimi.stop()
        try:
            self.abort_if_unrelated_pending()
            self.bridge.claim_and_send()
            row = self.outbox(outbox_id)
            self.assert_equal(row["status"], "pending", "T6 GoAlimi down keeps pending")
            self.assert_equal(int(row["attempts"]), 1, "T6 GoAlimi down attempts incremented by claim")
        finally:
            self.goalimi.restart()

        self.abort_if_unrelated_pending()
        self.bridge.claim_and_send()
        self.wait_until(
            lambda: self.outbox(outbox_id).get("status") == "sent",
            "T6 pending send after GoAlimi restart",
        )

    def test_t6_send_window_keeps_pending(self) -> None:
        _report_id, outbox_id = self.create_ready_report_and_outbox("t6-window")
        closed_config = replace(self.config, send_window=(0, 0))
        closed_bridge = Bridge(
            closed_config,
            self.supabase,
            GoAlimiClient(self.config.goalimi_base_url),
            logging.getLogger("bridge.integration.closed-window"),
        )
        today = now_kst().date().isoformat()
        closed_bridge.last_sync_at = now_kst()
        closed_bridge.last_reconcile_on = today
        closed_bridge.last_backup_on = today
        closed_bridge.run_once()
        row = self.outbox(outbox_id)
        self.assert_equal(row["status"], "pending", "T6 send_window outside keeps pending")
        self.assert_equal(int(row["attempts"]), 0, "T6 send_window outside does not claim")

        self.abort_if_unrelated_pending()
        self.bridge.claim_and_send()
        self.wait_until(
            lambda: self.outbox(outbox_id).get("status") == "sent",
            "T6 send_window row later sent",
        )

    def test_t12_6_hard_delete_reconcile(self) -> None:
        with sqlite3.connect(self.goalimi.db_path) as conn:
            conn.execute("delete from attendance_logs where id = ?", (self.attendance_goalimi_id,))
        self.bridge.reconcile_attendance()
        rows = self.supabase.select(
            "attendance",
            {
                "goalimi_log_id": f"eq.{self.attendance_goalimi_id}",
                "select": "id",
                "limit": "1",
            },
        )
        self.assert_equal(rows, [], "T12-6 attendance hard delete reflected")

    def test_t12_7_stale_processing_recovery_no_extra_send(self) -> None:
        report_id, outbox_id = self.create_ready_report_and_outbox("t12-stale")
        dedupe_key = f"codex-bridge-{self.run_id}-t12-stale"
        goalimi_student_id = self.student_goalimi_id
        before_direct = self.goalimi.mock_send_count()
        custom = self.bridge.goalimi.post_custom(
            goalimi_student_id,
            f"{MARKER} direct custom for stale recovery",
            dedupe_key,
        )
        self.wait_until(
            lambda: self.bridge.goalimi.get_custom(int(custom["id"])).get("status") == "sent",
            "T12-7 direct GoAlimi custom sent",
        )
        after_direct = self.goalimi.mock_send_count()
        self.assert_equal(after_direct, before_direct + 1, "T12-7 direct MockSender baseline")

        old_time = (datetime.now(timezone.utc) - timedelta(minutes=11)).isoformat()
        self.force_stale_processing(outbox_id, dedupe_key, old_time)
        self.bridge.recover_processing()
        self.wait_until(
            lambda: self.outbox(outbox_id).get("status") == "sent",
            "T12-7 stale processing recovered",
        )
        row = self.outbox(outbox_id)
        self.assert_equal(int(row["goalimi_custom_id"]), int(custom["id"]), "T12-7 dedupe returned existing custom")
        self.assert_equal(self.report(report_id)["status"], "sent", "T12-7 report sent")
        self.assert_equal(self.goalimi.mock_send_count(), after_direct, "T12-7 recovery caused no extra send")

    def create_ready_report_and_outbox(self, suffix: str) -> tuple[int, int]:
        if self.local_student_id is None:
            raise HarnessFailure("local student id missing; T8 sync must run first")
        body = f"{MARKER} {suffix} {self.run_id}"
        report = self.supabase.request(
            "POST",
            "reports",
            json_body={
                "student_id": self.local_student_id,
                "period_start": "2026-07-01",
                "period_end": "2026-07-04",
                "stats": {"source": MARKER, "case": suffix},
                "body": body,
                "status": "ready",
            },
            headers={"Prefer": "return=representation"},
        )[0]
        report_id = int(report["id"])
        self.inserted_report_ids.append(report_id)
        dedupe_key = f"codex-bridge-{self.run_id}-{suffix}"
        outbox = self.supabase.request(
            "POST",
            "notification_outbox",
            json_body={
                "report_id": report_id,
                "student_id": self.local_student_id,
                "kakao_name": "신성화",
                "message": body,
                "dedupe_key": dedupe_key,
                "status": "pending",
            },
            headers={"Prefer": "return=representation"},
        )[0]
        outbox_id = int(outbox["id"])
        self.inserted_outbox_ids.append(outbox_id)
        return report_id, outbox_id

    def abort_if_unrelated_pending(self) -> None:
        rows = self.supabase.select(
            "notification_outbox",
            {
                "status": "in.(pending,processing)",
                "select": "id,dedupe_key,status",
                "order": "created_at",
            },
        )
        unrelated = [
            row for row in rows
            if not str(row.get("dedupe_key", "")).startswith(f"codex-bridge-{self.run_id}-")
        ]
        if unrelated:
            first = unrelated[0]
            raise HarnessFailure(
                f"unrelated pending/processing outbox exists: id={first['id']} status={first['status']}"
            )

    def cleanup_previous_marker_rows(self) -> None:
        old_outbox = self.supabase.select(
            "notification_outbox",
            {
                "dedupe_key": "like.codex-bridge-*",
                "select": "id,report_id",
            },
        )
        for row in old_outbox:
            self.supabase.delete("notification_outbox", {"id": f"eq.{row['id']}"})
        old_reports = self.supabase.select(
            "reports",
            {
                "body": f"like.*{MARKER}*",
                "select": "id",
            },
        )
        for row in old_reports:
            self.supabase.delete("reports", {"id": f"eq.{row['id']}"})

    def force_stale_processing(self, outbox_id: int, dedupe_key: str, old_time: str) -> None:
        if not (
            self.config.supabase_url.startswith("http://127.0.0.1")
            or self.config.supabase_url.startswith("http://localhost")
        ):
            raise HarnessFailure("T12-7 stale fixture requires local Supabase")
        escaped_key = dedupe_key.replace("'", "''")
        escaped_time = old_time.replace("'", "''")
        sql = f"""
begin;
alter table public.notification_outbox disable trigger t_outbox_updated_at;
update public.notification_outbox
   set status = 'processing',
       dedupe_key = '{escaped_key}',
       goalimi_custom_id = null,
       updated_at = '{escaped_time}'::timestamptz
 where id = {int(outbox_id)};
alter table public.notification_outbox enable trigger t_outbox_updated_at;
commit;
"""
        db_container = self.local_supabase_db_container()
        result = subprocess.run(
            [
                "docker",
                "exec",
                "-i",
                db_container,
                "psql",
                "-U",
                "postgres",
                "-d",
                "postgres",
                "-v",
                "ON_ERROR_STOP=1",
            ],
            input=sql,
            cwd=REPO_ROOT,
            text=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            check=False,
        )
        if result.returncode != 0:
            detail = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "unknown error"
            raise HarnessFailure(f"failed to create stale processing fixture: {detail}")

    def local_supabase_db_container(self) -> str:
        result = subprocess.run(
            ["docker", "ps", "--format", "{{.Names}}"],
            cwd=REPO_ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if result.returncode != 0:
            raise HarnessFailure("docker ps failed while locating local Supabase DB")
        names = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        preferred = "supabase_db_GoLesson"
        if preferred in names:
            return preferred
        matches = [name for name in names if name.startswith("supabase_db_")]
        if len(matches) == 1:
            return matches[0]
        raise HarnessFailure("could not identify local Supabase DB container")

    def cleanup_supabase_rows(self) -> None:
        for outbox_id in reversed(self.inserted_outbox_ids):
            self.supabase.delete("notification_outbox", {"id": f"eq.{outbox_id}"})
        for report_id in reversed(self.inserted_report_ids):
            self.supabase.delete("reports", {"id": f"eq.{report_id}"})
        self.supabase.delete(
            "attendance",
            {"goalimi_log_id": f"eq.{self.attendance_goalimi_id}"},
        )
        self.supabase.delete(
            "parents",
            {"goalimi_parent_id": f"eq.{self.parent_goalimi_id}"},
        )
        self.supabase.delete(
            "students",
            {"goalimi_student_id": f"eq.{self.student_goalimi_id}"},
        )

    def restore_student_snapshot(self) -> None:
        test_id = self.student_goalimi_id
        for row in self.original_students:
            if int(row["goalimi_student_id"]) == test_id:
                continue
            self.supabase.patch(
                "students",
                {"id": f"eq.{row['id']}"},
                {
                    "active": row["active"],
                    "synced_at": row.get("synced_at"),
                },
            )

    def require_one(self, table: str, params: dict[str, str], label: str) -> dict[str, Any]:
        rows = self.supabase.select(table, params)
        if len(rows) != 1:
            raise HarnessFailure(f"{label}: expected 1 row, got {len(rows)}")
        return rows[0]

    def report(self, report_id: int) -> dict[str, Any]:
        return self.require_one(
            "reports",
            {"id": f"eq.{report_id}", "select": "id,status,sent_at", "limit": "1"},
            f"report {report_id}",
        )

    def outbox(self, outbox_id: int) -> dict[str, Any]:
        return self.require_one(
            "notification_outbox",
            {
                "id": f"eq.{outbox_id}",
                "select": "id,status,attempts,goalimi_custom_id,error",
                "limit": "1",
            },
            f"outbox {outbox_id}",
        )

    def wait_until(self, predicate, label: str, timeout: float = 12) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.25)
        raise HarnessFailure(f"{label}: timeout")

    def assert_equal(self, actual: Any, expected: Any, label: str) -> None:
        if actual != expected:
            raise HarnessFailure(f"{label}: expected {expected!r}, got {actual!r}")
        print(f"PASS {label}")

    def assert_true(self, value: bool, label: str) -> None:
        if not value:
            raise HarnessFailure(f"{label}: expected truthy value")
        print(f"PASS {label}")


def build_logger(verbose: bool) -> None:
    logging.basicConfig(
        level=logging.INFO if verbose else logging.WARNING,
        format="%(asctime)s %(levelname)s %(message)s",
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run GoLesson Bridge integration harness")
    parser.add_argument("--config", default=str(REPO_ROOT / "bridge" / "bridge_config.json"))
    parser.add_argument("--goalimi-repo", default=str(DEFAULT_GOALIMI_REPO))
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(argv)

    build_logger(args.verbose)
    config_path = Path(args.config).resolve()
    goalimi_repo = Path(args.goalimi_repo).resolve()
    if not config_path.exists():
        raise HarnessFailure(f"missing bridge config: {config_path}")
    if not (goalimi_repo / "app" / "main.py").exists():
        raise HarnessFailure(f"invalid GoAlimi repo: {goalimi_repo}")

    config = load_config(config_path)
    harness = Harness(config, goalimi_repo, args.port)
    harness.run()
    print("PASS Bridge integration harness completed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
