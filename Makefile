# Convenience wrappers around nixos-rebuild for the flake.
# Override the target host with `make switch NIXNAME=othermachine`.
NIXNAME ?= jenkonix-2
# Remote server to deploy with `make deploy` (built here, activated over SSH).
SERVER ?= jenkosrv-fsn1-3

.PHONY: switch test boot deploy droid update update-sites check fmt

# Build and activate, making it the default boot entry.
switch:
	sudo nixos-rebuild switch --flake ".#$(NIXNAME)"

# Activate without making it the default boot entry (reverts on reboot).
test:
	sudo nixos-rebuild test --flake ".#$(NIXNAME)"

# Build and set as default boot entry without activating now.
boot:
	sudo nixos-rebuild boot --flake ".#$(NIXNAME)"

# Build the server's configuration locally and activate it over SSH. The
# first install is done by nixos-anywhere from vps-config; this is for every
# change after that. Needs passwordless sudo on the server (modules/server.nix).
deploy:
	nixos-rebuild switch --flake ".#$(SERVER)" --target-host "ieuan@$(SERVER)" --sudo

# Activate the Nix-on-Droid environment (run this on the Android device).
droid:
	nix-on-droid switch --flake ".#default"

# Bump flake inputs (nixpkgs, home-manager, nixos-hardware, nix-on-droid) in flake.lock.
update:
	nix flake update

# Bump only the site repos served by $(SERVER) (its `web.sites`, which are
# flake inputs of the same names) to their latest commits, leaving nixpkgs and
# everything else pinned. Commit the lock and `make deploy` to roll them out.
update-sites:
	nix flake update $$(nix eval --raw ".#nixosConfigurations.$(SERVER).config.web.sites" \
	  --apply 'sites: builtins.concatStringsSep " " (builtins.attrNames sites)')

# Evaluate the flake and all checks.
check:
	nix flake check

# Format all Nix files (matches the pre-commit hook).
fmt:
	nixfmt $$(find . -name '*.nix')
