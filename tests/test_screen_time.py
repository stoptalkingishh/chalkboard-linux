import datetime as dt
import importlib.util
import pathlib
import sys
import tempfile
import unittest
from unittest import mock
from zoneinfo import ZoneInfo


MODULE_PATH = pathlib.Path(__file__).parents[1] / "scripts" / "fedora" / "screen-time.py"
SPEC = importlib.util.spec_from_file_location("screen_time", MODULE_PATH)
screen_time = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = screen_time
SPEC.loader.exec_module(screen_time)


class ScreenTimeTests(unittest.TestCase):
    def settings(self, windows):
        return screen_time.Settings("child", ZoneInfo("UTC"), "UTC", 5, 0, tuple(windows))

    def test_day_window_boundaries(self):
        settings = self.settings([screen_time.Window(0, 9 * 60, 10 * 60)])
        self.assertIsNotNone(screen_time.active_window(settings, dt.datetime(2026, 9, 7, 9, 0, tzinfo=dt.timezone.utc)))
        self.assertIsNone(screen_time.active_window(settings, dt.datetime(2026, 9, 7, 10, 0, tzinfo=dt.timezone.utc)))

    def test_cross_midnight_window(self):
        settings = self.settings([screen_time.Window(4, 21 * 60, 7 * 60)])
        self.assertIsNotNone(screen_time.active_window(settings, dt.datetime(2026, 9, 12, 6, 59, tzinfo=dt.timezone.utc)))
        self.assertIsNone(screen_time.active_window(settings, dt.datetime(2026, 9, 12, 7, 0, tzinfo=dt.timezone.utc)))

    def test_next_start_wraps_week(self):
        settings = self.settings([screen_time.Window(0, 9 * 60, 10 * 60)])
        now = dt.datetime(2026, 9, 7, 10, 0, tzinfo=dt.timezone.utc)
        self.assertEqual(screen_time.next_start(settings, now), dt.datetime(2026, 9, 14, 9, 0, tzinfo=dt.timezone.utc))

    def test_empty_template_is_disabled_schedule(self):
        config = pathlib.Path(__file__).parents[1] / "config" / "fedora" / "screen-time.conf"
        self.assertEqual(screen_time.load_settings(config).windows, ())

    def test_rejects_overlap_across_midnight(self):
        windows = [screen_time.Window(0, 23 * 60, 2 * 60), screen_time.Window(1, 60, 3 * 60)]
        with self.assertRaises(screen_time.ConfigError):
            screen_time.validate_overlaps(windows)

    def test_rejects_unknown_timezone(self):
        content = """[screen-time]
timezone = Not/A_Zone
user = child
warning_minutes = 5
grace_seconds = 30
[schedule]
monday =
tuesday =
wednesday =
thursday =
friday =
saturday =
sunday =
"""
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "config"
            path.write_text(content, encoding="utf-8")
            with self.assertRaises(screen_time.ConfigError):
                screen_time.load_settings(path)

    def test_release_uses_saved_user_and_expiry_without_config(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = pathlib.Path(directory)
            with mock.patch.object(screen_time, "STATE_DIR", state_dir), \
                    mock.patch.object(screen_time, "STATE_PATH", state_dir / "state.json"), \
                    mock.patch.object(screen_time, "validate_account"), \
                    mock.patch.object(screen_time, "shadow_expiry", return_value="1"), \
                    mock.patch.object(screen_time, "set_expiry") as set_expiry:
                (state_dir / "state.json").write_text(
                    '{"active": true, "user": "child", "prior_expiry": "22000"}',
                    encoding="utf-8",
                )
                screen_time.release()
                set_expiry.assert_called_once_with("child", "22000")
                self.assertFalse(screen_time.read_state()["active"])

    def test_release_refuses_system_account(self):
        class FakePwdAccount:
            pw_uid = 10

        with tempfile.TemporaryDirectory() as directory:
            state_dir = pathlib.Path(directory)
            with mock.patch.object(screen_time, "STATE_DIR", state_dir), \
                    mock.patch.object(screen_time, "STATE_PATH", state_dir / "state.json"), \
                    mock.patch("pwd.getpwnam", return_value=FakePwdAccount()), \
                    mock.patch.object(screen_time.os, "getgrouplist", return_value=[10]):
                (state_dir / "state.json").write_text(
                    '{"active": true, "user": "daemon", "prior_expiry": "22000"}',
                    encoding="utf-8",
                )
                with self.assertRaises(RuntimeError):
                    screen_time.release()

    def test_release_warns_when_account_was_already_expired(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = pathlib.Path(directory)
            with mock.patch.object(screen_time, "STATE_DIR", state_dir), \
                    mock.patch.object(screen_time, "STATE_PATH", state_dir / "state.json"), \
                    mock.patch.object(screen_time, "validate_account"), \
                    mock.patch.object(screen_time, "shadow_expiry", return_value="1"), \
                    mock.patch.object(screen_time, "set_expiry") as set_expiry:
                (state_dir / "state.json").write_text(
                    '{"active": true, "user": "child", "prior_expiry": "1", '
                    '"was_already_expired": true}',
                    encoding="utf-8",
                )
                screen_time.release()
                set_expiry.assert_called_once_with("child", "1")
                self.assertFalse(screen_time.read_state()["active"])

    def test_refuses_user_change_during_active_downtime(self):
        settings = self.settings([])
        with mock.patch.object(screen_time, "validate_account"), \
                mock.patch.object(screen_time, "read_state", return_value={"active": True, "user": "other"}):
            with self.assertRaises(RuntimeError):
                screen_time.enforce(settings, dt.datetime(2026, 9, 8, tzinfo=dt.timezone.utc))


if __name__ == "__main__":
    unittest.main()
