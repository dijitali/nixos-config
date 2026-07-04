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
      # Randomise the kernel stack offset on each syscall entry.
      "randomize_kstack_offset=on"
      # Don't merge slab caches of similar sizes; keeps heap-spray/overflow
      # exploits from reaching objects in other caches.
      "slab_nomerge"
      # Remove the legacy fixed-address vsyscall page (ancient-glibc compat
      # only), a classic ROP target at a known address.
      "vsyscall=none"
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
      # Protect against TIME-WAIT assassination (RFC 1337)
      "net.ipv4.tcp_rfc1337" = 1;
      # Log packets with spoofed/unroutable source addresses
      "net.ipv4.conf.all.log_martians" = 1;
      "net.ipv4.conf.default.log_martians" = 1;
      # Don't log responses to bogus ICMP errors (avoids log spam attacks)
      "net.ipv4.icmp_ignore_bogus_error_responses" = 1;
      # Don't auto-load TTY line disciplines from unprivileged code
      "dev.tty.ldisc_autoload" = 0;
      # Disable io_uring, a large and CVE-prone unprivileged kernel surface.
      # 2 = disabled for everyone. If an app breaks on io_uring, drop to 1
      # (root/CAP_SYS_ADMIN only) or remove.
      "kernel.io_uring_disabled" = 2;
    };
  };
}
