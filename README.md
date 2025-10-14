


# 🧂 Salt-Shaker — Offline Salt SSH Builder & Remote Runner 🧂

> **Target:** RHEL/CentOS **7.9** (Python 2.7.5) + Rocky/RHEL **8/9** controllers
> **Goal:** Build a portable, offline Salt SSH toolchain with curated “thin” packages, generate rosters from CSV (by **pod**), stage deployables (RPM/tar), and operate cleanly across isolated networks.

---

## 🧭 Overview

Salt-Shaker is a self-contained project for building and running Salt in legacy or air-gapped environments (EL7/EL8/EL9). It ships:

- **Offline assets** (RPMs & tarballs) for Salt and dependencies  
- **Vendor onedir trees** per platform (`vendor/el7|el8|el9/salt`)  
- **Thin archives** (`vendor/el*/thin/`)  
- **Wrappers** that select the correct onedir automatically  
- **Cleanup tooling**: `standard`, `full`, `factory-reset` with snapshots  
- **Menus** and helper modules for generating configs/rosters, building thin, verifying vendors, and staging deployables

Everything lives **inside the project root**. No symlinks. No global package installs. No writes outside the tree.

---

## 📁 Project Layout (stable)

```

salt-shaker/
├─ archive/                 # Snapshots & backups created by cleaners
├─ bin/                     # Local helper scripts/wrappers
├─ cleanup/                 # Standard / Full / Factory reset scripts
├─ env/                     # Environment snippets & config templates
├─ info/                    # Docs, How-To, FAQs
├─ modules/                 # Operational modules (build thin, checks, etc.)
├─ offline/                 # Offline RPMs & tarballs (critical, preserved)
│  ├─ deps/{el7,el8,el9}/
│  └─ salt/{el7,el8,el9,tarballs,thin}/
├─ rpm/                     # Project RPM build area
├─ runtime/                 # Runtime droppings (logs, temp, roster/pillar work)
│  ├─ logs/                 # Runtime logs (local only)
│  ├─ roster/               # Generated/working roster data
│  └─ pillar/               # Working pillar data
├─ support/                 # Notes / examples / references
├─ tools/                   # Utility scripts
├─ vendor/                  # Onedir trees + thin caches
│  ├─ el7/{salt,thin}
│  ├─ el8/{salt,thin}
│  └─ el9/{salt,thin}
├─ salt-shaker.sh           # Main entry (EL8/EL9)
└─ salt-shaker-el7.sh       # EL7 entry

````

**Never removed by cleaners:**  
`archive/ env/ info/ modules/ offline/ rpm/ tools/ vendor/ cleanup/ support/ salt-shaker.sh salt-shaker-el7.sh`

---

## 🧩 Platform Notes (EL7 vs EL8/EL9)

- **EL7**: uses a legacy python2-based thin build (offline RPMs live under `offline/salt/thin/el7/`).  
- **EL8/EL9**: use modern onedir (python3.10+). Offline packages under `offline/salt/el8|el9/`.

Wrappers detect OS major and launch the correct onedir from `vendor/el*/salt` — no system installs required.

---

## 🧰 Primary Entrypoints

```bash
# EL8 / EL9:
./salt-shaker.sh

# EL7:
./salt-shaker-el7.sh
````

Typical main menu (sample):

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                     S A L T • S H A K E R v1.11                              ║
║ Portable SaltStack Automation for Air-Gapped Environments                    ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ Project: /sto/salt-shaker │ OS: Rocky Linux release 8.10 │ Modules: 12       ║
╚══════════════════════════════════════════════════════════════════════════════╝

┌─ Salt Shaker Menu ──────────────────────────────────────────────────────┐
│
│ 1. setup                - Initialize project layout
│ 2. check-dirs           - Validate project directories
│ 3. create-csv           - Generate package CSV
│ 4. verify-packages      - Verify offline packages
│ 5. extract-binaries     - Extract controller binaries
│ 6. build-thin-el7       - Build salt-thin for EL7
│ 7. check-vendors        - Check vendors & thin
│ 8. remote-test          - Remote test via salt-ssh
│ 9. generate-configs     - Generate salt configs
│ 10. generate-roster      - Generate roster
│ 11. create-project-rpm   - Package project RPM
│ 12. stage-deployables    - Stage-deployables module
│
└─ Options: [Q]uit  [N]ext  [P]rev  [R]efresh  [H]elp
   Page 0/1  (12 modules loaded)

Select option (number/Q/N/P/R/H): 



```

All modules print short, high-signal lines with ✓ and ✗ — no noisy scrollback.

---

## 🧼 Clean-House (three levels)

From project root:

```bash
# Safe “mop & dust” (idempotent; snapshot first)
./cleanup/standard.sh

# Bigger reset; wipes vendor/el*/salt (recreated). Snapshot first.
./cleanup/full.sh

# Max reset; rebuild posture without losing sources/offline. Snapshot first.
./cleanup/factory-reset.sh
```

### What each profile does

**Standard** ✅

* Rotates root `logs/` → `archive/snapshots/logs.<ts>/`
* Removes clutter: `tmp/ .cache/ vendor/thin/ *.bak`
* Purges transient CSV artifacts (roster/runtime), re-creates skeletons
* **Creates snapshot** before changes
* **Never** touches: `offline/ env/ info/ modules/ tools/ rpm/ archive/ vendor/el*/salt`

**Full** 🧹

* Includes everything from Standard
* Also **wipes** `vendor/el7/salt`, `vendor/el8/salt`, `vendor/el9/salt` (dirs re-created)
* Leaves `offline/` **untouched**
* **Creates snapshot** before changes

**Factory Reset** 🏭

* Wipes most build artifacts, deployable outputs, and vendor salt directories
* Re-creates skeletons & empty vendor salt dirs
* **Preserves** sources and offline cache
* **Creates snapshot** before changes

> **Note:** Standard and Full both remove clutter: `*.bak`, temporary artifacts, patch leftovers, etc.

---

## 🧾 Roster & Configs

### Generate Configs

Creates structure & templates needed for Salt operation (ssh configs, master/minion/opts, pillars scaffolding). These are **templates** you customize.

### Generate Roster

Builds the `salt-ssh` roster from CSV. Because CSVs can contain many targets across VPN-segmented pods, the generator supports **selecting specific pod groups** rather than “all at once.”

Recommended CSV columns (Excel-friendly, CLI-friendly):

```
pod,hostname,host,port,user,os,notes
edge-a,node01,node01.edge.example,22,root,el8,dmz
edge-a,node02,node02.edge.example,22,ec2-user,el9,prod
lab-x,node99,10.20.30.99,2222,lab,el7,legacy
```

Generator will prompt for **pod selection** and produce a minimal, accurate roster for the chosen group.

---

## 📦 Deployables

**Stage Deployables** collects runtime-built bits (wrappers, configs, thin, etc.) into `deployables/` as a clean hand-off for packaging or transfer.

---

## 🧪 Vendor & Thin Checks

Use the module to verify **onedir executables** and **thin archive**:

```bash
./modules/06-check-vendors.sh
```

Sample output:

```
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

* **Portable**: all paths are relative to project root; **no symlinks** anywhere.
* **Offline-first**: everything required is staged under `offline/`.
* **Predictable**: scripts are idempotent; sensitive areas are preserved.
* **No external installs**: wrappers and vendor trees avoid system packages.
* **Safety**:

  * Cleaners never remove: `offline/ env/ info/ modules/ tools/ rpm/ archive/ support/` or the main scripts.
  * Snapshot before **Standard**, **Full**, **Factory**.
  * High-signal output: banners, warnings, ✓/✗.

---

## 🔧 Quick Commands

```bash
# Verify vendor & thin
./modules/06-check-vendors.sh

# Build EL7 thin from offline RPMs
./modules/05-build-thin-el7.sh --force -y

# Extract onedir binaries from offline caches
./modules/04-extract-binaries.sh

# Generate configs / roster (guided)
./modules/09-generate-configs.sh
./modules/10-generate-roster.sh

# Stage deployables
./modules/12-stage-deployables.sh

# Cleaners (with snapshot)
./cleanup/standard.sh
./cleanup/full.sh
./cleanup/factory-reset.sh
```

---

## 🧠 FAQs

**Q: Can I run `Standard` any time without breaking current work?**
**A:** Yes. It’s intended as a safe “mop & dust.” It rotates logs and removes clutter (tmp, .cache, *.bak, transient CSVs), re-creating skeleton directories.

**Q: What exactly does `Full` add?**
**A:** Everything from Standard **plus** wiping `vendor/el*/salt` to force re-extract. `offline/` remains untouched.

**Q: Will any cleaner touch `offline/`?**
**A:** **No.** Offline assets are critical and preserved.

**Q: Roster CSV has thousands of targets across pods. Can I pick pods?**
**A:** Yes. The roster generator prompts for **pod groups** so you can build **subset** rosters (e.g., per VPN segment).

**Q: What’s the difference between *Generate Configs* and *Generate Roster*?**
**A:** Configs create the **structure and template files** Salt needs; Roster builds the **target host list** for `salt-ssh` (from CSV, with pod selection).

**Q: How do I recover from a bad cleanup?**
**A:** Each cleaner makes a tarball snapshot in `archive/snapshots/`. Restore by extracting at project root.

---

## 🧪 Sample Module Output (realistic)

```
════════════════════════════════════════════════════════════════════
▶ Clean House · Standard
Project Root: /sto/salt-shaker
════════════════════════════════════════════════════════════════════
This level:
  - Rotates logs/ → archive/snapshots/logs.<ts>/
  - Removes: tmp/ .cache/ vendor/thin/ *.bak
  - Deletes roster/runtime CSV artifacts
  - Re-creates skeleton dirs: bin/ tmp/ vendor/thin/ deployables/ runtime/
• Creating snapshot → archive/snapshots/standard-20251004095339.tar.gz
✓ Snapshot created
• Rotating logs → logs.20251004095339/
✓ logs rotated
• Remove tmp, .cache, vendor/thin, *.bak
✓ removed tmp
✓ removed .cache
✓ removed vendor/thin
✓ removed *.bak (bin/env/runtime)
✓ skeletons ready
════════════════════════════════════════════════════════════════════
✓ Standard clean complete
```

---

## 🛟 Recovery: restoring a known-good zip

```bash
# Example:
unzip -q /sto/salt-shaker-knowngood.zip -d /sto
chown -R root:root /sto/salt-shaker
find /sto/salt-shaker -type f -name "*.sh" -exec chmod +x {} +
```

---

## ❤️ Principles Recap

* Portable, offline, **predictable**
* **No symlinks**
* **No external installs**
* Safety via snapshots, confirmations, and clear output
* Designed to be **reproducible** across EL7/EL8/EL9 with legacy needs
