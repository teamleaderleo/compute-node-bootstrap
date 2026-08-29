# `big-red` 80% firmware charge limit

This is a deliberately narrow runbook for the XIAOMI REDMI Book Pro 16 2025 named `big-red`. It does not provide a generic ACPI or embedded-controller write facility.

## Verified firmware contract

Read-only inspection on 2026-08-29 identified:

- product `REDMI Book Pro 16 2025`;
- board `TM2409`;
- BIOS `RMAAR6B0P0606`, dated 2025-05-09;
- DSDT SHA-256 `57dbcfd3227c6170e017291f24ca28d2ca895f7f25c7661a6d512278a3e1a928`;
- ACPI WMI device `\\_SB.PC00.WMID`, UID `MIFS`;
- serialized firmware method `\\_SB.PC00.WMID.WMAA`;
- charge command `0x10`, subcommand `0x02`;
- EC fields `LONL` (long-life enable) and `HBDA` (threshold value).

The machine's own SSDT maps firmware code `0` to ordinary 100% charging, codes `1` and `4` to 80%, and codes `5` through `8` to 70%, 60%, 50%, and 40%. The helper intentionally permits writes of only `0` and the OEM-compatible legacy 80% code `1`.

Ubuntu's normal power-supply interface reports no threshold support because the in-tree `redmi_wmi` driver handles hotkeys rather than this separate MIFS method. This runbook uses the packaged `acpi_call` module to invoke only the audited method and fixed buffers.

Useful independent research:

- [XiControl MIFS protocol](https://github.com/Oksion/XiControl/blob/main/docs/01-wmi-protocol.md)
- [XiControl charge-level validation](https://github.com/Oksion/XiControl/blob/main/docs/12-charge-levels.md)
- [redmi-charge-limiter](https://github.com/toshka/redmi-charge-limiter)
- [Linux `redmi-wmi` driver](https://github.com/torvalds/linux/blob/master/drivers/platform/x86/redmi-wmi.c)

## Safety properties

[`scripts/big-red-charge-limit`](../scripts/big-red-charge-limit):

- requires root and the exact DMI product, board, BIOS, and DSDT hash;
- exposes only `status`, `set-80`, and `set-100`;
- rejects arbitrary methods, buffers, percentages, and firmware response bytes;
- validates the firmware success byte and reads the threshold back after writes;
- uses Xiaomi's required `100% -> 80%` re-arm sequence;
- retries at most once;
- attempts and verifies rollback to normal 100% charging if 80% cannot be verified.

A BIOS or ACPI-table change stops the helper before any firmware call. Re-audit the new firmware rather than weakening the allowlist.

## First supervised test

Do this while physically near the machine, before installing persistence:

```bash
sudo apt install acpi-call-dkms
sudo modprobe acpi_call
sudo install -o root -g root -m 0755 scripts/big-red-charge-limit /usr/local/sbin/big-red-charge-limit

sudo big-red-charge-limit status
sudo big-red-charge-limit set-80
sudo big-red-charge-limit status
sudo big-red-charge-limit set-100
sudo big-red-charge-limit status
sudo big-red-charge-limit set-80
```

### Secure Boot enrollment

`big-red` keeps UEFI Secure Boot enabled. Ubuntu's DKMS tooling signs `acpi_call` with a machine-local, module-signing-only Machine Owner Key (MOK). If `modprobe` reports `Key was rejected by service`, stop: no firmware call has occurred, and Secure Boot is working as designed.

Do not disable Secure Boot or shim validation. Instead, while physically present:

```bash
sudo update-secureboot-policy --enroll-key
```

Choose a temporary enrollment password locally; do not put it in this repository or a chat. Reboot while remaining at the machine. In the blue MokManager screen, select **Enroll MOK**, review/confirm the certificate, enter that temporary password, and reboot when asked. Ubuntu documents that the one-run MokManager password is cleared after the operation. After Ubuntu returns:

```bash
mokutil --sb-state
sudo modprobe acpi_call
lsmod | grep '^acpi_call '
sudo big-red-charge-limit status
```

Secure Boot should still report enabled. Only continue to `set-80` after the signed module loads and the status call returns a valid threshold. See Ubuntu's [DKMS MOK enrollment guidance](https://wiki.ubuntu.com/UEFI/SecureBoot/DKMS) and [Secure Boot architecture](https://documentation.ubuntu.com/security/security-features/platform-protections/secure-boot/).

The expected final state is `charge_limit=80` and `firmware_code=1`. Because the battery may already be above 80%, firmware readback proves configuration immediately; physical cutoff behavior is verified later by observing that BAT0 does not charge above 80% after discharging below the threshold.

Rollback is always:

```bash
sudo big-red-charge-limit set-100
```

## Persistence after the test passes

Install the already-reviewed helper, module-load declaration, services, and AC reconnect rule:

```bash
sudo install -o root -g root -m 0755 scripts/big-red-charge-limit /usr/local/sbin/big-red-charge-limit
sudo install -o root -g root -m 0644 systemd/big-red-charge-limit.service /etc/systemd/system/big-red-charge-limit.service
sudo install -o root -g root -m 0644 systemd/big-red-charge-limit-rearm.service /etc/systemd/system/big-red-charge-limit-rearm.service
sudo install -o root -g root -m 0644 udev/99-big-red-charge-limit.rules /etc/udev/rules.d/99-big-red-charge-limit.rules
sudo install -o root -g root -m 0644 modules-load.d/big-red-charge-limit.conf /etc/modules-load.d/big-red-charge-limit.conf
sudo systemctl daemon-reload
sudo udevadm control --reload-rules
sudo systemctl enable --now big-red-charge-limit.service
```

The boot service applies 80%. The udev rule asks systemd to re-arm it when `ADP1` changes online. There is no polling daemon.

## Remove and return to ordinary charging

```bash
sudo big-red-charge-limit set-100
sudo systemctl disable --now big-red-charge-limit.service
sudo rm /etc/udev/rules.d/99-big-red-charge-limit.rules
sudo rm /etc/systemd/system/big-red-charge-limit.service
sudo rm /etc/systemd/system/big-red-charge-limit-rearm.service
sudo rm /etc/modules-load.d/big-red-charge-limit.conf
sudo systemctl daemon-reload
sudo udevadm control --reload-rules
```

Removing `acpi-call-dkms` is optional; it has no effect when unloaded and unused. Do not unload a kernel module merely to satisfy this runbook.
