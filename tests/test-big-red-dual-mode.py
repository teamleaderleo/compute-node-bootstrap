#!/usr/bin/env python3
"""Tests for Big Red's reboot-based Linux/Windows GPU dual mode."""
import ast
import importlib.machinery
import importlib.util
import os
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import Mock

ROOT = pathlib.Path(__file__).resolve().parents[1]

LINUX_CMDLINE = ('BOOT_IMAGE=/boot/vmlinuz-7.0.0-31-generic root=UUID=abc ro quiet splash '
                 'intel_iommu=on iommu=pt crashkernel=2G-4G:320M')
WINDOWS_CMDLINE = ('BOOT_IMAGE=/boot/vmlinuz root=UUID=abc ro intel_iommu=on iommu=pt '
                   'crashkernel=2G-4G:320M vfio-pci.ids=8086:7d51 rd.driver.pre=vfio_pci '
                   'modprobe.blacklist=i915,xe initcall_blacklist=sysfb_init '
                   'systemd.unit=multi-user.target bigred.mode=windows')


def load(relative_path, name):
    loader = importlib.machinery.SourceFileLoader(name, str(ROOT / relative_path))
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader(name, loader))
    loader.exec_module(module)
    return module


observe = load('scripts/big-red-handover-observe', 'handover_observe')
boot_mode = load('scripts/big-red-boot-mode', 'boot_mode')
windows_start = load('scripts/big-red-windows-mode-start', 'windows_mode_start')


def completed(returncode, stdout='', stderr=''):
    return subprocess.CompletedProcess([], returncode, stdout, stderr)


def literal_commands(path):
    """Yield every fully literal argv list that appears in a script."""
    for node in ast.walk(ast.parse(pathlib.Path(path).read_text())):
        if not isinstance(node, ast.Call) or not node.args:
            continue
        first = node.args[0]
        if not isinstance(first, ast.List) or not first.elts:
            continue
        if all(isinstance(e, ast.Constant) and isinstance(e.value, str) for e in first.elts):
            argv = [e.value for e in first.elts]
            if argv[0].startswith('/'):
                yield argv


class DeviceFixture:
    """A minimal sysfs PCI device tree."""

    def __init__(self, root, driver=None, drm_nodes=(), group_members=('0000:00:02.0',)):
        self.root = pathlib.Path(root)
        self.device = self.root / 'device'
        self.device.mkdir(parents=True)
        (self.device / 'modalias').write_text('pci:v00008086d00007D51\n')
        (self.device / 'boot_vga').write_text('1\n')
        if driver:
            target = self.root / driver
            target.mkdir(exist_ok=True)
            (self.device / 'driver').symlink_to(target)
        if drm_nodes:
            drm = self.device / 'drm'
            drm.mkdir()
            for node in drm_nodes:
                (drm / node).mkdir()
        if group_members is not None:
            group = self.root / '0'
            (group / 'devices').mkdir(parents=True)
            for member in group_members:
                (group / 'devices' / member).mkdir()
            (self.device / 'iommu_group').symlink_to(group)


class BootModeParsingTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = pathlib.Path(self.tmp.name)

    def observe_cmdline(self, text):
        path = self.dir / 'cmdline'
        path.write_text(text + '\n')
        original = observe.CMDLINE
        observe.CMDLINE = path
        self.addCleanup(lambda: setattr(observe, 'CMDLINE', original))
        grubenv = self.dir / 'grubenv'
        grubenv.write_text('# GRUB Environment Block\n' + '#' * 20 + '\n')
        original_env = observe.GRUBENV
        observe.GRUBENV = grubenv
        self.addCleanup(lambda: setattr(observe, 'GRUBENV', original_env))
        return observe.observe_boot_mode()

    def test_default_boot_declares_no_windows_mode(self):
        report = self.observe_cmdline(LINUX_CMDLINE)
        self.assertIn('linux', report['declared_mode'])
        self.assertIsNone(report['vfio_pci_ids'])
        self.assertIsNone(report['modprobe_blacklist'])
        self.assertFalse(report['early_vfio_load'])
        self.assertFalse(report['sysfb_blacklisted'])
        self.assertEqual(report['iommu'], ['intel_iommu=on', 'iommu=pt'])

    def test_windows_boot_reports_every_handover_argument(self):
        report = self.observe_cmdline(WINDOWS_CMDLINE)
        self.assertEqual(report['declared_mode'], 'windows')
        self.assertEqual(report['vfio_pci_ids'], '8086:7d51')
        self.assertEqual(report['modprobe_blacklist'], 'i915,xe')
        self.assertEqual(report['systemd_unit_argument'], 'multi-user.target')
        self.assertTrue(report['early_vfio_load'])
        self.assertTrue(report['sysfb_blacklisted'])

    def test_armed_entry_is_read_from_grubenv(self):
        grubenv = self.dir / 'grubenv'
        grubenv.write_text('# GRUB Environment Block\nnext_entry=big-red-windows-vfio\n####\n')
        self.assertEqual(boot_mode.armed_entry(grubenv), 'big-red-windows-vfio')
        grubenv.write_text('# GRUB Environment Block\n####\n')
        self.assertIsNone(boot_mode.armed_entry(grubenv))
        self.assertIsNone(boot_mode.armed_entry(self.dir / 'absent'))


class ObservationTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def use(self, **kwargs):
        fixture = DeviceFixture(self.tmp.name, **kwargs)
        original = observe.GPU_PATH
        observe.GPU_PATH = fixture.device
        self.addCleanup(lambda: setattr(observe, 'GPU_PATH', original))
        return fixture

    def test_linux_ownership_is_reported_as_linux(self):
        self.use(driver='i915', drm_nodes=('card0', 'renderD128'))
        gpu = observe.observe_gpu()
        self.assertEqual(gpu['driver'], 'i915')
        self.assertTrue(gpu['owned_by_linux'])
        self.assertFalse(gpu['owned_by_vfio'])
        self.assertEqual(observe.observe_drm_users()['nodes'], ['card0', 'renderD128'])

    def test_vfio_ownership_exposes_no_drm_nodes(self):
        self.use(driver='vfio-pci')
        gpu = observe.observe_gpu()
        self.assertTrue(gpu['owned_by_vfio'])
        self.assertFalse(gpu['owned_by_linux'])
        self.assertEqual(observe.observe_drm_users()['nodes'], [])

    def test_unbound_gpu_reports_no_driver_rather_than_failing(self):
        self.use()
        self.assertIsNone(observe.observe_gpu()['driver'])

    def test_iommu_group_membership_is_reported(self):
        self.use(driver='vfio-pci')
        group = observe.observe_iommu()
        self.assertEqual(group['members'], ['0000:00:02.0'])
        self.assertTrue(group['gpu_is_alone'])

    def test_shared_iommu_group_is_visible(self):
        self.use(driver='vfio-pci', group_members=('0000:00:02.0', '0000:00:02.1'))
        self.assertFalse(observe.observe_iommu()['gpu_is_alone'])

    def test_render_survives_a_fully_unavailable_host(self):
        self.use()
        report = observe.observe('win11-starsector')
        text = observe.render(report)
        for heading in ('BOOT MODE', 'GPU DRIVER OWNERSHIP', 'IOMMU GROUP', 'DRM USERS',
                        'GRAPHICAL SESSION', 'WINDOWS VM', 'REMOTE RECOVERY'):
            self.assertIn(heading, text)

    def test_observation_only_runs_read_only_commands(self):
        # Every literal argv in the observation command must be a query. Reading
        # driver_override is fine; running anything that could change it is not.
        allowed = {
            ('/usr/bin/systemctl', 'is-active'),
            ('/usr/bin/systemctl', 'is-enabled'),
            ('/usr/bin/systemctl', 'get-default'),
            ('/usr/bin/loginctl', 'list-sessions'),
            ('/usr/bin/virsh', 'domstate'),
            ('/usr/bin/ss', '-tlnH'),
            ('/usr/bin/tailscale', 'ip'),
            ('/usr/sbin/ip', 'addr'),
        }
        for argv in literal_commands(ROOT / 'scripts/big-red-handover-observe'):
            verbs = [a for a in argv[1:] if not a.startswith('-')] or ['']
            candidates = {(argv[0], argv[1])} | {(argv[0], verb) for verb in verbs}
            self.assertTrue(candidates & allowed,
                            f'observation runs a command that is not a known query: {argv}')

    def test_observation_writes_nothing(self):
        source = ast.parse((ROOT / 'scripts/big-red-handover-observe').read_text())
        writers = {'write_text', 'write_bytes', 'mkdir', 'symlink_to', 'unlink', 'rmdir',
                   'touch', 'chmod', 'rename', 'replace', 'remove', 'symlink'}
        found = {node.func.attr for node in ast.walk(source)
                 if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                 and node.func.attr in writers}
        self.assertEqual(found, set(), f'observation must not write: {found}')


class WindowsModeStartTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = pathlib.Path(self.tmp.name)
        self.cmdline = self.dir / 'cmdline'
        self.cmdline.write_text(WINDOWS_CMDLINE + '\n')

    def fixture(self, **kwargs):
        kwargs.setdefault('driver', 'vfio-pci')
        return DeviceFixture(tempfile.mkdtemp(dir=self.dir), **kwargs)

    def answers(self, gdm=(3, 'inactive'), ssh='active', tailscale='active', domstate='shut off'):
        def run(argv, timeout=60):
            if argv[:2] == ['/usr/bin/systemctl', 'is-active']:
                unit = argv[2]
                if unit == 'gdm.service':
                    return completed(gdm[0], gdm[1])
                return completed(0, ssh if unit == 'ssh.service' else tailscale)
            if 'domstate' in argv:
                return completed(0, domstate)
            raise AssertionError(f'unexpected command {argv}')
        return Mock(side_effect=run)

    def test_prerequisites_met_on_a_real_windows_boot(self):
        device = self.fixture().device
        self.assertEqual(windows_start.unmet(device, self.cmdline, self.answers()), [])

    def test_linux_ownership_refuses_and_never_detaches(self):
        device = self.fixture(driver='i915', drm_nodes=('card0',)).device
        run = self.answers()
        problems = windows_start.unmet(device, self.cmdline, run)
        self.assertTrue(any('belongs to i915' in p for p in problems))
        self.assertTrue(any('DRM nodes card0' in p for p in problems))
        self.assertTrue(os.path.basename(os.readlink(device / 'driver')) == 'i915')

    def test_unbound_gpu_refuses(self):
        device = self.fixture(driver=None).device
        problems = windows_start.unmet(device, self.cmdline, self.answers())
        self.assertTrue(any('no driver bound' in p for p in problems))

    def test_active_gdm_refuses(self):
        device = self.fixture().device
        problems = windows_start.unmet(device, self.cmdline, self.answers(gdm=(0, 'active')))
        self.assertTrue(any('not confirmed inactive' in p for p in problems))

    def test_lost_remote_recovery_refuses(self):
        device = self.fixture().device
        for down in ('ssh', 'tailscale'):
            with self.subTest(unit=down):
                run = self.answers(**{down: 'inactive'})
                problems = windows_start.unmet(device, self.cmdline, run)
                self.assertTrue(any('no remote recovery path' in p for p in problems))

    def test_running_domain_refuses(self):
        device = self.fixture().device
        problems = windows_start.unmet(device, self.cmdline, self.answers(domstate='running'))
        self.assertTrue(any('not shut off' in p for p in problems))

    def test_linux_boot_refuses_even_if_the_unit_is_invoked_by_hand(self):
        device = self.fixture().device
        linux = self.dir / 'linux-cmdline'
        linux.write_text(LINUX_CMDLINE + '\n')
        problems = windows_start.unmet(device, linux, self.answers())
        self.assertTrue(any('bigred.mode=windows' in p for p in problems))

    def test_shared_iommu_group_refuses(self):
        device = self.fixture(group_members=('0000:00:02.0', '0000:00:1f.3')).device
        problems = windows_start.unmet(device, self.cmdline, self.answers())
        self.assertTrue(any('0000:00:1f.3' in p for p in problems))

    def test_starter_performs_no_detachment(self):
        source = (ROOT / 'scripts/big-red-windows-mode-start').read_text()
        for forbidden in ('driver_override', 'unbind', 'drivers_probe', 'nodedev-detach',
                          'remove_id', 'new_id'):
            self.assertNotIn(f"'{forbidden}", source)
            self.assertNotIn(f'/{forbidden}', source)


class BootModePreflightTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = pathlib.Path(self.tmp.name)
        self.grub_cfg = self.dir / 'grub.cfg'
        self.grub_cfg.write_text("menuentry 'Big Red' --id big-red-windows-vfio {\n}\n")
        self.guard = self.dir / 'guard'
        self.guard.write_text('#!/bin/sh\n')

    def answers(self, domstate='shut off', enabled='enabled', ssh='active', tailscale='active'):
        def run(argv, timeout=30):
            if 'domstate' in argv:
                return completed(0, domstate)
            if argv[:2] == ['/usr/bin/systemctl', 'is-enabled']:
                return completed(0, enabled)
            if argv[:2] == ['/usr/bin/systemctl', 'is-active']:
                return completed(0, ssh if argv[2] == 'ssh.service' else tailscale)
            raise AssertionError(f'unexpected command {argv}')
        return Mock(side_effect=run)

    def test_healthy_host_may_arm_windows(self):
        self.assertEqual(
            boot_mode.preflight(self.grub_cfg, self.guard, self.answers()), [])

    def test_missing_grub_entry_refuses(self):
        self.grub_cfg.write_text("menuentry 'Ubuntu' {\n}\n")
        problems = boot_mode.preflight(self.grub_cfg, self.guard, self.answers())
        self.assertTrue(any('update-grub' in p for p in problems))

    def test_missing_pr40_guard_refuses(self):
        problems = boot_mode.preflight(self.grub_cfg, self.dir / 'absent', self.answers())
        self.assertTrue(any('PR #40 GPU guard is missing' in p for p in problems))

    def test_running_domain_refuses(self):
        problems = boot_mode.preflight(self.grub_cfg, self.guard, self.answers(domstate='running'))
        self.assertTrue(any('not shut off' in p for p in problems))

    def test_disabled_windows_unit_refuses(self):
        problems = boot_mode.preflight(self.grub_cfg, self.guard, self.answers(enabled='disabled'))
        self.assertTrue(any('would not start in Windows mode' in p for p in problems))

    def test_lost_remote_path_refuses(self):
        problems = boot_mode.preflight(self.grub_cfg, self.guard, self.answers(tailscale='inactive'))
        self.assertTrue(any('unreachable after the reboot' in p for p in problems))


class GrubEntryTest(unittest.TestCase):
    """Run the real /etc/grub.d snippet against a stubbed boot layout."""

    def render(self, boot_mount='/', default_args='quiet splash intel_iommu=on iommu=pt '
                                                  'crashkernel=2G-4G:320M'):
        tmp = tempfile.mkdtemp()
        self.addCleanup(lambda: subprocess.run(['rm', '-rf', tmp], check=False))
        stub_dir = pathlib.Path(tmp) / 'bin'
        stub_dir.mkdir()
        findmnt = stub_dir / 'findmnt'
        findmnt.write_text(
            '#!/bin/sh\n'
            'for a in "$@"; do\n'
            '  case "$a" in\n'
            f'    UUID) echo 267525b1-36d5-4051-ab56-14b259b40e59; exit 0 ;;\n'
            f'    TARGET) echo "{boot_mount}"; exit 0 ;;\n'
            '  esac\n'
            'done\n')
        findmnt.chmod(0o755)
        boot = pathlib.Path(tmp) / 'boot'
        boot.mkdir()
        (boot / 'vmlinuz').write_text('')
        (boot / 'initrd.img').write_text('')
        script = (ROOT / 'boot/grub.d/42_big_red_windows_mode').read_text()
        script = script.replace('[ -e /boot/vmlinuz ] && [ -e /boot/initrd.img ]',
                                f'[ -e {boot}/vmlinuz ] && [ -e {boot}/initrd.img ]')
        environment = dict(os.environ,
                           PATH=f'{stub_dir}:{os.environ["PATH"]}',
                           GRUB_CMDLINE_LINUX_DEFAULT=default_args,
                           GRUB_CMDLINE_LINUX='')
        return subprocess.run(['sh', '-c', script], capture_output=True, text=True,
                              env=environment, check=False)

    def test_entry_carries_every_handover_argument(self):
        result = self.render()
        self.assertEqual(result.returncode, 0, result.stderr)
        for required in ('--id big-red-windows-vfio', 'vfio-pci.ids=8086:7d51',
                         'rd.driver.pre=vfio_pci', 'modprobe.blacklist=i915,xe',
                         'initcall_blacklist=sysfb_init', 'systemd.unit=multi-user.target',
                         'bigred.mode=windows', 'crashkernel=2G-4G:320M',
                         'intel_iommu=on', 'iommu=pt'):
            self.assertIn(required, result.stdout)

    def test_entry_uses_the_upgrade_stable_boot_symlinks(self):
        result = self.render()
        self.assertIn('linux\t/boot/vmlinuz root=UUID=', result.stdout)
        self.assertIn('initrd\t/boot/initrd.img', result.stdout)
        self.assertNotIn('vmlinuz-7.', result.stdout)

    def test_splash_is_dropped_so_the_handover_boot_is_legible(self):
        result = self.render()
        linux_line = [l for l in result.stdout.splitlines() if l.strip().startswith('linux')][0]
        self.assertNotIn('quiet', linux_line)
        self.assertNotIn('splash', linux_line)

    def test_separate_boot_partition_uses_partition_relative_paths(self):
        result = self.render(boot_mount='/boot')
        self.assertIn('linux\t/vmlinuz root=UUID=', result.stdout)
        self.assertIn('initrd\t/initrd.img', result.stdout)

    def test_unexpected_boot_layout_emits_no_entry_instead_of_a_broken_one(self):
        result = self.render(boot_mount='/srv/weird')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), '')
        self.assertIn('skipping Windows entry', result.stderr)


class InstalledConfigurationTest(unittest.TestCase):
    def test_default_grub_arguments_never_hand_the_gpu_away(self):
        text = (ROOT / 'boot/grub.d/90-preflight-arc-vfio.cfg').read_text()
        default = [l for l in text.splitlines() if l.startswith('GRUB_CMDLINE_LINUX_DEFAULT=')][0]
        for forbidden in ('vfio-pci.ids=', 'modprobe.blacklist=', 'initcall_blacklist=',
                          'bigred.mode='):
            self.assertNotIn(forbidden, default)
        self.assertIn('intel_iommu=on', default)

    def test_modprobe_fragment_declares_no_active_directive(self):
        text = (ROOT / 'boot/modprobe.d/90-preflight-arc-vfio.conf').read_text()
        active = [l for l in text.splitlines() if l.strip() and not l.startswith('#')]
        self.assertEqual(active, [], f'unexpected active modprobe directives: {active}')

    def test_dracut_fragment_ships_modules_without_forcing_them(self):
        text = (ROOT / 'boot/dracut.conf.d/90-preflight-arc-vfio.conf').read_text()
        directives = [l for l in text.splitlines() if l.strip() and not l.lstrip().startswith('#')]
        self.assertTrue(any(l.startswith('add_drivers+=') for l in directives), directives)
        self.assertFalse(any('force_drivers' in l for l in directives),
                         f'dracut must not force-load vfio_pci on every boot: {directives}')

    def test_windows_unit_is_conditioned_and_never_blocks_the_boot(self):
        text = (ROOT / 'systemd/big-red-windows-mode.service').read_text()
        self.assertIn('ConditionKernelCommandLine=bigred.mode=windows', text)
        self.assertIn('WantedBy=multi-user.target', text)
        self.assertNotIn('Requires=', text)
        self.assertNotIn('Before=', text)

    def test_pr40_guard_is_untouched_by_this_change(self):
        guard = (ROOT / 'scripts/big-red-vm-gpu-guard').read_text()
        self.assertIn("driver != 'vfio-pci'", guard)
        self.assertIn('refusing automatic detach', guard)
        hook = (ROOT / 'libvirt/qemu').read_text()
        self.assertIn('/usr/local/sbin/big-red-vm-gpu-guard', hook)


class TailnetWaitTest(unittest.TestCase):
    """The helper must wait for an address, and give up rather than hang."""

    def run_helper(self, script_body, seconds='2'):
        tmp = tempfile.mkdtemp()
        self.addCleanup(lambda: subprocess.run(['rm', '-rf', tmp], check=False))
        stub = pathlib.Path(tmp) / 'tailscale'
        stub.write_text(script_body)
        stub.chmod(0o755)
        source = (ROOT / 'scripts/big-red-wait-for-tailnet').read_text()
        source = source.replace('/usr/bin/tailscale', str(stub))
        return subprocess.run(['bash', '-c', source, 'helper', seconds],
                              capture_output=True, text=True, check=False)

    def test_returns_as_soon_as_an_address_exists(self):
        result = self.run_helper('#!/bin/sh\necho 100.105.182.87\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('100.105.182.87', result.stdout)

    def test_waits_through_an_address_that_arrives_late(self):
        counter = pathlib.Path(tempfile.mkdtemp()) / 'n'
        self.addCleanup(lambda: subprocess.run(['rm', '-rf', str(counter.parent)], check=False))
        result = self.run_helper(
            '#!/bin/sh\n'
            f'n=$(cat {counter} 2>/dev/null || echo 0); n=$((n+1)); echo $n > {counter}\n'
            '[ "$n" -lt 2 ] && exit 1\n'
            'echo 100.105.182.87\n', seconds='10')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('100.105.182.87', result.stdout)

    def test_gives_up_instead_of_blocking_the_boot_forever(self):
        result = self.run_helper('#!/bin/sh\nexit 1\n', seconds='1')
        self.assertEqual(result.returncode, 1)
        self.assertIn('No Tailscale IPv4', result.stderr)

    def test_empty_output_is_not_treated_as_an_address(self):
        result = self.run_helper('#!/bin/sh\necho ""\n', seconds='1')
        self.assertEqual(result.returncode, 1)


class MoonlightDropInTest(unittest.TestCase):
    def test_dropin_waits_for_the_address_without_changing_the_rules(self):
        text = (ROOT / 'systemd/big-red-windows-moonlight-forward.service.d'
                       '/wait-for-tailnet.conf').read_text()
        self.assertIn('ExecStartPre=/usr/local/sbin/big-red-wait-for-tailnet', text)
        self.assertNotIn('ExecStart=', text.replace('ExecStartPre=', ''))
        self.assertIn('TimeoutStartSec=', text)


if __name__ == '__main__':
    unittest.main()
