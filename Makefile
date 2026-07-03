# Convenience wrappers around nixos-rebuild for the flake.
# Override the target host with `make switch NIXNAME=othermachine`.
NIXNAME ?= jenkonix-2

.PHONY: switch test boot droid update check fmt

# Build and activate, making it the default boot entry.
switch:
	sudo nixos-rebuild switch --flake ".#$(NIXNAME)"

# Activate without making it the default boot entry (reverts on reboot).
test:
	sudo nixos-rebuild test --flake ".#$(NIXNAME)"

# Build and set as default boot entry without activating now.
boot:
	sudo nixos-rebuild boot --flake ".#$(NIXNAME)"

# Activate the Nix-on-Droid environment (run this on the Android device).
droid:
	nix-on-droid switch --flake ".#default"

# Bump flake inputs (nixpkgs, home-manager, nixos-hardware, nix-on-droid) in flake.lock.
update:
	nix flake update

# Evaluate the flake and all checks.
check:
	nix flake check

# Format all Nix files (matches the pre-commit hook).
fmt:
	nixfmt $$(find . -name '*.nix')
