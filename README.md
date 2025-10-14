<p align="center">
  <img src="info/logo.png" alt="Salt Shaker - Portable SaltStack Automation" width="200">
</p>

<h1 align="center">🧂 Salt-Shaker 🧂</h1>
<h3 align="center">Portable SaltStack Automation for Air-Gapped Deployments</h3>

<p align="center">
  <a href="https://github.com/<your-username>/<your-repo>/actions"><img src="https://img.shields.io/github/workflow/status/<your-username>/<your-repo>/CI?label=Build&style=flat-square" alt="Build Status"></a>
  <a href="https://www.python.org/"><img src="https://img.shields.io/badge/Python-2.7%20|%203.10-blue?style=flat-square" alt="Python Version"></a>
  <a href="https://www.saltstack.com/"><img src="https://img.shields.io/badge/SaltStack-v3006+-green?style=flat-square" alt="SaltStack"></a>
  <a href="https://github.com/<your-username>/<your-repo>/license"><img src="https://img.shields.io/github/license/<your-username>/<your-repo>?style=flat-square" alt="License"></a>
  <img src="https://img.shields.io/badge/Version-1.11-orange?style=flat-square" alt="Version">
</p>

<p align="center">
  <strong>🚀 Streamlined, offline SaltStack toolchains for RHEL/CentOS 7.9 and Rocky/RHEL 8/9</strong>
</p>

<div style="text-align: center; color: #ffffff; background-color: #ff4d4f; padding: 15px; border-radius: 5px; margin: 20px 0;">
  <span style="font-size: 1.3em;">⚠️</span> <strong>Under Active Development</strong><br>
  Not fully functional yet—join us to make it awesome! 🎉
</div>

---

## 📜 Table of Contents

- [Why Salt-Shaker?](#-why-salt-shaker)
- [Project Overview](#-project-overview)
- [Project Layout](#-project-layout)
- [Platform Notes](#-platform-notes)
- [Primary Entrypoints](#-primary-entrypoints)
- [Clean-House](#-clean-house)
- [Roster & Configs](#-roster--configs)
- [Deployables](#-deployables)
- [Vendor & Thin Checks](#-vendor--thin-checks)
- [Rules & Standards](#-rules--standards)
- [Quick Commands](#-quick-commands)
- [FAQs](#-faqs)
- [Recovery](#-recovery)
- [Contributing](#-contributing)
- [License](#-license)

---

## 🌟 Why Salt-Shaker?

**Salt-Shaker** brings **portable, offline automation** to SaltStack, designed for **air-gapped** and **legacy environments**. It’s your go-to tool for:

- 🛠️ **Seamless Deployments**: Curated “thin” packages and onedir trees for RHEL/CentOS 7.9 and Rocky/RHEL 8/9.
- 🔒 **Isolated Networks**: No external dependencies, no system installs.
- 📋 **CSV-Driven Rosters**: Generate targeted rosters by pod for precise control.
- 🧼 **Clean Operations**: Safe cleanup with snapshots and high-signal output (✓/✗).

Built for **reliability**, **portability**, and **simplicity**, Salt-Shaker is perfect for automation enthusiasts tackling complex, disconnected environments. 🚀

---

## 🎯 Project Overview

**Salt-Shaker** is a lightweight, self-contained automation toolchain powered by **SaltStack**. It simplifies deployments in **air-gapped** and **legacy** environments, supporting:

- **RHEL/CentOS 7.9** (Python 2.7.5)
- **Rocky/RHEL 8 & 9** controllers (Python 3.10+)

### 🔑 Goals
- 🗂️ Generate rosters from **CSV** files, organized by **pod**.
- 📦 Stage deployables (RPM/tar) for easy distribution.
- 🌐 Operate cleanly in **isolated networks** with curated “thin” packages.

### 🛠️ Target Environments
- **RHEL/CentOS 7.9** (Python 2.7.5)
- **Rocky/RHEL 8 & 9** (Python 3.10+)

---

## 📁 Project Layout

```plaintext
salt-shaker/
├─ archive/                 # Snapshots & backups from cleaners
├─ bin/                     # Helper scripts/wrappers
├─ cleanup/                 # Standard, Full, Factory reset scripts
├─ env/                     # Config templates & environment snippets
├─ info/                    # Docs, How-To, FAQs
├─ modules/                 # Operational modules (build, verify, etc.)
├─ offline/                 # Offline RPMs & tarballs
│  ├─ deps/{el7,el8,el9}/  # Platform-specific dependencies
│  └─ salt/{el7,el8,el9,thin,tarballs}/  # Salt assets
├─ rpm/                     # Project RPM build area
├─ runtime/                 # Logs, rosters, pillars
│  ├─ logs/                 # Runtime logs
│  ├─ roster/               # Generated rosters
│  └─ pillar/               # Working pillar data
├─ support/                 # Notes, examples, references
├─ tools/                   # Utility scripts
├─ vendor/                  # Onedir trees & thin caches
│  ├─ el7/{salt,thin}/     # EL7 assets
│  ├─ el8/{salt,thin}/     # EL8 assets
│  └─ el9/{salt,thin}/     # EL9 assets
├─ salt-shaker.sh           # Main entry (EL8/EL9)
└─ salt-shaker-el7.sh       # EL7 entry
```

**Preserved by Cleaners**: `archive/`, `env/`, `info/`, `modules/`, `offline/`, `rpm/`, `tools/`, `vendor/`, `support/`, `salt-shaker.sh`, `salt-shaker-el7.sh`

---

## 🧩 Platform Notes

- **EL7**: Uses Python 2.7-based thin builds (`offline/salt/thin/el7/`).
- **EL8/EL9**: Uses modern onedir with Python 3.10+ (`offline/salt/el8|el9/`).
- **Wrappers**: Auto-detect OS and select the correct onedir from `vendor/el*/salt`.

No system installs required—everything runs from the project root.

---

## 🧰 Primary Entrypoints

Run the appropriate script based on your platform:

```bash
# EL8/EL9
./salt-shaker.sh

# EL7
./salt-shaker-el7.sh
```

### EL8/EL9 Menu (v1.11)

> **Note**: Menu options are subject to updates as modules are refined.

```bash
╔══════════════════════════════════════════════════════════════════════════════╗
║                     S A L T • S H A K E R v1.11                              ║
║ Portable SaltStack Automation for Air-Gapped Environments                    ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ Project: /sto/salt-shaker │ OS: Rocky Linux release 8.10 │ Modules: 12       ║
╚══════════════════════════════════════════════════════════════════════════════╝

┌─ Salt Shaker Menu ──────────────────────────────────────────────────────┐
│ 1. setup                - Initialize project layout                    │
│ 2. check-dirs           - Validate project directories                 │
│ 3. create-csv           - Generate package CSV                        │
│ 4. verify-packages      - Verify offline packages                     │
│ 5. extract-binaries     - Extract controller binaries                 │
│ 6. build-thin-el7       - Build salt-thin for EL7                     │
│ 7. check-vendors        - Check vendors & thin                        │
│ 8. remote-test          - Remote test via salt-ssh                    │
│ 9. generate-configs     - Generate salt configs                       │
│ 10. generate-roster     - Generate roster                             │
│ 11. create-project-rpm  - Package project RPM                         │
│ 12. stage-deployables   - Stage deployables                           │
└─ Options: [Q]uit  [N]ext  [P]rev  [R]efresh  [H]elp                   │
   Page 0/1  (12 modules loaded)

Select option (number/Q/N/P/R/H): 
```

### EL7 Menu (v8.10)

> **Note**: Menu options are subject to updates as modules are refined.

```bash
╔══════════════════════════════════════════════════════════════════════════════╗
║                         S A L T • S H A K E R v8.10                          ║
╠══════════════════════════════════════════════════════════════════════════════╣
║          Portable SaltStack Automation for Air-Gapped Environments           ║
║                 Red Hat Enterprise Linux Server 7.9                         ║
╠══════════════════════════════════════════════════════════════════════════════╣
║   1)       init dirs                                                        ║
║   2)       create csv                                                       ║
║   3)       verify packages                                                  ║
║   4)       extract binaries                                                 ║
║   5)       build thin el7                                                   ║
║   6)       check vendors                                                    ║
║   7)       remote test                                                      ║
║   8)       generate configs                                                 ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  [1-8] Select • [N] Next • [P] Prev • [R] Refresh • [H] Help • [Q] Quit      ║
╚══════════════════════════════════════════════════════════════════════════════╝
Select [1-8 / N / P / R / H / Q]:
```

**Output Style**: All modules use concise, high-signal output with ✓/✗ indicators to minimize scrollback noise.

---

## 🧼 Clean-House

Three levels of cleanup, all with **snapshots** for safety:

```bash
# Safe cleanup (logs, temp files)
./cleanup/standard.sh

# Deeper reset (includes vendor/salt)
./cleanup/full.sh

# Rebuild posture (preserves sources)
./cleanup/factory-reset.sh
```

### Cleanup Profiles

| Profile        | Description                                                                 | Preserves                     |
|----------------|-----------------------------------------------------------------------------|-------------------------------|
| **Standard** ✅ | Rotates logs, clears `tmp/`, `.cache/`, `vendor/thin/`, `*.bak`, CSVs       | `offline/`, `env/`, sources   |
| **Full** 🧹    | Standard + wipes `vendor/el*/salt` (recreated)                               | `offline/`, `env/`, sources   |
| **Factory** 🏭 | Wipes build artifacts, deployables, vendor/salt; recreates skeletons         | `offline/`, `env/`, sources   |

> **Safety**: All cleaners create snapshots in `archive/snapshots/` before making changes.

---

## 🧾 Roster & Configs

### Generate Configs
Creates templates for Salt operation (SSH configs, master/minion options, pillar scaffolding). Customize these as needed.

```bash
./modules/09-generate-configs.sh
```

### Generate Roster
Builds `salt-ssh` rosters from CSV files, with **pod selection** for targeted deployments.

```bash
./modules/10-generate-roster.sh
```

**Recommended CSV Format**:
```csv
pod,hostname,host,port,user,os,notes
edge-a,node01,node01.edge.example,22,root,el8,dmz
edge-a,node02,node02.edge.example,22,ec2-user,el9,prod
lab-x,node99,10.20.30.99,2222,lab,el7,legacy
```

---

## 📦 Deployables

The `stage-deployables` module collects runtime assets (wrappers, configs, thin archives) into `deployables/` for packaging or transfer.

```bash
./modules/12-stage-deployables.sh
```

---

## 🧪 Vendor & Thin Checks

Verify onedir executables and thin archives:

```bash
./modules/06-check-vendors.sh
```

**Sample Output**:
```plaintext
════════════════════════════════════════════════════════════════════
▶ Vendor & Thin Checks
Project Root: /path/to/salt-shaker
════════════════════════════════════════════════════════════════════
Platform | Status | Python   | salt-ssh        | salt-call       | Path
-------- | ------ | -------- | --------------- | --------------- | ------------------
el7      | OK     | 2.7.x    | 2019.2.x        | 2019.2.x        | vendor/el7/salt
el8      | OK     | 3.10.18  | 3007.8 (Chlor.) | 3007.8 (Chlor.) | vendor/el8/salt
el9      | OK     | 3.10.18  | 3007.8 (Chlor.) | 3007.8 (Chlor.) | vendor/el9/salt
✓ Thin found: vendor/thin/salt-thin.tgz (1753 entries)
READY ✓ (el8 · vendor/el8/salt · 3.10.18)
```

---

## 🧱 Rules & Standards

- **Portable**: All paths relative to project root; **no symlinks**.
- **Offline-First**: All dependencies in `offline/`.
- **Predictable**: Idempotent scripts; preserved critical directories.
- **No External Installs**: Uses wrappers and vendor trees.
- **Safety**:
  - Preserves `offline/`, `env/`, `info/`, `modules/`, `tools/`, `rpm/`, `archive/`, `support/`.
  - Snapshots before cleanup.
  - High-signal output with ✓/✗.

---

## 🔧 Quick Commands

```bash
# Verify vendor & thin
./modules/06-check-vendors.sh

# Build EL7 thin
./modules/05-build-thin-el7.sh --force -y

# Extract binaries
./modules/04-extract-binaries.sh

# Generate configs/roster
./modules/09-generate-configs.sh
./modules/10-generate-roster.sh

# Stage deployables
./modules/12-stage-deployables.sh

# Cleaners
./cleanup/standard.sh
./cleanup/full.sh
./cleanup/factory-reset.sh
```

---

## 🧠 FAQs

<details>
<summary><strong>Can I run <code>standard.sh</code> anytime without breaking work?</strong></summary>
Yes! It’s a safe “mop & dust” that rotates logs, clears temporary files (e.g., `tmp/`, `.cache/`, `*.bak`), and recreates skeletons. Critical directories are preserved.
</details>

<details>
<summary><strong>What does <code>full.sh</code> add?</strong></summary>
Everything in `standard.sh` plus wiping `vendor/el*/salt` (recreated). `offline/` remains untouched.
</details>

<details>
<summary><strong>Will cleaners touch <code>offline/</code>?</strong></summary>
**No.** Offline assets are critical and always preserved.
</details>

<details>
<summary><strong>Can I select pods from a large CSV?</strong></summary>
Yes, the roster generator prompts for **pod groups** to create subset rosters (e.g., per VPN segment).
</details>

<details>
<summary><strong>Configs vs. Roster?</strong></summary>
**Configs**: Generate structure/templates for Salt (SSH, master/minion, pillars).<br>
**Roster**: Builds `salt-ssh` target lists from CSV with pod selection.
</details>

<details>
<summary><strong>How do I recover from a bad cleanup?</strong></summary>
Restore from a snapshot in `archive/snapshots/` by extracting at the project root.
</details>

---

## 🛟 Recovery

Restore a known-good zip:

```bash
unzip -q /sto/salt-shaker-knowngood.zip -d /sto
chown -R root:root /sto/salt-shaker
find /sto/salt-shaker -type f -name "*.sh" -exec chmod +x {} +
```

---

## 🤝 Contributing

Join us to make **Salt-Shaker** the ultimate SaltStack tool! 🎉
- See our [Contributing Guide](CONTRIBUTING.md).
- Report bugs or suggest features in [Issues](https://github.com/<your-username>/<your-repo>/issues).
- Submit pull requests to enhance modules or fix issues.

---

## 📜 License

Licensed under the [MIT License](LICENSE). See the [LICENSE](LICENSE) file for details.

<p align="center">
  <em>Built with 💖 for automation heroes tackling air-gapped challenges!</em><br>
  <a href="https://github.com/<your-username>/<your-repo>/stargazers"><img src="https://img.shields.io/github/stars/<your-username>/<your-repo>?style=social" alt="GitHub Stars"></a>
</p>
