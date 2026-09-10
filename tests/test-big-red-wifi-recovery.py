#!/usr/bin/env python3
"""Tests for the Wi-Fi adapter recovery that runs after NetworkManager gives up."""
import importlib.machinery
import importlib.util
import pathlib
import subprocess
import unittest
from unittest.mock import Mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader(
    'wifi_recovery', str(ROOT / 'scripts/big-red-wifi-recovery'))
recovery = importlib.util.module_from_spec(
    importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(recovery)

HEALTHY_ADDRS = ('1: lo    inet 127.0.0.1/8 scope host lo\n'
                 '2: wlp0s20f3    inet 192.168.8.107/24 scope global wlp0s20f3\n'
                 '4: virbr0    inet 192.168.122.1/24 scope global virbr0')
# What the host looked like during the 2026-09-10 outage: libvirt's bridge and
# the VM's tap were up, the uplink was not.
OUTAGE_ADDRS = ('4: virbr0    inet 192.168.122.1/24 scope global virbr0\n'
                '7: vnet0    inet 192.168.122.1/24 scope global vnet0')
# Wi-Fi dies while Tailscale is already up: the overlay keeps its address even
# though nothing can reach the host through it.
STALE_OVERLAY_ADDRS = ('4: virbr0    inet 192.168.122.1/24 scope global virbr0\n'
                       '5: tailscale0    inet 100.105.182.87/32 scope global tailscale0')


def completed(rc=0, out='', err=''):
    return subprocess.CompletedProcess([], rc, out, err)


class Answers:
    """Stand in for the read-only commands the recovery consults."""

    def __init__(self, addrs=OUTAGE_ADDRS, blocked=False, gave_up=True,
                 unload=0, load=0):
        self.addrs, self.blocked, self.gave_up = addrs, blocked, gave_up
        self.unload, self.load = unload, load
        self.calls = []

    def __call__(self, argv, timeout=60):
        self.calls.append(argv)
        if argv[0].endswith('ip'):
            return completed(0, self.addrs)
        if argv[0].endswith('rfkill'):
            return completed(0, f'\tSoft blocked: {"yes" if self.blocked else "no"}')
        if argv[0].endswith('journalctl'):
            return completed(0, recovery.GIVING_UP if self.gave_up else 'all fine')
        if argv[0].endswith('modprobe'):
            return completed(self.unload if '-r' in argv else self.load, '', 'boom')
        if argv[0].endswith('nmcli'):
            return completed(0)
        raise AssertionError(f'unexpected command {argv}')


class DiagnosisTest(unittest.TestCase):
    def test_a_reachable_host_is_never_touched(self):
        run = Answers(addrs=HEALTHY_ADDRS)
        should, reason = recovery.diagnose(run)
        self.assertFalse(should)
        self.assertIn('192.168.8.107', reason)

    def test_libvirt_addresses_do_not_count_as_reachable(self):
        # The exact trap from the outage: virbr0 and vnet0 were up throughout.
        run = Answers(addrs=OUTAGE_ADDRS)
        should, _ = recovery.diagnose(run)
        self.assertTrue(should)

    def test_a_stale_tailscale_address_does_not_look_like_reachability(self):
        # tailscale0 outlives the uplink. Counting it would disable the recovery
        # in precisely the case it exists for.
        run = Answers(addrs=STALE_OVERLAY_ADDRS)
        should, _ = recovery.diagnose(run)
        self.assertTrue(should)

    def test_a_deliberately_blocked_radio_is_left_alone(self):
        run = Answers(blocked=True)
        should, reason = recovery.diagnose(run)
        self.assertFalse(should)
        self.assertIn('blocked', reason)

    def test_networkmanager_giving_up_is_recognised(self):
        run = Answers(gave_up=True)
        should, reason = recovery.diagnose(run)
        self.assertTrue(should)
        self.assertIn('gave up', reason)

    def test_no_address_still_retries_even_without_the_giving_up_line(self):
        run = Answers(gave_up=False)
        should, _ = recovery.diagnose(run)
        self.assertTrue(should)

    def test_reachability_is_checked_before_anything_else(self):
        run = Answers(addrs=HEALTHY_ADDRS)
        recovery.diagnose(run)
        self.assertEqual(len(run.calls), 1, 'a reachable host must short-circuit')


class ReloadTest(unittest.TestCase):
    def test_reload_unloads_then_loads_then_nudges_networkmanager(self):
        run = Answers()
        ok, detail = recovery.reload_driver(run)
        self.assertTrue(ok, detail)
        self.assertEqual([c[0].rsplit('/', 1)[-1] for c in run.calls],
                         ['modprobe', 'modprobe', 'nmcli'])
        self.assertIn('-r', run.calls[0])
        self.assertNotIn('-r', run.calls[1])

    def test_failed_unload_does_not_pretend_to_have_recovered(self):
        run = Answers(unload=1)
        ok, detail = recovery.reload_driver(run)
        self.assertFalse(ok)
        self.assertIn('could not unload', detail)
        self.assertEqual(len(run.calls), 1, 'must not load after a failed unload')

    def test_failed_load_is_reported(self):
        run = Answers(load=1)
        ok, detail = recovery.reload_driver(run)
        self.assertFalse(ok)
        self.assertIn('could not load', detail)


class TimerTest(unittest.TestCase):
    def test_timer_fires_after_networkmanager_would_have_given_up(self):
        text = (ROOT / 'systemd/big-red-wifi-recovery.timer').read_text()
        self.assertIn('OnBootSec=110s', text)
        self.assertIn('OnUnitActiveSec=60s', text)
        self.assertIn('WantedBy=timers.target', text)

    def test_service_does_not_depend_on_the_network_it_repairs(self):
        text = (ROOT / 'systemd/big-red-wifi-recovery.service').read_text()
        self.assertNotIn('Requires=', text)
        self.assertNotIn('BindsTo=', text)
        self.assertNotIn('network-online.target', text)


if __name__ == '__main__':
    unittest.main()
