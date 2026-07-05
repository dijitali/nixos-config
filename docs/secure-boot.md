# Secure Boot (lanzaboote)

UEFI Secure Boot for jenkonix-2, implemented with
[lanzaboote](https://github.com/nix-community/lanzaboote).

## Why

The ESP (`/boot`) is unencrypted — LUKS protects the root filesystem, but
anyone with physical access can replace the kernel or initrd on the ESP and
capture the LUKS passphrase on next boot (an "evil maid" attack). With Secure
Boot enabled, the firmware only runs bootloaders and kernels signed with our
own keys, closing that hole. It is also the prerequisite for later binding the
LUKS unlock to the TPM (`systemd-cryptenroll`).

## How it's implemented

- **`flake.nix`** — adds the `lanzaboote` input, pinned to a release tag
  (`v1.1.0`). Bump the tag deliberately; don't track master.
- **`modules/secure-boot.nix`** — imports lanzaboote's NixOS module, disables
  the stock `systemd-boot` module (lanzaboote installs and signs systemd-boot
  itself), points it at the sbctl PKI bundle in `/var/lib/sbctl`, and installs
  `sbctl`.
- **`hosts/jenkonix-2/default.nix`** — imports the module.

On every `nixos-rebuild`, lanzaboote's `lzbt` tool packs each generation's
kernel + initrd into a unified kernel image (UKI), signs it and systemd-boot
with the key in `/var/lib/sbctl`, and installs them to the ESP. The
systemd-boot options in `modules/boot.nix` (`editor = false`,
`consoleMode`, `configurationLimit`, `boot.loader.timeout`) are still
honoured — lanzaboote reads them for its loader configuration.

The signing keys live only on this machine, readable only by root. They are
**not** in the repo and are not managed by Nix; back them up (see below).

## Pre-cleanup: stale Ubuntu boot entries

`efibootmgr -v` on jenkonix-2 showed two leftover NVRAM entries from the
Ubuntu install on the old drive (before the Crucial T500 swap):

- `Boot0004 Ubuntu` — GRUB via `\EFI\ubuntu\shimx64.efi`
- `Boot0001 Linux Firmware Updater` — fwupd's UEFI capsule updater, also
  chainloaded through the Ubuntu shim

Both point at partition PARTUUID `18190cd2-…`, which no longer exists on any
disk in the machine — they're dangling pointers and can never boot. They're
worth deleting anyway, for two reasons:

1. **Clutter**: they show up in the firmware boot menu and `BootOrder`.
2. **Secure Boot hygiene**: we enroll with `--microsoft`, so a
   Microsoft-signed shim is trusted under our policy. A boot entry pointing
   at a shim is a ready-made side door if a matching partition ever
   reappears (e.g. plugging in the old drive). Fewer trusted-but-unmanaged
   boot paths, better.

Delete them (efibootmgr isn't installed; run it from nixpkgs — the `$(nix
build …)` resolves before sudo, sidestepping sudo's restricted `PATH`):

```sh
sudo "$(nix build nixpkgs#efibootmgr --no-link --print-out-paths)/bin/efibootmgr" -b 0001 -B
sudo "$(nix build nixpkgs#efibootmgr --no-link --print-out-paths)/bin/efibootmgr" -b 0004 -B
```

`-B` deletes the entry and drops it from `BootOrder` in one go. Afterwards
only two entries remain, both pointing at the real ESP (`46664568-…`):
`Boot0008 Linux Boot Manager` (systemd-boot, the active entry) and
`Boot0000 UEFI RST …` (the firmware's auto-created fallback for
`\EFI\Boot\BootX64.efi` — leave it; the firmware recreates it anyway, and
lanzaboote signs that fallback loader too).

This doesn't orphan fwupd: our config runs fwupd itself, and it creates a
fresh updater entry pointing at the real ESP whenever it next stages a
firmware update.

## One-time setup (order matters)

Do this **before** rebuilding with this branch merged — the bootloader
install step fails if `/var/lib/sbctl` has no keys.

1. **Check the firmware is capable** (it is on the XPS 13 9310, but verify):

   ```sh
   bootctl status    # look for "Secure Boot: disabled (setup)" or "(user)"
   ```

2. **Create the keys** (sbctl is in the config after merge; before that,
   `nix shell nixpkgs#sbctl`):

   ```sh
   sudo sbctl create-keys
   ```

   Keys land in `/var/lib/sbctl`, private key root-only.

3. **Rebuild** with this branch:

   ```sh
   make switch
   ```

4. **Verify everything on the ESP is signed:**

   ```sh
   sudo sbctl verify
   ```

   All `EFI/BOOT`, `EFI/Linux/nixos-generation-*.efi` and `EFI/systemd` files
   should show ✓. (Bare `kernel-*`/`bzImage` files being unsigned is expected.)

5. **Put the firmware in Setup Mode.** Reboot into firmware setup
   (`systemctl reboot --firmware-setup`). On the Dell XPS: *Boot
   Configuration → Secure Boot*. Enable Secure Boot, set the mode to **Audit
   Mode / Setup Mode** (Dell calls key reset "Expert Key Management → Reset
   all keys" or provides a "Deployed → Audit" switch — do **not** pick any
   option worded "clear/erase all Secure Boot data", which would also drop
   the revocation database). Save and boot back into NixOS.

6. **Enroll the keys** (keeping Microsoft's certificates so option ROMs —
   Thunderbolt, GPU — keep working; dropping them can brick some machines):

   ```sh
   sudo sbctl enroll-keys --microsoft
   ```

7. **Reboot and confirm:**

   ```sh
   bootctl status    # expect: Secure Boot: enabled (user)
   ```

8. **Set a firmware (BIOS) admin password.** Without it, anyone at the
   keyboard can simply switch Secure Boot off again.

9. **Back up `/var/lib/sbctl`** somewhere offline/encrypted (e.g. 1Password
   or a LUKS USB stick). Losing the keys isn't fatal (re-enter Setup Mode and
   re-enroll new ones) but the backup avoids the dance.

## Day-to-day usage

Nothing changes. `make switch` / auto-upgrade sign new generations
automatically. Occasionally worth running:

```sh
sudo sbctl verify     # everything on the ESP still signed
bootctl status        # Secure Boot still "enabled (user)"
```

`fwupd` firmware updates continue to work: with `--microsoft` enrolled, the
UEFI capsule updater remains trusted, and dbx (revocation) updates still
arrive via LVFS.

## Recovery

If the machine refuses to boot (e.g. ESP entry unsigned or keys wiped):

1. Enter firmware setup and **disable Secure Boot** — the same signed-or-not
   binaries boot fine without enforcement.
2. Boot NixOS, fix the issue (`sudo sbctl verify` shows what's unsigned;
   `make switch` re-signs and reinstalls), re-enable Secure Boot.

If you need to boot a NixOS installer/live USB while Secure Boot is on, it
won't be signed with our keys — temporarily disable Secure Boot (this is why
the firmware password matters).

Rolling back to older generations from the boot menu keeps working: previous
generations' UKIs were signed when they were built.

## Follow-ups (not yet implemented)

- **TPM2-bound LUKS unlock**: `sudo systemd-cryptenroll --tpm2-device=auto
  --tpm2-with-pin=yes /dev/disk/by-uuid/<luks-uuid>` plus
  `boot.initrd.systemd` TPM support — unlocks only when the measured boot
  chain is unchanged. Only worthwhile once Secure Boot is enabled and stable.
- The YubiKeys can be enrolled as an additional LUKS keyslot with
  `systemd-cryptenroll --fido2-device=auto`.
