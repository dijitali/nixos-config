# Caddy serving a set of sites, each defined by its own repo.
#
# Contract: a site is a flake input whose outputs include `caddyConfig`, a
# self-contained Caddyfile fragment (no relative imports) that refers to any
# files of its own by store path. This module knows nothing about individual
# sites: the host lists them in `web.sites`, and each repo's flake owns how its
# config and files fit together.
#
# The sites are written to the store as <name>.Caddyfile, imported by a small
# top-level Caddyfile, and the whole thing is validated with `caddy adapt` at
# build time, so a broken site fails the build rather than the deploy. To roll
# out a site change: commit to the site repo, `nix flake update <input>` here,
# and deploy.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.web;
  caddy = config.services.caddy.package;

  sites = pkgs.linkFarm "caddy-sites" (
    lib.mapAttrsToList (name: site: {
      name = "${name}.Caddyfile";
      path = pkgs.writeText "${name}.Caddyfile" site.caddyConfig;
    }) cfg.sites
  );

  # The admin endpoint stays at its localhost-only default: the unit's reload
  # (on config change, and any `systemctl reload caddy` after pushing content)
  # goes through it.
  caddyfile = pkgs.writeText "Caddyfile" ''
    {
      # ACME account email, for certificate expiry/problem notices.
      email ${cfg.acmeEmail}
    }
    import ${sites}/*.Caddyfile
  '';

  # Fails the build on any config error. `adapt` parses and converts without
  # provisioning, so missing runtime paths (pushed content, log dirs) are fine.
  validated = pkgs.runCommand "Caddyfile-validated" { } ''
    export HOME=$TMPDIR
    ${caddy}/bin/caddy adapt --adapter caddyfile --config ${caddyfile} > /dev/null
    cp ${caddyfile} $out
  '';
in
{
  options.web = {
    sites = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.addCheck lib.types.attrs (site: site ? caddyConfig && builtins.isString site.caddyConfig)
      );
      default = { };
      example = lib.literalExpression "{ my-site = inputs.my-site; }";
      description = ''
        Sites to serve, keyed by name. Each value is a flake (input) whose
        outputs include `caddyConfig`, a self-contained Caddyfile fragment.
      '';
    };

    acmeEmail = lib.mkOption {
      type = lib.types.str;
      description = "Email for the ACME account (certificate expiry/problem notices).";
    };
  };

  config = lib.mkIf (cfg.sites != { }) {
    services.caddy = {
      enable = true;
      adapter = "caddyfile";
      configFile = validated;
    };

    # Caddy's data dir holds ACME account and certificate keys. systemd
    # re-applies StateDirectoryMode on every start (default 0755), which would
    # override a stricter mode on a persisted directory, so set it here.
    systemd.services.caddy.serviceConfig.StateDirectoryMode = "0700";

    # On PATH for debugging (`caddy validate`, `caddy adapt`) with the same
    # plugins as the service.
    environment.systemPackages = [ caddy ];

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };
}
