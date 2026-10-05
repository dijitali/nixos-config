# Caddy serving the ieuan.net family of sites, configured declaratively.
#
# Each site's Caddy config comes from its own repo, pinned as a flake input
# (see flake.nix): ieuan-net, ieuan-co-uk, jensys-uk, net-diagnostics,
# jnkns-uk. They are assembled into one store directory and validated with
# `caddy adapt` at build time, so a broken site config fails the build rather
# than the deploy. To roll out a site change: commit to the site repo, then
# `nix flake update <repo>` here and deploy.
#
# The one thing still pushed is ieuan-net's built site content
# (`mise run deploy` rsyncs it into /var/www/public): building it needs a GPG
# key and Spotify credentials, so it can't be a Nix build.
{
  config,
  inputs,
  pkgs,
  ...
}:

let
  caddy = config.services.caddy.package;

  # Site configs, with the absolute paths that pointed at pushed files on the
  # Ubuntu server rewritten to the store. --replace-fail makes the build fail if
  # a repo changes the path, instead of silently serving the wrong thing.
  sites = pkgs.runCommand "caddy-sites" { } ''
    mkdir -p $out
    cp ${inputs.ieuan-net}/ieuan-net.Caddyfile ${inputs.ieuan-net}/ieuan-net.Caddyfile.snippets $out/
    cp ${inputs.ieuan-co-uk}/Caddyfile $out/ieuan-co-uk.Caddyfile
    cp ${inputs.jensys-uk}/Caddyfile $out/jensys-uk.Caddyfile
    substitute ${inputs.net-diagnostics}/Caddyfile $out/net-ieuan-net.Caddyfile \
      --replace-fail /var/www/net-ieuan-net ${inputs.net-diagnostics}/public
    substitute ${inputs.jnkns-uk}/Caddyfile $out/jnkns-uk.Caddyfile \
      --replace-fail /etc/caddy/sites-enabled/jenkins-family-root-ca-2026.crt \
        ${inputs.jnkns-uk}/jenkins-family-root-ca-2026.crt
  '';

  # - The admin endpoint stays at its localhost-only default: the unit's reload
  #   (on config change, and ieuan-net's deploy.sh after pushing content) goes
  #   through it.
  # - Only *.Caddyfile is imported: snippet files are imported by their site
  #   file, and importing them twice is a config error.
  caddyfile = pkgs.writeText "Caddyfile" ''
    {
      # ACME account email, for certificate expiry/problem notices.
      email hi@ieuan.net
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
  services.caddy = {
    enable = true;

    # Same plugin pin as ieuan-net/flake.nix: the access_log snippet's
    # `format transform` needs transform-encoder. Keep the pin in sync; the
    # hash differs from ieuan-net's because it also covers the Caddy version
    # (this flake's nixpkgs vs ieuan-net's). On a mismatch, nix prints the
    # hash it got; paste it here.
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddyserver/transform-encoder@v0.0.0-20260423033309-ba4124974830" ];
      hash = "sha256-EACMG870NkglP9fQBQR4/IOWsT+uqId02Di6BfVFfo0=";
    };

    adapter = "caddyfile";
    configFile = validated;
  };

  # The Caddy unit is sandboxed (ProtectSystem) with only dataDir writable; the
  # access log lives on tmpfs under /run/access, as on the Ubuntu server.
  systemd.services.caddy.serviceConfig.ReadWritePaths = [ "/run/access" ];
  # Caddy's data dir holds ACME account and certificate keys. systemd re-applies
  # StateDirectoryMode on every start (default 0755), which would override the
  # 0700 set on the persisted directory, so set it here too.
  systemd.services.caddy.serviceConfig.StateDirectoryMode = "0700";

  # On PATH for debugging (`caddy validate`, `caddy adapt`) with the same
  # plugins as the service.
  environment.systemPackages = [ caddy ];

  systemd.tmpfiles.rules = [
    # ieuan-net's pushed content and the dated backups of replaced files, both
    # written by its deploy.sh over rsync as ieuan.
    "d /var/www/public 0755 ieuan users -"
    "d /var/backups/ieuan-net 0755 ieuan users -"
    # Access log directory for the access_log snippet.
    "d /run/access 0750 caddy caddy -"
  ];

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
