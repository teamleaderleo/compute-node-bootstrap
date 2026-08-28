# REDMI Book Pro 16 2025 → Ubuntu 26.04

[中文版本](INSTALL.zh-CN.md)

This is the **single recommended path** for the REDMI Book Pro 16 2025 that will become a Linux development / CI node.

If a screen looks materially different from this guide, **stop, take a photo, and call** before changing firmware or disk settings.

## What you need

- the REDMI Book and charger;
- one **16 GB or larger USB stick** for Ubuntu;
- optionally, one **32 GB or larger USB stick** for factory Windows recovery;
- internet access;
- the Mac or another device for following this guide with Codex.

Use the new REDMI Book's own Windows installation to prepare both USB drives. The work ThinkPads and iPad are not needed for this.

## 0. Before wiping Windows

Boot Windows once and check:

- display, keyboard, trackpad and Wi-Fi work;
- Windows reports about **32 GB RAM**;
- the internal SSD is about **1 TB**;
- the charger works.

### Optional: make the Windows recovery USB

1. Insert the 32 GB USB stick.
2. Open Start and search for **Recovery Drive**.
3. Open it and keep **Back up system files to the recovery drive** selected.
4. Choose the 32 GB USB stick and click **Create**.
5. Label it `REDMI Windows recovery` and set it aside when it finishes.

If **Settings → Privacy & security → Device encryption** is on, save the recovery key. If it is off, continue.

Microsoft's reference: https://support.microsoft.com/en-US/Windows/Experience/backup-recovery/recovery-drive

### Optional: claim bundled Office

Some China-market REDMI Book configurations include Office Home & Student. If Windows offers a bundled Office license and you might ever want it, activate/claim it to the intended Microsoft account **before erasing Windows**.

## 1. Download Ubuntu 26.04 LTS

Use Ubuntu's official download page:

https://ubuntu.com/download/desktop

Choose **Ubuntu 26.04 LTS — Intel or AMD 64-bit**. The ISO filename should look like:

```text
ubuntu-26.04-desktop-amd64.iso
```

Ubuntu's full installation tutorial:

https://ubuntu.com/desktop/docs/en/26.04/tutorial/install-ubuntu-desktop/

## 2. Make the USB on Windows

Use Rufus from its official site:

https://rufus.ie/

Ubuntu's Rufus guide:

https://ubuntu.com/desktop/docs/en/26.04/how-to/create-a-bootable-usb-stick/#using-rufus

1. Remove the Windows recovery USB, then insert the 16 GB Ubuntu USB.
2. Open Rufus. Under **Device**, choose the Ubuntu USB.

![Rufus detects the USB](images/rufus/rufus-detects-usb.png)

3. Click **SELECT** and choose `ubuntu-26.04-desktop-amd64.iso`.
4. Leave the normal defaults alone. If **Enable runtime UEFI media validation** appears under the advanced format options, leave it unchecked.

![Rufus with an Ubuntu ISO selected](images/rufus/rufus-iso-selected.png)

5. Click **START**.
6. If Rufus asks about an ISOHybrid image, choose **Write in ISO Image mode** and click **OK**.

![Rufus ISOHybrid choice](images/rufus/rufus-isohybrid-image.png)

7. At the erase confirmation, click **OK**.

![Rufus USB erase confirmation](images/rufus/rufus-data-warning.png)

8. Wait until the status says **READY**, then close Rufus.

![Rufus finished writing the Ubuntu USB](images/rufus/rufus-finished-writing.png)

> Ubuntu's current 26.04 documentation still shows an older 24.04 ISO filename in its Rufus screenshots. Your downloaded file should say **26.04**.

## 3. Boot the REDMI Book from USB

1. Shut the REDMI Book down.
2. Insert the Ubuntu USB.
3. Power on and repeatedly tap **F12** to open the one-time boot menu.
4. Select the USB device.

If F12 behaves like a media/function shortcut, try **Fn+F12**.

**Leave Secure Boot enabled for the first attempt.** Ubuntu's signed installer should boot normally with Secure Boot enabled.

If the USB does not appear, stop and call. Do not randomly change firmware settings.

## 4. Try Ubuntu before erasing anything

Go through language/keyboard/network setup until you reach this page:

![Ubuntu 26.04 Try or install screen](images/ubuntu-installer/try-or-install-ubuntu.png)

Choose **Try Ubuntu** first.

Check:

- display looks normal;
- keyboard and trackpad work;
- Wi-Fi connects;
- speakers work;
- the system does not freeze or reboot unexpectedly.

Then open **Install Ubuntu** from the desktop.

## 5. Installer choices

Use the ordinary interactive installer.

Choose **Default selection**:

![Ubuntu 26.04 applications selection](images/ubuntu-installer/applications.png)

If the installer offers third-party drivers/media support, leaving the recommended boxes enabled is fine.

## 6. Disk setup — destructive step

Choose **Erase disk and install Ubuntu**:

![Ubuntu 26.04 disk setup](images/ubuntu-installer/disk-setup.png)

Before continuing, verify that the target is the **internal ~1 TB SSD**.

For this unattended node, choose **no full-disk encryption** during the first installation so a reboot does not require someone physically present to unlock the disk.

### STOP if the internal SSD is missing

If the installer cannot see the internal ~1 TB drive, **stop and call**. Intel RST/VMD/storage-controller settings can be involved on some Intel PCs; do not change them speculatively.

Ubuntu reference:

https://ubuntu.com/desktop/docs/en/26.04/reference/intel-rst-during-ubuntu-installation/

## 7. Create the local account

![Ubuntu 26.04 create account screen](images/ubuntu-installer/create-your-account.png)

Recommended computer name:

```text
big-red
```

Use this Ubuntu username:

```text
leo
```

Create a normal admin user and a local password. Keep **Require my password to log in** enabled.

Send the **username** to the remote operator.

## 8. Final review

![Ubuntu 26.04 ready to install](images/ubuntu-installer/ready-to-install.png)

Important lines for this machine:

- **Erase disk and install Ubuntu**;
- **Default selection**;
- **Disk encryption: None**;
- root filesystem is **ext4**;
- installation disk is the internal SSD.

If those are right, click **Install**.

## 9. Restart

![Ubuntu 26.04 installation complete](images/ubuntu-installer/installation-complete.png)

Click **Restart now**. When prompted, remove the USB stick and press Enter.

Log into Ubuntu and connect it to the internet.

## 10. Give Codex a remote shell

The preferred handoff is **Tailscale SSH**. This avoids router changes, public SSH ports, dynamic DNS, and manually copying SSH public keys.

Open Terminal with **Ctrl + Alt + T**.

### 10a. Install ordinary SSH plus Tailscale

Click GitHub's copy button for this entire block, paste it into Terminal, and press Enter:

```bash
sudo apt update
sudo apt install -y openssh-server curl
sudo systemctl enable --now ssh
curl -fsSL https://tailscale.com/install.sh | sh
```

It may ask for the local Ubuntu password. When typing a password in Terminal, nothing appears on screen; type it normally and press Enter.

If the Tailscale download/install command fails, **stop and call**. Ordinary OpenSSH is already installed, so we still have a fallback path to work with.

### 10b. Join the operator's Tailscale network and enable Tailscale SSH

Copy and run:

```bash
sudo tailscale up --ssh --hostname=big-red
```

The command prints a web address beginning with `https://login.tailscale.com/...`.

Send that address to the remote operator. The person holding the laptop does not need the operator's Tailscale password or account.

The remote operator opens that address on their own device and authenticates the REDMI Book into their Tailscale network.

After the operator says authentication succeeded, copy and run:

```bash
tailscale status
printf '\nUbuntu username: '; whoami
printf 'Computer name: '; hostname
printf 'Tailscale IP: '; tailscale ip -4
```

Send the output to the operator.

### 10c. Operator test

The remote operator, from a computer that is also signed into the same Tailscale network, can now try:

```bash
ssh leo@big-red
```

With Tailscale SSH, no separately generated SSH key pair is required for this connection. Tailscale handles the SSH identity/authorization for traffic arriving over the tailnet.

Once that succeeds **from the operator's actual remote network**, the required physical setup is complete. The person holding the laptop can stop; the operator follows the [post-handoff TODO](../../docs/REDMI_HANDOFF_TODO.md).

> Mainland-China cross-border connectivity can make Tailscale slower or less reliable than elsewhere. We install normal OpenSSH too so Tailscale is a preferred path rather than the sole recovery mechanism. Test the real remote connection before leaving the node unattended.

## Stop conditions

Stop and call if:

- the Ubuntu USB is absent from the boot menu;
- the installer cannot see the internal ~1 TB SSD;
- the installer proposes erasing an unexpected disk;
- firmware asks for an unfamiliar password;
- the live environment repeatedly freezes/reboots;
- the installed system does not boot;
- Tailscale cannot install or produce an authentication URL;
- any screen looks risky and you are unsure what it means.

Photos are more useful than guesses.

## Machine-specific Linux notes

The current ArchWiki page for this exact 2025 model reports working GPU, Wi-Fi, Bluetooth, webcam, touchpad, keyboard, TPM, fingerprint reader, audio and ambient-light sensor. It also documents Linux charge-limit control and `fwupd` support:

https://wiki.archlinux.org/title/Xiaomi_RedmiBook_Pro_16_2025
