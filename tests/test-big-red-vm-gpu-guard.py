#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import Mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader(
    'gpu_guard', str(ROOT / 'scripts/big-red-vm-gpu-guard'))
guard = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(guard)


class GuardTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.gpu = pathlib.Path(self.tmp.name) / 'gpu'
        self.gpu.mkdir()
        self.run = Mock(return_value=subprocess.CompletedProcess([], 3, 'inactive\n', ''))

    def driver(self, name):
        target = self.gpu.parent / name
        target.mkdir()
        (self.gpu / 'driver').symlink_to(target)

    def test_linux_drivers_refused_without_any_service_action(self):
        for name in ('i915', 'xe'):
            with self.subTest(name=name):
                self.driver(name)
                with self.assertRaisesRegex(RuntimeError, 'refusing automatic detach'):
                    guard.check(self.gpu, self.run)
                self.run.assert_not_called()
                (self.gpu / 'driver').unlink()

    def test_missing_driver_refused(self):
        with self.assertRaisesRegex(RuntimeError, 'unavailable'):
            guard.check(self.gpu, self.run)

    def test_prebound_vfio_and_stopped_gdm_allowed(self):
        self.driver('vfio-pci')
        guard.check(self.gpu, self.run)
        self.assertEqual(self.run.call_args.args[0], ['/usr/bin/systemctl', 'is-active', 'gdm.service'])

    def test_unknown_active_or_transitioning_gdm_refused(self):
        self.driver('vfio-pci')
        for code, state in ((0, 'active'), (0, 'activating'), (3, 'deactivating'),
                            (3, 'failed'), (4, 'unknown'), (1, 'inactive')):
            with self.subTest(state=state, code=code):
                self.run.return_value = subprocess.CompletedProcess([], code, state, '')
                with self.assertRaisesRegex(RuntimeError, 'not confirmed inactive'):
                    guard.check(self.gpu, self.run)

    def test_hook_blocks_before_cpu_mutations(self):
        hook = (ROOT / 'libvirt/qemu').read_text()
        # Exercise real shell dispatch with an inert failing guard and CPU spy.
        marker = self.gpu.parent / 'effect'
        guard_path = self.gpu.parent / 'deny'
        guard_path.write_text('#!/bin/sh\nexit 1\n')
        guard_path.chmod(0o755)
        hook = hook.replace('/usr/local/sbin/big-red-vm-gpu-guard', str(guard_path))
        hook = hook.replace('systemctl set-property', f'touch {marker}; false')
        for operation in ('prepare', 'start', 'restore', 'migrate'):
            result = subprocess.run(['bash', '-c', hook, 'hook', 'win11-starsector', operation, 'begin'], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(marker.exists())
        for vm, operation, phase in (('other', 'prepare', 'begin'),
                                      ('win11-starsector', 'reconnect', 'begin'),
                                      ('win11-starsector', 'started', 'begin')):
            result = subprocess.run(['bash', '-c', hook, 'hook', vm, operation, phase], capture_output=True)
            self.assertEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
