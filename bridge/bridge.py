#!/usr/bin/env python3
"""GoLesson Bridge: Supabase outbox polling + GoAlimi sync.

Design constraints come from docs/05 §3 and docs/08 §4:
- claim outbox only through claim_outbox RPC
- never auto-resend failed sends
- recover processing rows only through GoAlimi status lookup or idempotent re-POST
- keep service_role key only in bridge_config.json
"""

from __future__ import annotations

import argparse
import json
import logging
from logging.handlers import TimedRotatingFileHandler
from pathlib import Path
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

try:
    import requests
except ImportError:  # pragma: no cover - installation guidance path
    print("requests is required: python -m pip install requests", file=sys.stderr)
    raise


KST = ZoneInfo("Asia/Seoul")
NON_TERMINAL_CUSTOM_STATUS = {"pending", "sending"}
DEFAULT_TABLES = [
    "profiles",
    "students",
    "parents",
    "textbooks",
    "student_textbooks",
    "enrollments",
    "schedule_slots",
    "lessons",
    "lesson_progress",
    "homeworks",
    "comments",
    "attendance",
    "payments",
    "payment_items",
    "reports",
    "notification_outbox",
    "parse_logs",
    "app_settings",
    "audits",
]


@dataclass(frozen=True)
class BridgeConfig:
    supabase_url: str
    service_key: str
    goalimi_base_url: str
    poll_sec: int
    send_window: tuple[int, int]
    backup_dir: Path


def load_config(path: Path) -> BridgeConfig:
    raw = json.loads(path.read_text(encoding="utf-8"))
    required = ["supabase_url", "service_key", "goalimi_base_url"]
    missing = [key for key in required if not str(raw.get(key, "")).strip()]
    if missing:
        raise ValueError(f"missing config fields: {', '.join(missing)}")
    send_window = raw.get("send_window", [9, 21])
    if not isinstance(send_window, list) or len(send_window) != 2:
        raise ValueError("send_window must be [start_hour, end_hour]")
    backup_dir = Path(raw.get("backup_dir", "backup"))
    if not backup_dir.is_absolute():
        backup_dir = path.parent / backup_dir
    return BridgeConfig(
        supabase_url=str(raw["supabase_url"]).rstrip("/"),
        service_key=str(raw["service_key"]),
        goalimi_base_url=str(raw["goalimi_base_url"]).rstrip("/"),
        poll_sec=int(raw.get("poll_sec", 60)),
        send_window=(int(send_window[0]), int(send_window[1])),
        backup_dir=backup_dir,
    )


def setup_logging(base_dir: Path) -> logging.Logger:
    log_dir = base_dir / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger("golesson.bridge")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    fmt = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    file_handler = TimedRotatingFileHandler(
        log_dir / "bridge.log",
        when="midnight",
        backupCount=14,
        encoding="utf-8",
    )
    file_handler.setFormatter(fmt)
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(fmt)
    logger.addHandler(file_handler)
    logger.addHandler(console_handler)
    return logger


def now_kst() -> datetime:
    return datetime.now(KST)


def as_kst_iso(value: datetime | None = None) -> str:
    return (value or now_kst()).isoformat(timespec="seconds")


def parse_goalimi_local_time(value: str) -> str:
    # GoAlimi returns naive local timestamps. Store them as KST timestamptz so
    # Supabase does not interpret them as UTC and shift dates.
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=KST)
    return dt.isoformat(timespec="seconds")


def in_send_window(send_window: tuple[int, int], when: datetime | None = None) -> bool:
    current = when or now_kst()
    start, end = send_window
    return start <= current.hour < end


class SupabaseClient:
    def __init__(self, base_url: str, service_key: str, timeout: int = 20):
        self.rest_url = f"{base_url.rstrip('/')}/rest/v1"
        self.timeout = timeout
        self.session = requests.Session()
        self.session.headers.update({
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
            "Content-Type": "application/json",
        })

    def request(
        self,
        method: str,
        path: str,
        *,
        params: dict[str, str] | None = None,
        json_body: Any | None = None,
        headers: dict[str, str] | None = None,
    ) -> Any:
        url = f"{self.rest_url}/{path.lstrip('/')}"
        resp = self.session.request(
            method,
            url,
            params=params,
            json=json_body,
            headers=headers,
            timeout=self.timeout,
        )
        if resp.status_code >= 400:
            raise RuntimeError(f"Supabase {method} {path} failed: HTTP {resp.status_code}")
        if not resp.content:
            return None
        return resp.json()

    def rpc(self, name: str, body: dict[str, Any]) -> list[dict[str, Any]]:
        data = self.request("POST", f"rpc/{name}", json_body=body)
        return data or []

    def select(
        self,
        table: str,
        params: dict[str, str] | None = None,
        headers: dict[str, str] | None = None,
    ) -> list[dict[str, Any]]:
        data = self.request("GET", table, params=params, headers=headers)
        return data or []

    def select_all(
        self,
        table: str,
        params: dict[str, str] | None = None,
        page_size: int = 1000,
    ) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        offset = 0
        while True:
            page = self.select(
                table,
                params=params,
                headers={"Range": f"{offset}-{offset + page_size - 1}"},
            )
            rows.extend(page)
            if len(page) < page_size:
                return rows
            offset += page_size

    def patch(self, table: str, filters: dict[str, str], body: dict[str, Any]) -> None:
        self.request("PATCH", table, params=filters, json_body=body, headers={"Prefer": "return=minimal"})

    def delete(self, table: str, filters: dict[str, str]) -> None:
        self.request("DELETE", table, params=filters, headers={"Prefer": "return=minimal"})

    def upsert(self, table: str, rows: list[dict[str, Any]], on_conflict: str) -> None:
        if not rows:
            return
        self.request(
            "POST",
            table,
            params={"on_conflict": on_conflict},
            json_body=rows,
            headers={"Prefer": "resolution=merge-duplicates,return=minimal"},
        )


class GoAlimiClient:
    def __init__(self, base_url: str, timeout: int = 10):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.session = requests.Session()

    def request(self, method: str, path: str, *, json_body: Any | None = None, params: dict[str, Any] | None = None) -> Any:
        url = f"{self.base_url}/api/{path.lstrip('/')}"
        resp = self.session.request(method, url, json=json_body, params=params, timeout=self.timeout)
        if resp.status_code >= 400:
            detail = ""
            try:
                detail = resp.json().get("detail", "")
            except Exception:
                detail = resp.text[:80]
            raise GoAlimiHttpError(resp.status_code, detail)
        return resp.json()

    def post_custom(self, goalimi_student_id: int, body: str, dedupe_key: str) -> dict[str, Any]:
        return self.request(
            "POST",
            "notify/custom",
            json_body={"student_id": goalimi_student_id, "body": body, "dedupe_key": dedupe_key},
        )

    def get_custom(self, custom_id: int) -> dict[str, Any]:
        return self.request("GET", f"notify/custom/{custom_id}")

    def students(self) -> list[dict[str, Any]]:
        return self.request("GET", "golesson/students")

    def parents(self) -> list[dict[str, Any]]:
        return self.request("GET", "golesson/parents")

    def attendance(self, since_id: int = 0, days: int = 30) -> list[dict[str, Any]]:
        return self.request("GET", "golesson/attendance", params={"since_id": since_id, "days": days})


class GoAlimiHttpError(RuntimeError):
    def __init__(self, status_code: int, detail: str):
        super().__init__(f"GoAlimi HTTP {status_code}: {detail}")
        self.status_code = status_code
        self.detail = detail


class Bridge:
    def __init__(self, config: BridgeConfig, supabase: SupabaseClient, goalimi: GoAlimiClient, logger: logging.Logger):
        self.config = config
        self.supabase = supabase
        self.goalimi = goalimi
        self.logger = logger
        self.last_sync_at: datetime | None = None
        self.last_reconcile_on: str | None = None
        self.last_backup_on: str | None = None

    def run_forever(self) -> None:
        self.logger.info("Bridge started")
        self.recover_processing()
        while True:
            started = time.monotonic()
            try:
                self.run_once()
            except Exception as exc:
                self.logger.exception("Bridge cycle failed: %s", exc)
            elapsed = time.monotonic() - started
            time.sleep(max(1, self.config.poll_sec - elapsed))

    def run_once(self) -> None:
        self.heartbeat()
        self.recover_processing()
        if in_send_window(self.config.send_window):
            self.claim_and_send()
        else:
            self.logger.info("Outside send window; pending outbox stays pending")
        if self.should_sync():
            self.sync_all()
        if self.should_reconcile():
            self.reconcile_attendance()
        if self.should_backup():
            self.backup_all()

    def heartbeat(self) -> None:
        self.supabase.upsert(
            "app_settings",
            [{"key": "bridge_last_poll_at", "value": as_kst_iso()}],
            "key",
        )

    def claim_and_send(self) -> None:
        rows = self.supabase.rpc("claim_outbox", {"p_limit": 5})
        if not rows:
            return
        self.logger.info("Claimed %d outbox rows", len(rows))
        for row in rows:
            self.handle_outbox_row(row)

    def handle_outbox_row(self, row: dict[str, Any]) -> None:
        outbox_id = row["id"]
        custom_id = row.get("goalimi_custom_id")
        if not custom_id:
            try:
                goalimi_student_id = self.goalimi_student_id(row["student_id"])
                resp = self.goalimi.post_custom(goalimi_student_id, row["message"], row["dedupe_key"])
            except GoAlimiHttpError as exc:
                self.handle_goalimi_post_error(outbox_id, exc)
                return
            except requests.RequestException:
                self.logger.warning("GoAlimi unavailable; outbox %s returned to pending", outbox_id)
                self.return_to_pending(outbox_id)
                return
            custom_id = int(resp["id"])
            self.supabase.patch(
                "notification_outbox",
                {"id": f"eq.{outbox_id}"},
                {"goalimi_custom_id": custom_id},
            )
        self.poll_custom_status(row | {"goalimi_custom_id": custom_id}, max_seconds=min(60, self.config.poll_sec))

    def handle_goalimi_post_error(self, outbox_id: int, exc: GoAlimiHttpError) -> None:
        if exc.status_code in (404, 422):
            error = exc.detail or "goalimi_rejected"
            self.fail_outbox(outbox_id, error)
            self.logger.warning("GoAlimi rejected outbox %s: %s", outbox_id, error)
            return
        self.logger.warning("GoAlimi error; outbox %s returned to pending", outbox_id)
        self.return_to_pending(outbox_id)

    def recover_processing(self) -> None:
        rows = self.supabase.select(
            "notification_outbox",
            {
                "status": "eq.processing",
                "select": "id,report_id,student_id,message,dedupe_key,goalimi_custom_id,updated_at",
                "order": "updated_at",
            },
        )
        if not rows:
            return
        stale_before = datetime.now(timezone.utc) - timedelta(minutes=10)
        for row in rows:
            custom_id = row.get("goalimi_custom_id")
            if custom_id:
                self.poll_custom_status(row, max_seconds=0)
                continue
            updated_at = parse_supabase_time(row.get("updated_at"))
            if updated_at and updated_at > stale_before:
                continue
            self.logger.info("Recovering processing outbox %s without custom id", row["id"])
            self.handle_outbox_row(row)

    def poll_custom_status(self, row: dict[str, Any], max_seconds: int = 0) -> None:
        custom_id = int(row["goalimi_custom_id"])
        deadline = time.monotonic() + max_seconds
        while True:
            try:
                status = self.goalimi.get_custom(custom_id)
            except requests.RequestException:
                self.logger.warning("GoAlimi status unavailable for custom %s", custom_id)
                return
            except GoAlimiHttpError as exc:
                if exc.status_code == 404:
                    self.fail_outbox(row["id"], "custom_message_not_found")
                else:
                    self.logger.warning("GoAlimi status error for custom %s: HTTP %s", custom_id, exc.status_code)
                return

            state = status.get("status")
            if state == "sent":
                self.mark_sent(row, status.get("sent_at"))
                return
            if state == "failed":
                self.fail_outbox(row["id"], status.get("error") or "unknown")
                return
            if state not in NON_TERMINAL_CUSTOM_STATUS:
                self.fail_outbox(row["id"], f"unknown_status:{state}")
                return
            if max_seconds <= 0 or time.monotonic() >= deadline:
                return
            time.sleep(5)

    def mark_sent(self, row: dict[str, Any], sent_at: str | None) -> None:
        when = parse_goalimi_local_time(sent_at) if sent_at else as_kst_iso()
        report_id = row.get("report_id")
        if report_id:
            self.supabase.patch(
                "reports",
                {"id": f"eq.{report_id}"},
                {"status": "sent", "sent_at": when},
            )
        self.supabase.patch(
            "notification_outbox",
            {"id": f"eq.{row['id']}"},
            {"status": "sent", "sent_at": when, "error": None},
        )
        self.logger.info("Outbox %s marked sent", row["id"])

    def fail_outbox(self, outbox_id: int, error: str) -> None:
        self.supabase.patch(
            "notification_outbox",
            {"id": f"eq.{outbox_id}"},
            {"status": "failed", "error": error},
        )

    def return_to_pending(self, outbox_id: int) -> None:
        self.supabase.patch(
            "notification_outbox",
            {"id": f"eq.{outbox_id}"},
            {"status": "pending"},
        )

    def goalimi_student_id(self, student_id: int) -> int:
        rows = self.supabase.select(
            "students",
            {"id": f"eq.{student_id}", "select": "goalimi_student_id", "limit": "1"},
        )
        if not rows:
            raise RuntimeError(f"student missing for outbox: {student_id}")
        return int(rows[0]["goalimi_student_id"])

    def should_sync(self) -> bool:
        return self.last_sync_at is None or now_kst() - self.last_sync_at >= timedelta(minutes=10)

    def sync_all(self) -> None:
        self.sync_students()
        self.sync_parents()
        self.sync_attendance_incremental()
        self.last_sync_at = now_kst()

    def sync_students(self) -> None:
        rows = self.goalimi.students()
        now = as_kst_iso()
        payload = [{
            "goalimi_student_id": int(row["id"]),
            "name": row["name"],
            "grade": row.get("grade"),
            "school": row.get("school"),
            "active": bool(row.get("active")),
            "synced_at": now,
        } for row in rows]
        self.supabase.upsert("students", payload, "goalimi_student_id")
        remote_ids = {int(row["id"]) for row in rows}
        existing = self.supabase.select("students", {"select": "goalimi_student_id"})
        for row in existing:
            if int(row["goalimi_student_id"]) not in remote_ids:
                self.supabase.patch(
                    "students",
                    {"goalimi_student_id": f"eq.{row['goalimi_student_id']}"},
                    {"active": False, "synced_at": now},
                )
        self.logger.info("Synced students: %d", len(payload))

    def sync_parents(self) -> None:
        rows = self.goalimi.parents()
        student_map = self.student_id_map()
        now = as_kst_iso()
        payload: list[dict[str, Any]] = []
        for row in rows:
            local_student_id = student_map.get(int(row["student_id"]))
            if not local_student_id:
                self.logger.warning("Skipping parent %s; student not synced", row.get("id"))
                continue
            payload.append({
                "goalimi_parent_id": int(row["id"]),
                "student_id": local_student_id,
                "kakao_name": row["kakao_name"],
                "relation": row.get("relation"),
                "is_primary": bool(row.get("is_primary")),
                "notify_enabled": bool(row.get("notify_enabled")),
                "synced_at": now,
            })
        self.supabase.upsert("parents", payload, "goalimi_parent_id")
        remote_ids = {int(row["id"]) for row in rows}
        existing = self.supabase.select("parents", {"select": "goalimi_parent_id"})
        for row in existing:
            if int(row["goalimi_parent_id"]) not in remote_ids:
                self.supabase.delete("parents", {"goalimi_parent_id": f"eq.{row['goalimi_parent_id']}"})
        self.logger.info("Synced parents: %d", len(payload))

    def sync_attendance_incremental(self) -> None:
        since_id = self.max_goalimi_log_id()
        rows = self.goalimi.attendance(since_id=since_id, days=30)
        self.upsert_attendance(rows)
        self.logger.info("Synced attendance rows: %d", len(rows))

    def upsert_attendance(self, rows: list[dict[str, Any]]) -> None:
        student_map = self.student_id_map()
        payload: list[dict[str, Any]] = []
        for row in rows:
            local_student_id = student_map.get(int(row["student_id"]))
            if not local_student_id:
                self.logger.warning("Skipping attendance %s; student not synced", row.get("id"))
                continue
            payload.append({
                "goalimi_log_id": int(row["id"]),
                "student_id": local_student_id,
                "event_type": row["event_type"],
                "event_at": parse_goalimi_local_time(row["event_at"]),
            })
        self.supabase.upsert("attendance", payload, "goalimi_log_id")

    def max_goalimi_log_id(self) -> int:
        rows = self.supabase.select(
            "attendance",
            {"select": "goalimi_log_id", "order": "goalimi_log_id.desc", "limit": "1"},
        )
        return int(rows[0]["goalimi_log_id"]) if rows else 0

    def student_id_map(self) -> dict[int, int]:
        rows = self.supabase.select("students", {"select": "id,goalimi_student_id"})
        return {int(row["goalimi_student_id"]): int(row["id"]) for row in rows}

    def should_reconcile(self) -> bool:
        today = now_kst().date().isoformat()
        return self.last_reconcile_on != today and now_kst().hour >= 3

    def reconcile_attendance(self) -> None:
        remote_rows = self.goalimi.attendance(since_id=0, days=30)
        remote_ids = {int(row["id"]) for row in remote_rows}
        self.upsert_attendance(remote_rows)
        cutoff = (now_kst() - timedelta(days=30)).isoformat(timespec="seconds")
        local_rows = self.supabase.select(
            "attendance",
            {"event_at": f"gte.{cutoff}", "select": "goalimi_log_id"},
        )
        removed = 0
        for row in local_rows:
            log_id = int(row["goalimi_log_id"])
            if log_id not in remote_ids:
                self.supabase.delete("attendance", {"goalimi_log_id": f"eq.{log_id}"})
                removed += 1
        self.last_reconcile_on = now_kst().date().isoformat()
        self.logger.info("Reconciled attendance: remote=%d removed=%d", len(remote_ids), removed)

    def should_backup(self) -> bool:
        today = now_kst().date().isoformat()
        return self.last_backup_on != today and now_kst().hour >= 3

    def backup_all(self) -> None:
        target = self.config.backup_dir / now_kst().date().isoformat()
        target.mkdir(parents=True, exist_ok=True)
        for table in DEFAULT_TABLES:
            rows = self.supabase.select_all(table, {"select": "*"})
            (target / f"{table}.json").write_text(
                json.dumps(rows, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
        self.prune_backups()
        self.last_backup_on = now_kst().date().isoformat()
        self.logger.info("Backup written: %s", target)

    def prune_backups(self) -> None:
        if not self.config.backup_dir.exists():
            return
        cutoff = now_kst().date() - timedelta(days=30)
        for child in self.config.backup_dir.iterdir():
            if not child.is_dir():
                continue
            try:
                child_date = datetime.strptime(child.name, "%Y-%m-%d").date()
            except ValueError:
                continue
            if child_date < cutoff:
                for file in child.glob("*"):
                    file.unlink()
                child.rmdir()


def parse_supabase_time(value: str | None) -> datetime | None:
    if not value:
        return None
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="GoLesson Bridge")
    parser.add_argument("--config", default=str(Path(__file__).with_name("bridge_config.json")))
    parser.add_argument("--once", action="store_true", help="run one poll cycle and exit")
    args = parser.parse_args(argv)

    config_path = Path(args.config).resolve()
    config = load_config(config_path)
    logger = setup_logging(Path(__file__).resolve().parent)
    supabase = SupabaseClient(config.supabase_url, config.service_key)
    goalimi = GoAlimiClient(config.goalimi_base_url)
    bridge = Bridge(config, supabase, goalimi, logger)
    if args.once:
        bridge.run_once()
    else:
        bridge.run_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
