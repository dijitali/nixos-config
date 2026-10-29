# Weekly vulnerability scan of the running system, mailed when anything is
# open, newly resolved, or the scan itself failed (see vuln-scan.py); failed
# auto-upgrades are mailed too. Findings
# go to email, never to this repo: it is public, and an open-findings list for
# a live server doesn't belong in it.
#
# The scan reads /run/current-system, so it reports what is actually deployed.
# vulnix needs the system's .drv files, which exist here once an auto-upgrade
# has evaluated the flake on the server (a `make deploy` copies outputs only);
# until then the report says vulnix couldn't run and govulncheck still does.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.security.vulnScan;

  settings = pkgs.writeText "vuln-scan.json" (
    builtins.toJSON {
      inherit (cfg)
        mailTo
        mailFrom
        minScore
        goIgnore
        ;
      whitelist = "${cfg.whitelist}";
      system = "/run/current-system";
      stateDir = "/var/lib/vuln-scan";
      cacheDir = "/var/cache/vuln-scan";
    }
  );

  # Mails the tail of a failed unit's journal; the unit is the argument
  # (mail-unit-failure@<unit>.service, used through onFailure).
  failureMail = pkgs.writeShellScript "mail-unit-failure" ''
    {
      printf 'From: %s\nTo: %s\nSubject: [%s] %s failed\n\n' \
        ${lib.escapeShellArg cfg.mailFrom} ${lib.escapeShellArg cfg.mailTo} ${config.networking.hostName} "$1"
      ${config.systemd.package}/bin/journalctl --unit "$1" --lines 60 --no-pager
    } | ${pkgs.msmtp}/bin/msmtp --read-recipients
  '';
in
{
  options.security.vulnScan = {
    enable = lib.mkEnableOption "the weekly mailed vulnerability scan";

    mailTo = lib.mkOption {
      type = lib.types.str;
      description = "Where reports go.";
    };

    mailFrom = lib.mkOption {
      type = lib.types.str;
      default = cfg.mailTo;
      defaultText = lib.literalExpression "config.security.vulnScan.mailTo";
      description = "Sender address; must be one the SMTP account may send as.";
    };

    smtp = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "smtp.fastmail.com";
        description = "SMTP submission server (implicit TLS on port 465).";
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = cfg.mailFrom;
        defaultText = lib.literalExpression "config.security.vulnScan.mailFrom";
        description = "SMTP login.";
      };
      passwordFile = lib.mkOption {
        type = lib.types.str;
        description = "File holding the SMTP password (a Fastmail app password), readable by root.";
      };
    };

    dates = lib.mkOption {
      type = lib.types.str;
      # After the nightly auto-upgrade (04:40), so the scan sees its result.
      default = "Mon *-*-* 06:17";
      description = "When to scan (systemd calendar event).";
    };

    minScore = lib.mkOption {
      type = lib.types.float;
      default = 7.0;
      description = "Lowest CVSS v3 base score reported from vulnix. Not-yet-scored CVEs are always reported.";
    };

    whitelist = lib.mkOption {
      type = lib.types.path;
      default = ./vulnix-whitelist.toml;
      description = "vulnix whitelist of triaged false positives.";
    };

    goIgnore = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "GO-2026-5932" = "x/crypto/openpgp is linked but never called with untrusted input";
      };
      description = "Go vulnerability IDs to leave out of reports, each with the reason.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.msmtp = {
      enable = true;
      accounts.default = {
        inherit (cfg.smtp) host user;
        from = cfg.mailFrom;
        port = 465;
        tls = true;
        tls_starttls = false;
        auth = true;
        passwordeval = "${pkgs.coreutils}/bin/cat ${cfg.smtp.passwordFile}";
      };
    };

    systemd.services.vuln-scan = {
      description = "Scan the running system for known vulnerabilities";
      after = [
        "network-online.target"
        "nixos-upgrade.service"
      ];
      wants = [ "network-online.target" ];
      onFailure = [ "mail-unit-failure@vuln-scan.service" ];
      path = [
        pkgs.vulnix
        pkgs.govulncheck
        pkgs.msmtp
        config.nix.package
      ];
      environment = {
        # Talk to the daemon instead of opening the store database directly,
        # which ProtectSystem leaves read-only.
        NIX_REMOTE = "daemon";
        HOME = "/var/cache/vuln-scan";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.python3.interpreter} -I ${./vuln-scan.py} ${settings}";
        StateDirectory = "vuln-scan";
        CacheDirectory = "vuln-scan";
        # Root, because the Nix daemon only admits root and @wheel
        # (modules/nix.nix) and the SMTP password is root-only; the rest is
        # read-only.
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        Nice = 19;
        IOSchedulingClass = "idle";
      };
    };

    systemd.services."mail-unit-failure@" = {
      description = "Mail that %i failed";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${failureMail} %i";
      };
    };

    # A failed auto-upgrade leaves the server on its old generation without a
    # word, e.g. when a nixpkgs bump changed Caddy's withPlugins hash and
    # scripts/update-caddy-hash.sh didn't run. Mail those too.
    systemd.services.nixos-upgrade.onFailure = lib.mkIf config.system.autoUpgrade.enable [
      "mail-unit-failure@nixos-upgrade.service"
    ];

    systemd.timers.vuln-scan = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.dates;
        Persistent = true;
        RandomizedDelaySec = "15min";
      };
    };
  };
}
