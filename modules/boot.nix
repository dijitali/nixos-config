# Boot loader, kernel hardening and a themed graphical boot/unlock flow.
{ pkgs, ... }:

{
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        # Keep only the most recent generations in the boot menu (and on the
        # ESP), instead of every generation ever built. Pairs with the weekly
        # GC / auto-upgrade to stop the menu and EFI partition filling up.
        configurationLimit = 10;
        # Disable the boot-time command-line editor. The default lets anyone at
        # the keyboard edit the kernel cmdline (e.g. init=/bin/sh) to bypass
        # access controls, which undermines the hardening below.
        editor = false;
        # Use the highest available console resolution for the menu/prompt.
        consoleMode = "max";
      };
      efi.canTouchEfiVariables = true;
      # Seconds the boot menu is shown before booting the default generation.
      # With splash enabled below, this keeps a brief window to pick an older
      # build; set to 0 to hide the menu entirely behind the splash.
      timeout = 5;
    };

    # Graphical boot splash that also themes the LUKS passphrase prompt.
    # Breeze matches the Plasma 6 / SDDM look for a consistent boot -> unlock
    # -> login flow.
    plymouth = {
      enable = true;
      theme = "breeze";
      themePackages = [ pkgs.kdePackages.breeze-plymouth ];
    };

    # Render the LUKS unlock under the systemd-based initrd so Plymouth can
    # draw the passphrase prompt graphically instead of the plain console text.
    initrd.systemd.enable = true;

    # Quiet, seamless boot to let the splash take over the screen, combined
    # with memory-hardening allocator options. The latter have a small runtime
    # cost but real exploit-mitigation value (zero-on-alloc/free, freelist
    # randomisation).
    kernelParams = [
      "quiet"
      "splash"
      "init_on_alloc=1"
      "init_on_free=1"
      "page_alloc.shuffle=1"
    ];
    consoleLogLevel = 0;
    initrd.verbose = false;

    kernel.sysctl = {
      # Restrict kernel pointer access
      "kernel.kptr_restrict" = 2;
      # Restrict dmesg to root
      "kernel.dmesg_restrict" = 1;
      # Disable SysRq
      "kernel.sysrq" = 0;
      # Protect symlinks/hardlinks
      "fs.protected_symlinks" = 1;
      "fs.protected_hardlinks" = 1;
      # Disable IP forwarding (not a router)
      "net.ipv4.ip_forward" = 0;
      # SYN flood protection
      "net.ipv4.tcp_syncookies" = 1;
      # Ignore ICMP redirects
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv6.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv6.conf.default.accept_redirects" = 0;
      # Never send ICMP redirects (not a router)
      "net.ipv4.conf.all.send_redirects" = 0;
      "net.ipv4.conf.default.send_redirects" = 0;
      # Drop source-routed packets
      "net.ipv4.conf.all.accept_source_route" = 0;
      "net.ipv6.conf.all.accept_source_route" = 0;
      # Reverse-path filtering (drop spoofed/asymmetric traffic)
      "net.ipv4.conf.all.rp_filter" = 1;
      "net.ipv4.conf.default.rp_filter" = 1;
      # Only allow a process to ptrace its own descendants
      "kernel.yama.ptrace_scope" = 1;
      # Lock down unprivileged BPF (common local-privesc surface)
      "kernel.unprivileged_bpf_disabled" = 1;
      "net.core.bpf_jit_harden" = 2;
      # Extend symlink-style protections to FIFOs/regular files in sticky dirs
      "fs.protected_fifos" = 2;
      "fs.protected_regular" = 2;
      # Block kexec-based kernel replacement and restrict perf subsystem
      "kernel.kexec_load_disabled" = 1;
      "kernel.perf_event_paranoid" = 3;
    };
  };
}
