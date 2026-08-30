#!/usr/bin/env python3
"""Diagnose and narrowly repair Big Red remote-control reachability from macOS."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol


SAFE_NAME = re.compile(r"^[A-Za-z0-9._-]+$")
CODEX = "/home/leo/.codex/packages/standalone/current/codex"

BIG_RED_HEALTH = f"""
printf 'network='; nmcli -t -f CONNECTIVITY general 2>/dev/null || true
printf 'tailscale='; tailscale status --json 2>/dev/null | jq -r '.BackendState // "unavailable"' || true
printf 'desktop='; if pgrep -f '^/usr/lib/chatgpt/ChatGPT$' >/dev/null 2>&1; then printf 'yes\n'; else printf 'no\n'; fi
printf 'desktop_app_server='; if pgrep -f '^/usr/lib/chatgpt/resources/codex .* app-server( |$)' >/dev/null 2>&1; then printf 'yes\n'; else printf 'no\n'; fi
printf 'standalone_remote='; if pgrep -f '^/home/leo/.codex/packages/standalone/current/codex app-server --remote-control( |$)' >/dev/null 2>&1; then printf 'yes\n'; else printf 'no\n'; fi
daemon_state="$({CODEX} app-server daemon version 2>/dev/null | jq -r '.status // "unavailable"' || true)"; [ -n "$daemon_state" ] || daemon_state=stopped; printf 'standalone_daemon=%s\n' "$daemon_state"
printf 'writer_conflict_recent='; python3 - <<'PY'
from datetime import datetime, timezone
from pathlib import Path
import re

path = Path('/home/leo/.codex/app-server-daemon/app-server.stderr.log')
recent = False
if path.exists():
    cutoff = datetime.now(timezone.utc).timestamp() - 600
    for line in path.read_text(errors='replace').splitlines()[-1000:]:
        if 'already has an active writer' not in line:
            continue
        match = re.search(r'(20\\d\\d-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\d(?:\\.\\d+)?Z)', line)
        if match and datetime.fromisoformat(match.group(1).replace('Z', '+00:00')).timestamp() >= cutoff:
            recent = True
print('yes' if recent else 'no')
PY
""".strip()

BERYL_HEALTH = """
printf 'tailscale_init='; /etc/init.d/tailscale status 2>/dev/null || true
printf 'tailscale_process='; if pidof tailscaled >/dev/null 2>&1; then printf 'yes\n'; else printf 'no\n'; fi
printf 'tailscale_cli='; if tailscale status --peers=false >/dev/null 2>&1; then printf 'yes\n'; else printf 'no\n'; fi
printf 'openclash='; /etc/init.d/openclash status 2>/dev/null || true
""".strip()

REPAIR_BERYL_TAILSCALE = "/etc/init.d/tailscale restart\nsleep 5"
REPAIR_BIG_RED_TAILSCALE = "sudo -n systemctl restart tailscaled.service\nsleep 5"
STOP_CONFLICTING_STANDALONE = f"""
{CODEX} app-server daemon disable-remote-control
{CODEX} app-server daemon stop
sleep 3
""".strip()
START_HEADLESS_REMOTE = f"""
{CODEX} app-server daemon restart
{CODEX} app-server daemon enable-remote-control
sleep 3
""".strip()


@dataclass(frozen=True)
class Result:
    returncode: int
    stdout: str = ""


class Runner(Protocol):
    def run(self, argv: list[str], timeout: int) -> Result: ...


class SubprocessRunner:
    def run(self, argv: list[str], timeout: int) -> Result:
        try:
            completed = subprocess.run(
                argv,
                check=False,
                capture_output=True,
                text=True,
                timeout=timeout,
            )
        except (OSError, subprocess.TimeoutExpired):
            return Result(124)
        return Result(completed.returncode, completed.stdout)


@dataclass(frozen=True)
class Route:
    name: str
    argv: list[str]


@dataclass(frozen=True)
class Decision:
    actions: tuple[str, ...]
    blocked: tuple[str, ...]


def safe_name(value: str) -> str:
    if not SAFE_NAME.fullmatch(value):
        raise argparse.ArgumentTypeError(
            "SSH aliases must contain only letters, numbers, dot, dash, or underscore"
        )
    return value


def parse_fields(output: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for line in output.splitlines():
        key, separator, value = line.partition("=")
        if separator and SAFE_NAME.fullmatch(key):
            fields[key] = value.strip()
    return fields


def beryl_healthy(fields: dict[str, str]) -> bool:
    return (
        fields.get("tailscale_init") == "running"
        and fields.get("tailscale_process") == "yes"
        and fields.get("tailscale_cli") == "yes"
    )


def desktop_authority_healthy(fields: dict[str, str]) -> bool:
    return (
        fields.get("desktop") == "yes"
        and fields.get("desktop_app_server") == "yes"
        and fields.get("standalone_remote") != "yes"
    )


def headless_authority_healthy(fields: dict[str, str]) -> bool:
    return (
        fields.get("desktop") != "yes"
        and fields.get("standalone_remote") == "yes"
        and fields.get("standalone_daemon") == "running"
    )


def remote_authority_healthy(fields: dict[str, str]) -> bool:
    return desktop_authority_healthy(fields) or headless_authority_healthy(fields)


def decide_actions(
    big_red: dict[str, str],
    beryl: dict[str, str],
    route: str,
    mobile_stale: bool,
) -> Decision:
    actions: list[str] = []
    blocked: list[str] = []

    if beryl.get("openclash") != "running":
        blocked.append("openclash_unhealthy_manual_recovery_required")

    network_repair = False
    if not beryl_healthy(beryl):
        actions.append("restart_beryl_tailscale")
        network_repair = True

    if big_red.get("tailscale") != "Running":
        if route == "beryl_lan":
            actions.append("restart_big_red_tailscale")
            network_repair = True
        else:
            blocked.append("big_red_tailscale_restart_requires_beryl_lan_route")

    desktop_present = big_red.get("desktop") == "yes"
    standalone_present = big_red.get("standalone_remote") == "yes"
    duplicate_authorities = desktop_present and standalone_present

    if duplicate_authorities:
        actions.append("stop_conflicting_standalone_remote")
    elif desktop_present:
        if big_red.get("desktop_app_server") != "yes":
            blocked.append("desktop_app_server_missing_manual_recovery_required")
        elif mobile_stale and big_red.get("writer_conflict_recent") != "yes":
            blocked.append("desktop_remote_reenable_required")
    elif not headless_authority_healthy(big_red):
        actions.append("start_headless_remote")

    if network_repair and desktop_present:
        blocked.append("desktop_remote_reconnect_external_validation_required")

    if big_red.get("network") != "full":
        blocked.append("big_red_network_not_full_manual_recovery_required")

    return Decision(tuple(dict.fromkeys(actions)), tuple(dict.fromkeys(blocked)))


def base_ssh(host: str, timeout: int) -> list[str]:
    return [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        f"ConnectTimeout={timeout}",
        "-o",
        "ServerAliveInterval=5",
        "-o",
        "ServerAliveCountMax=2",
        host,
    ]


def make_routes(args: argparse.Namespace) -> list[Route]:
    routes = [
        Route("beryl_lan", base_ssh(args.big_red_lan_host, args.timeout)),
        Route("big_red_tailnet", base_ssh(args.big_red_tailnet_host, args.timeout)),
    ]
    if not args.skip_canary:
        proxy = (
            f"ssh -q {args.bandwagon_host} sudo -n ip netns exec ts-egress-canary "
            "/usr/bin/tailscale --socket=/run/tailscale/ts-egress-canary.sock nc %h %p"
        )
        routes.append(
            Route(
                "bandwagon_canary",
                [
                    "ssh",
                    "-o",
                    "BatchMode=yes",
                    "-o",
                    f"ConnectTimeout={args.timeout * 2}",
                    "-o",
                    f"HostKeyAlias={args.big_red_host_key_alias}",
                    "-o",
                    f"ProxyCommand={proxy}",
                    "-i",
                    str(Path.home() / ".ssh" / "id_ed25519_big_red"),
                    f"leo@{args.big_red_tailnet_host}",
                ],
            )
        )
    return routes


def remote_run(runner: Runner, route: Route, command: str, timeout: int) -> Result:
    return runner.run([*route.argv, command], timeout)


def beryl_run(
    runner: Runner,
    route: Route,
    beryl_host: str,
    command: str,
    timeout: int,
) -> Result:
    nested = [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        f"ConnectTimeout={timeout}",
        beryl_host,
        command,
    ]
    quoted = " ".join(subprocess.list2cmdline([part]) for part in nested)
    return remote_run(runner, route, quoted, timeout * 2)


def observe(
    runner: Runner,
    route: Route,
    args: argparse.Namespace,
) -> tuple[dict[str, str], dict[str, str]]:
    big_red_result = remote_run(runner, route, BIG_RED_HEALTH, args.timeout * 2)
    beryl_result = beryl_run(runner, route, args.beryl_host, BERYL_HEALTH, args.timeout)
    big_red = parse_fields(big_red_result.stdout) if big_red_result.returncode == 0 else {}
    beryl = parse_fields(beryl_result.stdout) if beryl_result.returncode == 0 else {}
    return big_red, beryl


def acceptance(big_red: dict[str, str], beryl: dict[str, str]) -> bool:
    return (
        big_red.get("network") == "full"
        and big_red.get("tailscale") == "Running"
        and remote_authority_healthy(big_red)
        and beryl_healthy(beryl)
        and beryl.get("openclash") == "running"
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Emit a sanitized recovery receipt and optionally apply narrow repairs."
    )
    parser.add_argument("--repair", action="store_true")
    parser.add_argument(
        "--mobile-stale",
        action="store_true",
        help="refresh Codex Remote even if local health checks pass",
    )
    parser.add_argument("--timeout", type=int, default=12)
    parser.add_argument("--big-red-lan-host", type=safe_name, default="big-red-beryl")
    parser.add_argument("--big-red-tailnet-host", type=safe_name, default="big-red")
    parser.add_argument("--beryl-host", type=safe_name, default="beryl7")
    parser.add_argument("--bandwagon-host", type=safe_name, default="bandwagon")
    parser.add_argument("--big-red-host-key-alias", type=safe_name, default="192.168.5.18")
    parser.add_argument("--skip-canary", action="store_true")
    return parser


def main(argv: list[str] | None = None, runner: Runner | None = None) -> int:
    args = build_parser().parse_args(argv)
    if not 2 <= args.timeout <= 60:
        print("--timeout must be between 2 and 60 seconds", file=sys.stderr)
        return 2

    command_runner = runner or SubprocessRunner()
    attempts: list[dict[str, object]] = []
    selected: Route | None = None
    for route in make_routes(args):
        probe = remote_run(command_runner, route, "printf recovery-ok", args.timeout)
        reachable = probe.returncode == 0 and probe.stdout == "recovery-ok"
        attempts.append({"route": route.name, "reachable": reachable})
        if reachable:
            selected = route
            break

    receipt: dict[str, object] = {
        "schema_version": 1,
        "mode": "repair" if args.repair else "check",
        "mobile_stale_asserted": args.mobile_stale,
        "external_mobile_validation_required": args.mobile_stale,
        "route_attempts": attempts,
    }
    if selected is None:
        receipt.update(
            {
                "selected_route": None,
                "outcome": "unreachable",
                "actions": [],
                "blocked": ["no_big_red_ssh_route"],
            }
        )
        print(json.dumps(receipt, sort_keys=True))
        return 1

    before_big_red, before_beryl = observe(command_runner, selected, args)
    decision = decide_actions(before_big_red, before_beryl, selected.name, args.mobile_stale)
    applied: list[str] = []
    failures: list[str] = []

    if args.repair:
        for action in decision.actions:
            if action == "restart_beryl_tailscale":
                result = beryl_run(
                    command_runner,
                    selected,
                    args.beryl_host,
                    REPAIR_BERYL_TAILSCALE,
                    args.timeout + 8,
                )
            elif action == "restart_big_red_tailscale":
                result = remote_run(
                    command_runner,
                    selected,
                    REPAIR_BIG_RED_TAILSCALE,
                    args.timeout + 8,
                )
            elif action == "stop_conflicting_standalone_remote":
                result = remote_run(
                    command_runner,
                    selected,
                    STOP_CONFLICTING_STANDALONE,
                    args.timeout + 8,
                )
            else:
                result = remote_run(
                    command_runner,
                    selected,
                    START_HEADLESS_REMOTE,
                    args.timeout + 8,
                )
            if result.returncode == 0:
                applied.append(action)
            else:
                failures.append(f"{action}_failed")

    after_big_red, after_beryl = observe(command_runner, selected, args)
    healthy = acceptance(after_big_red, after_beryl)
    blocked = list(decision.blocked) + failures
    receipt.update(
        {
            "selected_route": selected.name,
            "before": {"big_red": before_big_red, "beryl": before_beryl},
            "planned_actions": list(decision.actions),
            "actions": applied,
            "blocked": blocked,
            "after": {"big_red": after_big_red, "beryl": after_beryl},
            "outcome": "healthy" if healthy and not blocked else "needs_attention",
        }
    )
    print(json.dumps(receipt, sort_keys=True))
    return 0 if healthy and not blocked else 1


if __name__ == "__main__":
    raise SystemExit(main())
