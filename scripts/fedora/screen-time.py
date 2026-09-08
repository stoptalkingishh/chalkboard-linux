#!/usr/bin/env python3

import argparse
import configparser
import datetime as dt
import json
import os
import pathlib
import stat
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

DAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
CONFIG_PATH = pathlib.Path(os.environ.get("CHALKBOARD_SCREEN_TIME_CONFIG", "/etc/chalkboard/screen-time.conf"))
STATE_DIR = pathlib.Path(os.environ.get("CHALKBOARD_SCREEN_TIME_STATE_DIR", "/var/lib/chalkboard/screen-time"))
STATE_PATH = STATE_DIR / "state.json"
LOCK_PATH = STATE_DIR / "lock"


class ConfigError(ValueError):
    pass


@dataclass(frozen=True)
class Window:
    weekday: int
    start: int
    end: int


@dataclass(frozen=True)
class Settings:
    user: str
    timezone: dt.tzinfo
    timezone_name: str
    warning_minutes: int
    grace_seconds: int
    windows: tuple[Window, ...]


def parse_time(value: str) -> int:
    try:
        parsed = dt.time.fromisoformat(value)
    except ValueError as error:
        raise ConfigError(f"invalid time {value!r}; use HH:MM") from error
    if parsed.second or parsed.microsecond or len(value) != 5:
        raise ConfigError(f"invalid time {value!r}; use HH:MM")
    return parsed.hour * 60 + parsed.minute


def expanded_ranges(window: Window) -> list[tuple[int, int]]:
    start = window.weekday * 1440 + window.start
    end = window.weekday * 1440 + window.end
    if window.end <= window.start:
        end += 1440
    if end <= 7 * 1440:
        return [(start, end)]
    return [(start, 7 * 1440), (0, end - 7 * 1440)]


def validate_overlaps(windows: list[Window]) -> None:
    ranges = sorted(item for window in windows for item in expanded_ranges(window))
    for previous, current in zip(ranges, ranges[1:]):
        if current[0] < previous[1]:
            raise ConfigError("schedule windows overlap")


def load_settings(path: pathlib.Path = CONFIG_PATH) -> Settings:
    parser = configparser.ConfigParser(interpolation=None)
    try:
        with path.open(encoding="utf-8") as config_file:
            parser.read_file(config_file)
    except (OSError, configparser.Error) as error:
        raise ConfigError(f"cannot read {path}: {error}") from error

    if set(parser.sections()) != {"screen-time", "schedule"}:
        raise ConfigError("config must contain only [screen-time] and [schedule]")
    general = parser["screen-time"]
    allowed_general = {"timezone", "user", "warning_minutes", "grace_seconds"}
    if set(general) != allowed_general:
        raise ConfigError(f"[screen-time] keys must be: {', '.join(sorted(allowed_general))}")
    if set(parser["schedule"]) != set(DAYS):
        raise ConfigError("[schedule] must contain each weekday exactly once")

    timezone_name = general["timezone"].strip()
    if timezone_name == "local":
        timezone = local_timezone()
    else:
        try:
            timezone = ZoneInfo(timezone_name)
        except ZoneInfoNotFoundError as error:
            raise ConfigError(f"unknown IANA timezone {timezone_name!r}") from error

    user = general["user"].strip()
    if not user or any(character.isspace() for character in user):
        raise ConfigError("user must be a non-empty account name without whitespace")
    try:
        warning_minutes = int(general["warning_minutes"])
        grace_seconds = int(general["grace_seconds"])
    except ValueError as error:
        raise ConfigError("warning_minutes and grace_seconds must be integers") from error
    if not 0 <= warning_minutes <= 60:
        raise ConfigError("warning_minutes must be between 0 and 60")
    if not 0 <= grace_seconds <= 120:
        raise ConfigError("grace_seconds must be between 0 and 120")

    windows = []
    for weekday, day in enumerate(DAYS):
        value = parser["schedule"][day].strip()
        if not value:
            continue
        for raw_window in value.split(","):
            parts = raw_window.strip().split("-")
            if len(parts) != 2:
                raise ConfigError(f"invalid {day} window {raw_window!r}; use HH:MM-HH:MM")
            start, end = (parse_time(part.strip()) for part in parts)
            if start == end:
                raise ConfigError(f"{day} window cannot start and end at the same time")
            windows.append(Window(weekday, start, end))
    validate_overlaps(windows)
    return Settings(user, timezone, timezone_name, warning_minutes, grace_seconds, tuple(windows))


def local_timezone() -> dt.tzinfo:
    if os.environ.get("TZ"):
        try:
            return ZoneInfo(os.environ["TZ"])
        except ZoneInfoNotFoundError as error:
            raise ConfigError(f"unknown timezone in TZ: {os.environ['TZ']!r}") from error
    localtime = pathlib.Path("/etc/localtime")
    if localtime.exists():
        resolved = localtime.resolve()
        zoneinfo_root = pathlib.Path("/usr/share/zoneinfo")
        try:
            return ZoneInfo(str(resolved.relative_to(zoneinfo_root)).replace(os.sep, "/"))
        except ValueError:
            with localtime.open("rb") as timezone_file:
                return ZoneInfo.from_file(timezone_file)
    return dt.datetime.now().astimezone().tzinfo


def active_window(settings: Settings, now: dt.datetime) -> Window | None:
    local = now.astimezone(settings.timezone)
    minute = local.hour * 60 + local.minute
    for window in settings.windows:
        if window.end > window.start:
            if local.weekday() == window.weekday and window.start <= minute < window.end:
                return window
        elif ((local.weekday() == window.weekday and minute >= window.start) or
              (local.weekday() == (window.weekday + 1) % 7 and minute < window.end)):
            return window
    return None


def next_start(settings: Settings, now: dt.datetime) -> dt.datetime | None:
    local = now.astimezone(settings.timezone)
    candidates = []
    for window in settings.windows:
        days_ahead = (window.weekday - local.weekday()) % 7
        date = local.date() + dt.timedelta(days=days_ahead)
        candidate = dt.datetime.combine(
            date, dt.time(window.start // 60, window.start % 60), settings.timezone
        )
        if candidate <= local:
            candidate += dt.timedelta(days=7)
        candidates.append(candidate)
    return min(candidates, default=None)


def check_config_security(path: pathlib.Path) -> None:
    info = path.stat()
    if info.st_uid != 0:
        raise ConfigError(f"{path} must be owned by root")
    if stat.S_IMODE(info.st_mode) & 0o022:
        raise ConfigError(f"{path} must not be writable by group or other users")


def read_state() -> dict:
    if not STATE_PATH.exists():
        return {"active": False}
    try:
        return json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"cannot read state: {error}") from error


def write_state(state: dict) -> None:
    STATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=STATE_DIR, prefix="state.")
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as state_file:
            json.dump(state, state_file, sort_keys=True)
            state_file.write("\n")
        os.replace(temporary, STATE_PATH)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def shadow_expiry(user: str) -> str:
    result = subprocess.run(
        ["getent", "shadow", user], check=True, text=True, capture_output=True
    )
    fields = result.stdout.rstrip("\n").split(":")
    if len(fields) != 9:
        raise RuntimeError(f"unexpected shadow entry for {user}")
    return fields[7]


def set_expiry(user: str, expiry: str) -> None:
    subprocess.run(["chage", "-E", expiry or "-1", user], check=True)


def notify(user: str, message: str) -> bool:
    import pwd
    try:
        uid = pwd.getpwnam(user).pw_uid
        bus = pathlib.Path(f"/run/user/{uid}/bus")
        if not bus.exists() or not pathlib.Path("/usr/bin/notify-send").exists():
            return False
        result = subprocess.run(
            ["runuser", "-u", user, "--", "env", f"DBUS_SESSION_BUS_ADDRESS=unix:path={bus}",
             "notify-send", "--urgency=critical", "--expire-time=0", "Screen time", message],
            check=False,
            timeout=8,
        )
    except (KeyError, OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0


def validate_account(user: str) -> None:
    import grp
    import pwd
    account = pwd.getpwnam(user)
    if account.pw_uid < 1000:
        raise RuntimeError(f"refusing to manage system account {user}")
    group_names = {grp.getgrgid(group_id).gr_name for group_id in os.getgrouplist(user, account.pw_gid)}
    if group_names & {"wheel", "sudo"}:
        raise RuntimeError(f"refusing to manage administrator account {user}")


def release(settings: Settings | None = None, force: bool = False) -> None:
    state = read_state()
    if not state.get("active"):
        print("Screen-time downtime is not active.")
        return
    user = state.get("user") or (settings.user if settings else None)
    if not user:
        raise RuntimeError("active state does not identify a child account")
    validate_account(user)
    current = shadow_expiry(user)
    if current != "1" and not force:
        raise RuntimeError(
            f"{user} account expiry changed outside Chalkboard; use force-release to restore the saved value"
        )
    prior = state.get("prior_expiry", "")
    if state.get("was_already_expired") and prior == "1":
        print(
            f"WARNING: {user} was already expired before Chalkboard ran; the account "
            "remains expired and Chalkboard did not silently restore an earlier value.",
            file=sys.stderr,
        )
    set_expiry(user, prior)
    write_state({"active": False})
    print(f"Released {user}; restored the previous account expiry.")


def enforce(settings: Settings, now: dt.datetime | None = None) -> int:
    """Enforce downtime and return the number of seconds to wait until the
    grace period ends (0 when no waiting is required). The grace wait must
    happen outside the caller's lock so recovery commands are not blocked."""
    validate_account(settings.user)
    now = now or dt.datetime.now(dt.timezone.utc)
    state = read_state()
    if state.get("active") and state.get("user") != settings.user:
        raise RuntimeError(
            f"downtime is active for {state.get('user')}; release it before changing user"
        )
    active = active_window(settings, now)
    if not active:
        if state.get("active"):
            release(settings)
            state = read_state()
        start = next_start(settings, now)
        if start is None or settings.warning_minutes == 0:
            return 0
        seconds = start.timestamp() - now.timestamp()
        warning_key = start.isoformat()
        if 0 < seconds <= settings.warning_minutes * 60 and state.get("warned_start") != warning_key:
            notify(settings.user, f"Downtime starts in {max(1, round(seconds / 60))} minute(s). Please save your work.")
            state["warned_start"] = warning_key
            write_state(state)
        return 0

    first_activation = not state.get("active")
    if first_activation:
        prior = shadow_expiry(settings.user)
        state = {
            "active": True,
            "grace_complete": False,
            "user": settings.user,
            "prior_expiry": prior,
            "was_already_expired": prior == "1",
        }
        write_state(state)
    if shadow_expiry(settings.user) != "1":
        set_expiry(settings.user, "1")
    if not state.get("grace_complete"):
        notify(settings.user, f"Downtime has started. Your session will close in {settings.grace_seconds} seconds.")
        grace_ends = state.get("grace_ends_at")
        if grace_ends is None:
            grace_ends = time.time() + settings.grace_seconds
            state["grace_ends_at"] = grace_ends
            write_state(state)
        remaining = grace_ends - time.time()
        if remaining > 0:
            return int(remaining) + 1
        state["grace_complete"] = True
        write_state(state)
    result = subprocess.run(["loginctl", "terminate-user", settings.user], check=False)
    if first_activation and result.returncode == 0:
        print(f"Downtime activated for {settings.user}.")
    return 0


def print_status(settings: Settings) -> None:
    state = read_state()
    now = dt.datetime.now(dt.timezone.utc)
    print(f"user: {settings.user}")
    print(f"timezone: {settings.timezone_name}")
    print(f"configured windows: {len(settings.windows)}")
    print(f"schedule currently: {'downtime' if active_window(settings, now) else 'available'}")
    print(f"enforcement state: {'active' if state.get('active') else 'released'}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Enforce parent-managed Chalkboard downtime")
    parser.add_argument("command", choices=("check", "enforce", "release", "force-release", "status"))
    args = parser.parse_args()
    try:
        effective_uid = getattr(os, "geteuid", lambda: 1)()
        if args.command != "check" and effective_uid != 0:
            raise RuntimeError("this command must run as root")
        settings = None if args.command in ("release", "force-release") else load_settings()
        if settings is not None and (args.command != "check" or effective_uid == 0):
            check_config_security(CONFIG_PATH)
        if args.command == "check":
            assert settings is not None
            print(f"Valid configuration: {len(settings.windows)} downtime window(s).")
            return 0
        STATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
        import fcntl
        grace_wait = 0
        with LOCK_PATH.open("a", encoding="utf-8") as lock_file:
            os.chmod(LOCK_PATH, 0o600)
            fcntl.flock(lock_file, fcntl.LOCK_EX)
            if args.command == "enforce":
                assert settings is not None
                grace_wait = enforce(settings)
            elif args.command in ("release", "force-release"):
                release(settings, force=args.command == "force-release")
            else:
                assert settings is not None
                print_status(settings)
        # The grace delay must not hold the lock, or recovery commands would
        # block for the whole grace period. Re-check after the delay so a
        # parent-issued release made during grace is honored.
        if grace_wait > 0:
            time.sleep(grace_wait)
            with LOCK_PATH.open("a", encoding="utf-8") as lock_file:
                os.chmod(LOCK_PATH, 0o600)
                fcntl.flock(lock_file, fcntl.LOCK_EX)
                assert settings is not None
                enforce(settings)
        return 0
    except (ConfigError, KeyError, OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"chalkboard-screen-time: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
