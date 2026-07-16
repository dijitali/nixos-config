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

6. **Enroll the keys.** `--microsoft` keeps Microsoft's certificates so
   option ROMs (docks, eGPUs) and MS-signed shims keep working — dropping
   them can brick some machines. `--firmware-builtin` additionally carries
   over the certs the firmware ships as defaults: on this Dell the factory
   `db` (dump it with `mokutil --db`) contains two Dell certs (`Dell Bios DB
   Key`, `Dell Bios FW Aux Authority 2018`) alongside the Microsoft CAs, and
   plain `--microsoft` would silently drop them, likely breaking Dell-signed
   pre-boot tools (F12 BIOS flash, diagnostics):

   ```sh
   sudo sbctl enroll-keys --microsoft --firmware-builtin
   ```

   To preview without touching NVRAM, add `--export esl` (writes the
   would-be PK/KEK/db bundles to the current directory); inspect with
   efitools' `sig-list-to-certs` + `openssl x509` and check every subject
   from the factory `db` dump is still present.

   **If enrollment fails with `File is immutable: /sys/firmware/efi/efivars/…`**:
   this is not a firmware problem — the Dell BIOS side is fine (Setup Mode
   being enabled in `sbctl status` proves the key-management step worked).
   The Linux kernel marks every efivarfs file immutable (`chattr +i`) as a
   guard against accidental deletion, and even in Setup Mode the leftover
   `KEK`/`db` variables keep that flag. sbctl deliberately refuses to clear
   it itself. Clear it and re-run:

   ```sh
   sudo chattr -i /sys/firmware/efi/efivars/KEK-8be4df61-93ca-11d2-aa0d-00e098032b8c
   sudo chattr -i /sys/firmware/efi/efivars/db-d719b2cb-3d3a-4596-a3bc-dad00e67656f
   sudo sbctl enroll-keys --microsoft --firmware-builtin
   ```

   This doesn't delete the variables — it just lets sbctl overwrite them
   with the enrolled bundle. The same will apply on any future re-enroll.

7. **Reboot and confirm:**

   ```sh
   bootctl status    # expect: Secure Boot: enabled (user) or (deployed)
   ```

   This Dell finalizes to **`enabled (deployed)`** — the most locked-down
   UEFI state (only authenticated updates signed by our PK/KEK can change
   the key databases; no unauthenticated mode switches). Functionally
   identical to `(user)` for signing, dbx updates and daily use. Also
   confirm the boot chain: `Current Stub: lanzastub`, the default entry is
   Type #2 (UKI, `.efi` from `EFI/Linux/`), and `Measured UKI: yes` (which
   unlocks the TPM2 LUKS follow-up below).

8. **Set a firmware (BIOS) admin password.** Without it, anyone at the
   keyboard can simply switch Secure Boot off again.

9. **Back up `/var/lib/sbctl`** somewhere offline/encrypted (e.g. 1Password
   or a LUKS USB stick). Losing the keys isn't fatal (re-enter Setup Mode and
   re-enroll new ones) but the backup avoids the dance.

### Why not lanzaboote's automated key setup?

Upstream now offers a hands-off alternative to steps 2 and 6
([auto-generate][lzbt-autogen], [auto-enroll][lzbt-autoenroll]):
`boot.lanzaboote.autoGenerateKeys.enable` creates the keys in `pkiBundle` via
a systemd service on first boot, and `boot.lanzaboote.autoEnrollKeys.enable`
enrolls them (Microsoft certs included by default) on the next reboot. Both
options exist in our pinned v1.1.0, and for a fresh unattended install
they'd be the better practice. We stay manual deliberately:

- **`--firmware-builtin` has no auto-enroll equivalent in any release.**
  `autoEnrollKeys.includeFirmwareBuiltinKeys` exists only on unreleased
  master (checked 2026-07-05); v1.1.0's auto-enroll would silently drop the
  Dell factory `db` certs this doc goes out of its way to preserve.
- The manual flow allows a dry-run (`--export esl`) before touching NVRAM;
  auto-enroll doesn't.
- The keys already exist and are enrolled — switching buys nothing.

Revisit if a release ships `includeFirmwareBuiltinKeys` (worth rechecking
whenever the lanzaboote pin is bumped).

[lzbt-autogen]: https://nix-community.github.io/lanzaboote/how-to-guides/automatically-generate-keys.html
[lzbt-autoenroll]: https://nix-community.github.io/lanzaboote/how-to-guides/automatically-enroll-keys.html

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

## Key expiry

UEFI Secure Boot image verification is a signature/trust check with no
time-based validation (the firmware has no trustworthy pre-boot clock), so
**certificate expiry never stops the machine booting**. But the two cert
sets in play age differently:

- **Our sbctl certs** (created 2026-07-05, expire 2031-07-05: `sudo openssl
  x509 -noout -dates -in /var/lib/sbctl/keys/PK/PK.pem`): expiry is a
  non-event. We control both signing and verification, sbsign keeps signing
  with an expired cert, and the firmware keeps accepting it. No
  auto-renewal, no notification, none needed. Rotate only on compromise,
  via the same setup-mode + enroll dance as initial setup.
- **Microsoft's CAs**: the 2011 generation expires in 2026 (KEK CA 2011:
  2026-06-24, UEFI CA 2011: 2026-06-27, Windows Production PCA 2011:
  2026-10-19). Existing signatures stay valid and machines keep booting,
  but Microsoft issues *new* signatures — including **dbx revocation
  updates**, which we receive via fwupd/LVFS — only under the 2023 CAs
  ([MS: Secure Boot certificate expiration and CA updates][ms-sb-expiry]).
  The firmware accepts a dbx update only if it's signed under a KEK CA
  present in the enrolled KEK, so the 2023 CAs must be in our KEK/db. They
  are: the factory variables include `Microsoft Corporation KEK 2K CA 2023`
  (KEK) and `Microsoft UEFI CA 2023` + `Microsoft Option ROM UEFI CA 2023`
  (db), and enrolling with `--microsoft --firmware-builtin` carries them
  over. If a future audit (`mokutil --kek`, `mokutil --db`) shows no 2023
  CAs, re-enroll — dbx updates are silently failing.

[ms-sb-expiry]: https://support.microsoft.com/en-gb/topic/windows-secure-boot-certificate-expiration-and-ca-updates-7ff40d33-95dc-4c3c-8725-a9b95457578e

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

## TPM2 + FIDO2 LUKS unlock

Builds on Secure Boot: the LUKS volume key gets sealed by the TPM against
the boot measurements that lanzaboote's measured boot provides (`Measured
UKI: yes` in `bootctl status` was the prerequisite). At boot the TPM only
releases the key if the Secure Boot policy is unchanged **and** a PIN is
entered — so the unlock becomes "this machine, untampered, plus something
you know". A second keyslot bound to the YubiKeys (FIDO2 hmac-secret)
covers TPM failure, and the original passphrase slot stays as the last
resort. **Never remove the passphrase slot.**

Why the PIN: a TPM-only slot means a stolen laptop decrypts itself to the
SDDM login screen, collapsing the security boundary to the login prompt.
The PIN can be short (6–8 digits): wrong guesses are rate-limited by the
TPM's dictionary-attack lockout, and the slot cannot be brute-forced
offline at all — the secret never leaves the chip, so an attacker with a
disk image is back to attacking the (long) passphrase slot.

### How it's implemented

`hosts/jenkonix-2/default.nix` adds `crypttabExtraOpts = [ "tpm2-device=auto"
"fido2-device=auto" "token-timeout=10s" ]` to both LUKS volumes (root
`c54ac17e-…` and swap `58f3676b-…` — both, or swap still prompts for a
passphrase). The systemd initrd's TPM2/FIDO2 support
(`boot.initrd.systemd.{tpm2,fido2}.enable`) already defaults to on.

Unlock order (verified in systemd v260's `cryptsetup.c`: TPM2 wins
`determine_token_type()`, and each failure invalidates that mechanism and
re-enters the loop):

1. **TPM2** — Plymouth asks for the PIN.
2. **FIDO2** — on TPM failure; touch the plugged-in YubiKey, or after
   `token-timeout` (10s) with no key present, fall through.
3. **Passphrase** — always works, on every generation ever built (older
   initrds don't even have the token options).

The options are inert until keyslots are enrolled: an initrd with
`tpm2-device=auto` and no TPM2 keyslot just falls through to the
passphrase, so the config can land before enrollment in either order.

### Enrollment (one-time, per volume)

Uses the default PCR 7 binding (Secure Boot policy). Do **not** bind PCR 11
(the UKI measurement) — it changes on every rebuild and needs signed-policy
machinery to be usable.

```sh
# TPM2 + PIN, both volumes, same PIN (systemd caches the credential during
# boot, so one PIN entry unlocks both). Asks for the existing passphrase.
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-with-pin=yes \
  /dev/disk/by-uuid/c54ac17e-bd99-4425-b4f8-c0cc62285b61
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-with-pin=yes \
  /dev/disk/by-uuid/58f3676b-64b0-4165-88f1-366ef142fbcf

# FIDO2, per YubiKey plugged in (4 runs total: 2 keys x 2 volumes).
sudo systemd-cryptenroll --fido2-device=auto /dev/disk/by-uuid/c54ac17e-…
sudo systemd-cryptenroll --fido2-device=auto /dev/disk/by-uuid/58f3676b-…

# Inspect the slots afterwards:
sudo systemd-cryptenroll /dev/disk/by-uuid/c54ac17e-…
```

Then rebuild onto this branch's config and reboot. Test the whole ladder
once: PIN unlock, then a boot where you fail the PIN and use the YubiKey,
then escape to the passphrase.

### What invalidates the TPM slot

PCR 7 measures the Secure Boot *policy*, not the kernel — so normal
rebuilds and kernel updates never break it. What does (by design):
toggling Secure Boot, re-enrolling SB keys, and — easy to forget — **dbx
revocation updates via fwupd/LVFS**. The symptom is the PIN prompt being
replaced by the passphrase prompt. After one of those events that's
routine; at any other time, treat it as the tamper alarm it is.

Re-seal (both volumes):

```sh
sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto \
  --tpm2-with-pin=yes /dev/disk/by-uuid/…
```

The FIDO2 and passphrase slots are unaffected by PCR changes.

### Recovery notes

- **TPM lockout** (too many wrong PINs): boot with the YubiKey or
  passphrase, then clear it with `tpm2_dictionarylockout --clear-lockout`
  (`nix shell nixpkgs#tpm2-tools`), or let it decay on its own.
- **Undo any mechanism** without data loss:
  `systemd-cryptenroll --wipe-slot=tpm2` (or `=fido2`) per volume.
- **Motherboard/TPM swap**: TPM slot is gone for good — unlock via
  YubiKey/passphrase, wipe the stale slot, enroll the new TPM.
