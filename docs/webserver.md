# webserver — Hetzner Cloud VPS for www.ieuan.net

`nixosConfigurations.webserver` (`hosts/webserver/`) manages the Hetzner
Cloud VM that serves <https://www.ieuan.net/>. It is a headless server
profile: no desktop, no Home Manager, key-only SSH, GRUB/BIOS boot on the
virtio disk.

## Division of labour with dijitali/ieuan-net

This flake owns the **operating system**: the Caddy binary (built with the
`transform-encoder` log plugin), the `caddy` systemd service, firewall,
SSH, users and hardening.

The [ieuan-net](https://github.com/dijitali/ieuan-net) repo owns the
**content and virtual-host config**, deployed over SSH without a rebuild:

| What | Deployed by | Lands in |
|------|-------------|----------|
| Built site | `mise run deploy` (rsync) | `/var/www/public` |
| Caddyfile + snippets | `mise run caddy:deploy` | `/etc/caddy/sites-enabled/` |

The Caddyfile is deliberately **not** in the Nix store: a config tweak stays
an rsync + `systemctl reload caddy`, not a flake rebuild. The trade-off is
that on a fresh install the caddy unit fails to start until the first
`mise run caddy:deploy` has run — that's expected.

`hosts/webserver/caddy.nix` creates the directories both deploys expect
(`/var/www/public`, `/var/backups/ieuan-net`, `/etc/caddy/sites-enabled`,
`/run/access` for the tmpfs access log) via `systemd.tmpfiles`.

Keep the Caddy plugin pin + hash in `hosts/webserver/caddy.nix` in sync with
the devshell in `ieuan-net/flake.nix`. If a nixpkgs bump breaks the plugin
build with a hash mismatch, copy the correct hash from the error message.

## Bootstrapping NixOS on the VM

Hetzner Cloud has no official NixOS image. Two workable paths:

1. **[nixos-anywhere](https://github.com/nix-community/nixos-anywhere)** —
   cleanest for a *new* VM (kexec + reformat + install in one shot), but it
   wipes the disk, so snapshot/back up first if reusing the existing server.
2. **[nixos-infect](https://github.com/elitak/nixos-infect)** — converts the
   *running* distro in place. From root on the existing server:

   ```sh
   curl https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect | \
     NIX_CHANNEL=nixos-26.05 bash -x
   ```

Either way, once the machine boots NixOS:

```sh
# Sanity-check the committed hardware profile against reality; fold in any
# differences (especially the root filesystem device).
nixos-generate-config --show-hardware-config

# First activation from a checkout (or straight from GitHub):
sudo nixos-rebuild switch --flake github:dijitali/nixos-config#webserver
```

Then, before walking away:

1. `passwd` — set a password for `ieuan` (sudo requires one; SSH stays
   key-only).
2. Fill in the static IPv6 address block in `hosts/webserver/default.nix`
   (Hetzner provides no SLAAC/DHCPv6; gateway is `fe80::1`). The interface
   name should be `enp1s0` — confirm with `ip a`.
3. From the ieuan-net repo: `mise run caddy:deploy`, then `mise run deploy`
   to put the Caddyfile and site in place and get caddy running.

## Day-to-day deploys

From this repo on the laptop:

```sh
make web    # nixos-rebuild switch --flake .#webserver --target-host ieuan.net --sudo --ask-sudo-password
```

(With an older classic `nixos-rebuild`, substitute `--use-remote-sudo` for
`--sudo --ask-sudo-password`.)

Auto-upgrade (`modules/nix.nix`) also rebuilds nightly from the flake on
GitHub, so pushing to `main` and running `nix flake update` there is enough
to roll the server forward without SSHing in.

## Not yet managed

* `webstats.ieuan.net` reverse-proxies to `localhost:8080`; the stats
  service behind it is still hand-run. See the TODO in
  `hosts/webserver/caddy.nix`.
