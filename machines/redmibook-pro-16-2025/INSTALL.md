# REDMI Book Pro 16 2025 → Ubuntu 26.04

[中文版本](INSTALL.zh-CN.md)

This is the **single recommended path** for the REDMI Book Pro 16 2025 that will become a Linux development / CI node.

If a screen looks materially different from this guide, **stop, take a photo, and call** before changing firmware or disk settings.

## What you need

- the REDMI Book and charger;
- an **8 GB or larger USB stick** (everything on it will be erased);
- another Windows computer to prepare the USB;
- internet access;
- about 45–90 minutes, most of it waiting for downloads/install.

## 0. Before wiping Windows — 5 minutes

Boot Windows once before changing anything.

Check:

- display, keyboard, trackpad and Wi-Fi work;
- Windows reports about **32 GB RAM**;
- the internal SSD is about **1 TB**;
- the charger works.

### Optional: claim bundled Office

Some China-market REDMI Book configurations include Office Home & Student. If Windows offers a bundled Office license and you might ever want it, activate/claim it to the intended Microsoft account **before erasing Windows**.

Do not spend time personalizing Windows. The purpose of this boot is to catch a defective machine and preserve any bundled license you care about.

## 1. Download Ubuntu 26.04 LTS

Use Ubuntu's official download page:

https://ubuntu.com/download/desktop

Choose **Ubuntu 26.04 LTS — Intel or AMD 64-bit**. The ISO filename should look like:

```text
ubuntu-26.04-desktop-amd64.iso
```

Ubuntu's full installation tutorial is here if you want to cross-check anything:

https://ubuntu.com/desktop/docs/en/26.04/tutorial/install-ubuntu-desktop/

## 2. Make the USB on Windows

Use Rufus from its official site:

https://rufus.ie/

Ubuntu's current Rufus guide:

https://ubuntu.com/desktop/docs/en/26.04/how-to/create-a-bootable-usb-stick/#using-rufus

The short version:

1. Insert the USB stick.
2. Open Rufus.
3. Confirm **Device** is the USB stick you intend to erase.
4. Click **SELECT** and choose `ubuntu-26.04-desktop-amd64.iso`.
5. Leave the normal defaults alone.
6. Click **START**.
7. If Rufus asks about an ISOHybrid image, choose **Write in ISO Image mode**.
8. Confirm the USB erase warning.
9. Wait for **READY**, then close Rufus.

> Ubuntu's current 26.04 documentation still shows an older 24.04 ISO filename in its Rufus screenshots. Your downloaded file should say **26.04**.

## 3. Boot the REDMI Book from USB

1. Shut the REDMI Book down.
2. Insert the Ubuntu USB.
3. Power on and repeatedly tap **F12** to open the one-time boot menu.
4. Select the USB device.

If F12 appears to behave like a media/function shortcut, try **Fn+F12**.

**Leave Secure Boot enabled for the first attempt.** Ubuntu's signed installer should boot normally with Secure Boot enabled. There is no reason to add a firmware password or disable Secure Boot unless we discover a concrete need later.

If the USB does not appear, stop and call. Do not randomly change firmware settings.

## 4. Try Ubuntu before erasing anything

Go through language/keyboard/network setup until you reach this page:

![Ubuntu 26.04 Try or install screen](https://raw.githubusercontent.com/ubuntu/ubuntu-desktop-documentation/b8ac89eb51c82da87875ab4d65469f5615f0afd6/docs/images/installer/try-or-install-ubuntu.png)

Choose **Try Ubuntu** first.

Spend a few minutes checking:

- display looks normal;
- keyboard and trackpad work;
- Wi-Fi can see/connect to the network;
- speakers work;
- the system does not freeze or behave strangely.

Then open **Install Ubuntu** from the desktop.

## 5. Installer choices

Use the ordinary interactive installer.

### Applications

Choose **Default selection**. This node does not need the extra office apps.

![Ubuntu 26.04 applications selection](https://raw.githubusercontent.com/ubuntu/ubuntu-desktop-documentation/b8ac89eb51c82da87875ab4d65469f5615f0afd6/docs/images/installer/applications.png)

If the installer offers third-party drivers/media support, leaving both recommended boxes enabled is fine.

## 6. Disk setup — this is the destructive step

For this machine, choose **Erase disk and install Ubuntu**.

![Ubuntu 26.04 disk setup](https://raw.githubusercontent.com/ubuntu/ubuntu-desktop-documentation/b8ac89eb51c82da87875ab4d65469f5615f0afd6/docs/images/installer/disk-setup.png)

Before continuing, verify that the target is the **internal ~1 TB SSD**.

### Encryption

For this unattended CI node, choose **no full-disk encryption** during the first installation. A disk-unlock prompt after every reboot would prevent unattended recovery after a power outage. We can revisit encryption later if we also design remote/unattended unlock.

### STOP if the internal SSD is missing

If the installer cannot see the internal ~1 TB drive, **stop and call**. Intel RST/VMD/storage-controller settings can be involved on some Intel PCs; do not change them speculatively.

Ubuntu's reference:

https://ubuntu.com/desktop/docs/en/26.04/reference/intel-rst-during-ubuntu-installation/

## 7. Create the local account

The installer asks for a name, computer name, username and password:

![Ubuntu 26.04 create account screen](https://raw.githubusercontent.com/ubuntu/ubuntu-desktop-documentation/b8ac89eb51c82da87875ab4d65469f5615f0afd6/docs/images/installer/create-your-account.png)

Recommended computer name:

```text
redmi-01
```

Use a normal local admin user and a strong password. Send the username/password privately to the operator; **never put credentials in this public repository**.

Keep **Require my password to log in** enabled.

## 8. Final review

The last page should look broadly like this:

![Ubuntu 26.04 ready to install](https://raw.githubusercontent.com/ubuntu/ubuntu-desktop-documentation/b8ac89eb51c82da87875ab4d65469f5615f0afd6/docs/images/installer/ready-to-install.png)

For our machine, the important lines are:

- **Erase disk and install Ubuntu**;
- **Default selection**;
- **Disk encryption: None**;
- root filesystem is **ext4**;
- installation disk is the internal SSD.

If those are right, click **Install**.

## 9. Restart

When installation finishes:

![Ubuntu 26.04 installation complete](https://raw.githubusercontent.com/ubuntu/ubuntu-desktop-documentation/b8ac89eb51c82da87875ab4d65469f5615f0afd6/docs/images/installer/installation-complete.png)

Click **Restart now**. When prompted, remove the USB stick and press Enter.

Log into the new Ubuntu desktop and connect it to the internet.

## 10. Hand the machine over remotely

Open Terminal (`Ctrl` + `Alt` + `T`) and run:

```bash
curl -fsSLO https://raw.githubusercontent.com/teamleaderleo/compute-node-bootstrap/main/scripts/bootstrap-ubuntu.sh
bash bootstrap-ubuntu.sh
```

Then:

```bash
curl -fsSLO https://raw.githubusercontent.com/teamleaderleo/compute-node-bootstrap/main/scripts/host-report.sh
bash host-report.sh
```

The bootstrap enables SSH and prints the LAN IP addresses. At that point the physical installation is complete; the operator can choose the remote-access method and CI software separately.

## Stop conditions

Stop and call if any of these happen:

- the Ubuntu USB is absent from the boot menu;
- the installer cannot see the internal ~1 TB SSD;
- the installer proposes erasing an unexpected disk;
- firmware asks for an unfamiliar password;
- the machine repeatedly freezes/reboots in the live environment;
- the installed system does not boot after restart;
- any screen looks risky and you are unsure what it means.

Photos are more useful than guesses.

## Machine-specific Linux notes

The current ArchWiki page for this exact 2025 model reports working GPU, Wi-Fi, Bluetooth, webcam, touchpad, keyboard, TPM, fingerprint reader, audio and ambient-light sensor. It also documents Linux charge-limit control and `fwupd` support:

https://wiki.archlinux.org/title/Xiaomi_RedmiBook_Pro_16_2025
