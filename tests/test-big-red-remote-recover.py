#!/usr/bin/env python3

import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts" / "big-red-remote-recover.py"
SPEC = importlib.util.spec_from_file_location("big_red_remote_recover", SCRIPT)
assert SPEC and SPEC.loader
RECOVER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = RECOVER
SPEC.loader.exec_module(RECOVER)


class DecisionTests(unittest.TestCase):
    def setUp(self):
        self.big_red = {
            "network": "full",
            "tailscale": "Running",
            "desktop": "yes",
            "desktop_app_server": "yes",
            "standalone_remote": "no",
            "standalone_daemon": "stopped",
            "writer_conflict_recent": "no",
        }
        self.beryl = {
            "tailscale_init": "running",
            "tailscale_process": "yes",
            "tailscale_cli": "yes",
            "openclash": "running",
        }

    def test_healthy_state_is_noop(self):
        decision = RECOVER.decide_actions(self.big_red, self.beryl, "beryl_lan", False)
        self.assertEqual(decision.actions, ())
        self.assertEqual(decision.blocked, ())

    def test_mobile_stale_without_duplicate_requires_desktop_reenable(self):
        decision = RECOVER.decide_actions(self.big_red, self.beryl, "beryl_lan", True)
        self.assertEqual(decision.actions, ())
        self.assertEqual(decision.blocked, ("desktop_remote_reenable_required",))

    def test_duplicate_authority_stops_only_standalone(self):
        self.big_red["standalone_remote"] = "yes"
        self.big_red["standalone_daemon"] = "running"
        self.big_red["writer_conflict_recent"] = "yes"
        decision = RECOVER.decide_actions(self.big_red, self.beryl, "beryl_lan", True)
        self.assertEqual(decision.actions, ("stop_conflicting_standalone_remote",))
        self.assertEqual(decision.blocked, ())

    def test_beryl_failure_repairs_network_and_requires_external_validation(self):
        self.beryl["tailscale_cli"] = "no"
        decision = RECOVER.decide_actions(self.big_red, self.beryl, "big_red_tailnet", False)
        self.assertEqual(decision.actions, ("restart_beryl_tailscale",))
        self.assertEqual(
            decision.blocked,
            ("desktop_remote_reconnect_external_validation_required",),
        )

    def test_headless_host_starts_managed_remote(self):
        self.big_red.update(
            {
                "desktop": "no",
                "desktop_app_server": "no",
                "standalone_remote": "no",
                "standalone_daemon": "stopped",
            }
        )
        decision = RECOVER.decide_actions(self.big_red, self.beryl, "beryl_lan", False)
        self.assertEqual(decision.actions, ("start_headless_remote",))
        self.assertEqual(decision.blocked, ())

    def test_big_red_tailscale_restart_requires_independent_route(self):
        self.big_red["tailscale"] = "Stopped"
        direct = RECOVER.decide_actions(self.big_red, self.beryl, "beryl_lan", False)
        self.assertIn("restart_big_red_tailscale", direct.actions)
        relayed = RECOVER.decide_actions(self.big_red, self.beryl, "big_red_tailnet", False)
        self.assertNotIn("restart_big_red_tailscale", relayed.actions)
        self.assertIn(
            "big_red_tailscale_restart_requires_beryl_lan_route",
            relayed.blocked,
        )

    def test_openclash_is_never_auto_restarted(self):
        self.beryl["openclash"] = "stopped"
        decision = RECOVER.decide_actions(self.big_red, self.beryl, "beryl_lan", False)
        self.assertNotIn("restart_openclash", decision.actions)
        self.assertIn("openclash_unhealthy_manual_recovery_required", decision.blocked)

    def test_field_parser_ignores_unstructured_output(self):
        parsed = RECOVER.parse_fields("network=full\nprivate noise\nremote=ready\n")
        self.assertEqual(parsed, {"network": "full", "remote": "ready"})


if __name__ == "__main__":
    unittest.main()
