# Compute Node Bootstrap

A small, boring playbook for taking a new computer from factory state to a remotely manageable Linux development / CI node.

The first target is a **REDMI Book Pro 16 2025 (Core Ultra 7 255H / 32 GB / 1 TB)** running **Ubuntu 26.04 LTS**.

## Start here

If you are physically holding the REDMI Book, follow:

- [English install guide](machines/redmibook-pro-16-2025/INSTALL.md)
- [中文安装指南](machines/redmibook-pro-16-2025/INSTALL.zh-CN.md)

The physical part is intentionally short:

1. Verify the new laptop in Windows and claim any bundled software license you want to keep.
2. Make an Ubuntu 26.04 USB stick.
3. Boot it with the one-time boot menu.
4. Try Ubuntu and check the hardware.
5. Erase Windows and install Ubuntu.
6. Get the machine online.
7. Run the bootstrap script so the remote operator can take over.

If anything materially differs from the guide, **stop, take a photo, and call**. There is no prize for improvising in firmware or disk-management screens.

## Why Ubuntu 26.04?

Ubuntu 26.04 is the current LTS and ships a newer kernel for recent Intel hardware. We want the physical node to be a normal, current Linux machine. Exact GitHub-hosted runner parity is a workload concern, not a reason to pin the host OS to an older release.

GitHub also provides an `ubuntu-26.04` hosted runner image (currently preview as of August 2026), so 26.04 is already useful as a CI target.

## After Ubuntu is installed

Run:

```bash
curl -fsSLO https://raw.githubusercontent.com/teamleaderleo/compute-node-bootstrap/main/scripts/bootstrap-ubuntu.sh
bash bootstrap-ubuntu.sh
```

Then collect a basic machine report:

```bash
curl -fsSLO https://raw.githubusercontent.com/teamleaderleo/compute-node-bootstrap/main/scripts/host-report.sh
bash host-report.sh
```

See [remote access](docs/REMOTE_ACCESS.md) and [CI-node notes](docs/CI_NODE.md) after the first boot.

## Design rule

This repository optimizes for a remote video call with a competent person who simply has not installed this exact machine before. It therefore:

- shows one recommended path rather than every Ubuntu option;
- uses screenshots only where a wrong click would be expensive or confusing;
- links back to canonical upstream documentation;
- separates physical setup from later remote administration;
- treats unexpected screens as stop conditions.

## Sources and licensing

The Ubuntu installer screenshots embedded in the machine guide come from the Ubuntu Desktop documentation and are attributed in [THIRD_PARTY.md](THIRD_PARTY.md). See [LICENSES.md](LICENSES.md) for licensing.
