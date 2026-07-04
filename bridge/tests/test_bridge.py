import logging
import sys
import types
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

try:
    import requests
except ImportError:
    class RequestException(Exception):
        pass

    class ConnectionError(RequestException):
        pass

    requests = types.SimpleNamespace(
        RequestException=RequestException,
        ConnectionError=ConnectionError,
        Session=lambda: None,
    )
    sys.modules["requests"] = requests

from bridge.bridge import Bridge, BridgeConfig, GoAlimiHttpError, parse_goalimi_local_time


class FakeSupabase:
    def __init__(self):
        self.rpc_rows = []
        self.tables = {
            "students": [{"id": 1, "goalimi_student_id": 7707}],
            "parents": [],
            "attendance": [],
            "notification_outbox": [],
            "reports": [],
        }
        self.patches = []
        self.upserts = []
        self.deletes = []

    def rpc(self, name, body):
        assert name == "claim_outbox"
        rows = self.rpc_rows
        self.rpc_rows = []
        return rows

    def select(self, table, params=None):
        rows = list(self.tables.get(table, []))
        params = params or {}
        if table == "students" and "id" in params:
            wanted = int(params["id"].split(".", 1)[1])
            rows = [row for row in rows if row["id"] == wanted]
        if table == "attendance" and params.get("order") == "goalimi_log_id.desc":
            rows = sorted(rows, key=lambda row: row["goalimi_log_id"], reverse=True)
            if params.get("limit") == "1":
                rows = rows[:1]
        return rows

    def patch(self, table, filters, body):
        self.patches.append((table, filters, body))

    def upsert(self, table, rows, on_conflict):
        self.upserts.append((table, rows, on_conflict))

    def delete(self, table, filters):
        self.deletes.append((table, filters))


class FakeGoAlimi:
    def __init__(self):
        self.posts = []
        self.custom_status = {"id": 5, "status": "sent", "sent_at": "2026-07-04T15:30:00", "error": None}
        self.raise_on_post = None
        self.student_rows = []
        self.parent_rows = []
        self.attendance_rows = []

    def post_custom(self, goalimi_student_id, body, dedupe_key):
        self.posts.append((goalimi_student_id, body, dedupe_key))
        if self.raise_on_post:
            raise self.raise_on_post
        return {"id": 5, "status": "pending"}

    def get_custom(self, custom_id):
        return dict(self.custom_status)

    def students(self):
        return list(self.student_rows)

    def parents(self):
        return list(self.parent_rows)

    def attendance(self, since_id=0, days=30):
        return [row for row in self.attendance_rows if row["id"] > since_id]


def make_bridge(supabase=None, goalimi=None):
    config = BridgeConfig(
        supabase_url="http://supabase.local",
        service_key="not-a-real-key",
        goalimi_base_url="http://127.0.0.1:8000",
        poll_sec=1,
        send_window=(0, 24),
        backup_dir=Path("/tmp/golesson-bridge-test-backup"),
    )
    return Bridge(config, supabase or FakeSupabase(), goalimi or FakeGoAlimi(), logging.getLogger("test"))


class BridgeSendTests(unittest.TestCase):
    def test_send_uses_goalimi_student_id_and_marks_report_sent(self):
        supabase = FakeSupabase()
        goalimi = FakeGoAlimi()
        bridge = make_bridge(supabase, goalimi)

        bridge.handle_outbox_row({
            "id": 10,
            "report_id": 20,
            "student_id": 1,
            "message": "body",
            "dedupe_key": "report:20:v1",
        })

        self.assertEqual(goalimi.posts, [(7707, "body", "report:20:v1")])
        self.assertIn(("notification_outbox", {"id": "eq.10"}, {"goalimi_custom_id": 5}), supabase.patches)
        self.assertTrue(any(p[0] == "notification_outbox" and p[2].get("status") == "sent" for p in supabase.patches))
        self.assertTrue(any(p[0] == "reports" and p[1] == {"id": "eq.20"} and p[2].get("status") == "sent" for p in supabase.patches))

    def test_goalimi_connection_failure_returns_claimed_row_to_pending(self):
        supabase = FakeSupabase()
        goalimi = FakeGoAlimi()
        goalimi.raise_on_post = requests.ConnectionError("down")
        bridge = make_bridge(supabase, goalimi)

        bridge.handle_outbox_row({
            "id": 11,
            "report_id": 21,
            "student_id": 1,
            "message": "body",
            "dedupe_key": "report:21:v1",
        })

        self.assertIn(("notification_outbox", {"id": "eq.11"}, {"status": "pending"}), supabase.patches)

    def test_goalimi_no_primary_parent_fails_outbox_without_report_update(self):
        supabase = FakeSupabase()
        goalimi = FakeGoAlimi()
        goalimi.raise_on_post = GoAlimiHttpError(422, "no_primary_parent")
        bridge = make_bridge(supabase, goalimi)

        bridge.handle_outbox_row({
            "id": 12,
            "report_id": 22,
            "student_id": 1,
            "message": "body",
            "dedupe_key": "report:22:v1",
        })

        self.assertIn(
            ("notification_outbox", {"id": "eq.12"}, {"status": "failed", "error": "no_primary_parent"}),
            supabase.patches,
        )
        self.assertFalse(any(p[0] == "reports" for p in supabase.patches))

    def test_recover_processing_with_custom_id_polls_status_without_repost(self):
        supabase = FakeSupabase()
        supabase.tables["notification_outbox"] = [{
            "id": 13,
            "report_id": 23,
            "student_id": 1,
            "message": "body",
            "dedupe_key": "report:23:v1",
            "goalimi_custom_id": 5,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }]
        goalimi = FakeGoAlimi()
        bridge = make_bridge(supabase, goalimi)

        bridge.recover_processing()

        self.assertEqual(goalimi.posts, [])
        self.assertTrue(any(p[0] == "notification_outbox" and p[2].get("status") == "sent" for p in supabase.patches))

    def test_recover_stale_processing_without_custom_id_reposts_idempotently(self):
        supabase = FakeSupabase()
        supabase.tables["notification_outbox"] = [{
            "id": 14,
            "report_id": 24,
            "student_id": 1,
            "message": "body",
            "dedupe_key": "report:24:v1",
            "goalimi_custom_id": None,
            "updated_at": (datetime.now(timezone.utc) - timedelta(minutes=11)).isoformat(),
        }]
        goalimi = FakeGoAlimi()
        bridge = make_bridge(supabase, goalimi)

        bridge.recover_processing()

        self.assertEqual(goalimi.posts, [(7707, "body", "report:24:v1")])
        self.assertIn(("notification_outbox", {"id": "eq.14"}, {"goalimi_custom_id": 5}), supabase.patches)


class BridgeSyncTests(unittest.TestCase):
    def test_sync_maps_goalimi_ids_to_local_ids(self):
        supabase = FakeSupabase()
        goalimi = FakeGoAlimi()
        goalimi.student_rows = [{"id": 7707, "name": "신성화", "grade": None, "school": None, "active": 1}]
        goalimi.parent_rows = [{
            "id": 7001,
            "student_id": 7707,
            "kakao_name": "신성화",
            "relation": "운영자",
            "is_primary": 1,
            "notify_enabled": 1,
        }]
        goalimi.attendance_rows = [{
            "id": 9001,
            "student_id": 7707,
            "event_type": "IN",
            "event_at": "2026-07-04T09:15:32",
        }]
        bridge = make_bridge(supabase, goalimi)

        bridge.sync_students()
        bridge.sync_parents()
        bridge.sync_attendance_incremental()

        students = [u for u in supabase.upserts if u[0] == "students"][0][1]
        parents = [u for u in supabase.upserts if u[0] == "parents"][0][1]
        attendance = [u for u in supabase.upserts if u[0] == "attendance"][0][1]
        self.assertEqual(students[0]["goalimi_student_id"], 7707)
        self.assertEqual(parents[0]["student_id"], 1)
        self.assertEqual(attendance[0]["student_id"], 1)
        self.assertTrue(attendance[0]["event_at"].endswith("+09:00"))

    def test_goalimi_naive_time_is_stored_as_kst(self):
        self.assertEqual(parse_goalimi_local_time("2026-07-04T09:15:32"), "2026-07-04T09:15:32+09:00")


if __name__ == "__main__":
    unittest.main()
