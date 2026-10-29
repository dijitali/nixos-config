"""Scan the running system for known vulnerabilities and mail what's open.

Two scanners, because neither alone sees everything:

- vulnix: every package in the system's runtime closure against NVD (CVSS
  scored), filtered through vulnix-whitelist.toml.
- govulncheck: every Go binary in the closure against the Go vulnerability
  database, which covers the Go standard library and modules compiled into a
  binary. Only symbol-level findings (the vulnerable code is reachable) count.

A report is mailed when anything is open, when something was resolved since
the last report, or when a scanner failed. Clean runs stay quiet.
"""

import email.message
import email.utils
import json
import os
import socket
import subprocess
import sys
from datetime import date
from pathlib import Path

GO_BUILDINFO_MAGIC = b"\xff Go buildinf:"


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def tail(text, lines=20):
    return "\n".join(text.strip().splitlines()[-lines:])


def scan_vulnix(cfg, system, problems):
    """CVSS >= minScore (or not yet scored) CVEs in the runtime closure."""
    proc = run(
        [
            "vulnix",
            "--closure",
            "--json",
            "--cache-dir",
            cfg["cacheDir"],
            "--whitelist",
            cfg["whitelist"],
            system,
        ]
    )
    # Exit 2 means both "vulnerable" and "crashed"; only valid JSON tells them apart.
    try:
        items = json.loads(proc.stdout)
    except json.JSONDecodeError:
        problems.append(
            f"vulnix failed (exit {proc.returncode}). A system deployed with "
            "`make deploy` has no .drv files here until the next auto-upgrade.\n"
            + tail(proc.stderr)
        )
        return []
    findings = []
    for item in items:
        for cve in item["affected_by"]:
            score = item["cvssv3_basescore"].get(cve)
            if score is not None and score < cfg["minScore"]:
                continue
            findings.append(
                {
                    "key": f"{item['pname']} {cve}",
                    "score": score,
                    "package": item["name"],
                    "cve": cve,
                    "summary": item.get("description", {}).get(cve, ""),
                }
            )
    return sorted(findings, key=lambda f: (-(f["score"] or 10), f["key"]))


def go_binaries(system):
    """ELF executables in the closure that carry Go build info, one per inode."""
    closure = run(["nix-store", "--query", "--requisites", system]).stdout.split()
    seen, found = set(), []
    for path in closure:
        for sub in ("bin", "sbin", "libexec"):
            root = Path(path, sub)
            if not root.is_dir():
                continue
            for dirpath, _, files in os.walk(root):
                for name in files:
                    file = Path(dirpath, name)
                    if file.is_symlink():
                        continue
                    st = file.stat()
                    if st.st_ino in seen or not st.st_mode & 0o111:
                        continue
                    with file.open("rb") as f:
                        if f.read(4) != b"\x7fELF":
                            continue
                        if GO_BUILDINFO_MAGIC not in f.read():
                            continue
                    seen.add(st.st_ino)
                    found.append(file)
    return found


def govulncheck_stream(text):
    """govulncheck -format json prints a stream of JSON objects."""
    decoder, pos = json.JSONDecoder(), 0
    while True:
        while pos < len(text) and text[pos].isspace():
            pos += 1
        if pos >= len(text):
            return
        obj, pos = decoder.raw_decode(text, pos)
        yield obj


def scan_go(cfg, system, problems):
    """Reachable Go vulnerabilities, one finding per advisory and module."""
    by_id = {}
    for binary in go_binaries(system):
        proc = run(["govulncheck", "-mode=binary", "-format=json", str(binary)])
        try:
            objs = list(govulncheck_stream(proc.stdout))
        except json.JSONDecodeError:
            objs = []
        if proc.returncode != 0 or not objs:
            problems.append(
                f"govulncheck failed on {binary} (exit {proc.returncode}).\n"
                + tail(proc.stderr)
            )
            continue
        osv = {o["osv"]["id"]: o["osv"] for o in objs if "osv" in o}
        # Strip /nix/store/<hash>- so the report names the package.
        pkg = binary.relative_to("/nix/store").parts[0].split("-", 1)[1]
        for o in objs:
            finding = o.get("finding")
            if not finding or not finding["trace"][0].get("function"):
                continue
            gid = finding["osv"]
            if gid in cfg["goIgnore"]:
                continue
            top = finding["trace"][0]
            # One advisory can sit in several modules (net/http's HTTP/2 is
            # both stdlib and golang.org/x/net), each needing its own fix.
            entry = by_id.setdefault(
                (gid, top["module"]),
                {
                    "key": f"{gid} {top['module']}",
                    "id": gid,
                    "cves": [a for a in osv[gid].get("aliases", []) if a.startswith("CVE-")],
                    "module": top["module"],
                    "version": top.get("version", "?"),
                    "fixed": finding.get("fixed_version", "none"),
                    "summary": osv[gid].get("summary", ""),
                    "binaries": set(),
                },
            )
            entry["binaries"].add(f"{pkg}: {binary.name.removeprefix('.').removesuffix('-wrapped')}")
    return sorted(by_id.values(), key=lambda f: f["key"])


def format_report(host, system, vulnix, go, new, resolved, problems):
    lines = [f"{host}: vulnerability scan, {date.today()}", f"System: {system}", ""]
    mark = lambda f: " [new]" if f["key"] in new else ""  # noqa: E731
    if go:
        lines.append("Go binaries (govulncheck; the vulnerable code is reachable)")
        lines.append("Details for each ID: https://pkg.go.dev/vuln/<ID>")
        groups = {}
        for f in go:
            groups.setdefault((f["module"], f["version"]), []).append(f)
        for (module, version), fs in sorted(groups.items()):
            pkgs = sorted({b.split(":")[0] for f in fs for b in f["binaries"]})
            lines += ["", f"  {module} {version}, in {', '.join(pkgs)}"]
            for f in fs:
                cves = ",".join(f["cves"]) or "no CVE yet"
                lines += [
                    f"    {f['id']}  {cves}  fixed in {f['fixed']}{mark(f)}",
                    f"        {f['summary']}",
                ]
        lines.append("")
    if vulnix:
        lines.append("System packages (vulnix; runtime closure, not whitelisted)")
        for f in vulnix:
            score = f"{f['score']:4.1f}" if f["score"] is not None else " n/a"
            lines += [
                f"  {score}  {f['package']}  {f['cve']}{mark(f)}",
                f"      {f['summary'][:300]}",
                f"      https://nvd.nist.gov/vuln/detail/{f['cve']}",
            ]
        lines.append("")
    if resolved:
        lines.append("Resolved since the last report")
        lines += [f"  {key}" for key in sorted(resolved)]
        lines.append("")
    if problems:
        lines.append("Problems (this report may be incomplete)")
        lines += ["  " + p.replace("\n", "\n    ") for p in problems]
        lines.append("")
    lines += [
        "False positives: add them, with the reason, to",
        "modules/vuln-scan/vulnix-whitelist.toml or security.vulnScan.goIgnore",
        "in nixos-config.",
    ]
    return "\n".join(lines) + "\n"


def send(cfg, subject, body):
    msg = email.message.EmailMessage()
    msg["From"] = cfg["mailFrom"]
    msg["To"] = cfg["mailTo"]
    msg["Subject"] = subject
    msg["Date"] = email.utils.formatdate(localtime=True)
    msg["Message-ID"] = email.utils.make_msgid(domain=cfg["mailFrom"].split("@")[-1])
    msg.set_content(body, cte="8bit")
    subprocess.run(["msmtp", "--read-recipients"], input=msg.as_bytes(), check=True)


def main():
    cfg = json.loads(Path(sys.argv[1]).read_text())
    host = socket.gethostname()
    system = os.path.realpath(cfg["system"])
    problems = []

    vulnix = scan_vulnix(cfg, system, problems)
    go = scan_go(cfg, system, problems)

    state_file = Path(cfg["stateDir"], "reported.json")
    try:
        previous = set(json.loads(state_file.read_text()))
    except FileNotFoundError:
        previous = set()
    current = {f["key"] for f in vulnix + go}
    new, resolved = current - previous, previous - current
    # A scanner that failed found nothing; that is not the same as "resolved",
    # so keep the previous findings for comparison next time.
    remembered = current
    if problems:
        resolved = set()
        remembered = current | previous

    if current or resolved or problems:
        if current:
            subject = f"[{host}] {len(current)} open vulnerabilities ({len(new)} new)"
        elif resolved:
            subject = f"[{host}] all clear: {len(resolved)} resolved"
        else:
            subject = f"[{host}] vulnerability scan incomplete"
        if problems and current:
            subject += ", scan incomplete"
        send(cfg, subject, format_report(host, system, vulnix, go, new, resolved, problems))

    state_file.write_text(json.dumps(sorted(remembered), indent=1) + "\n")


if __name__ == "__main__":
    main()
