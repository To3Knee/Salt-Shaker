
<p align="center">
  <img src="https://github.com/To3Knee/Salt-Shaker/blob/main/info/logo.png" 
       alt="Salt Shaker" 
       width="200"/>


# <p align="center">🧂 Salt Shaker — Portable Salt-SSH /> 🧂

## ❌This is Just an idea and at this point 100% not functional (yet) - You have been warned❌

[![Linux](https://img.shields.io/badge/platform-Linux-blue?logo=linux&logoColor=white)](#)
[![Bash](https://img.shields.io/badge/shell-bash-green?logo=gnu-bash&logoColor=white)](#)
[![Salt](https://img.shields.io/badge/SaltStack-portable-orange?logo=saltproject&logoColor=white)](#)
![Air-Gapped](https://img.shields.io/badge/Air--Gapped-First-red)
![RHEL/Rocky](https://img.shields.io/badge/EL7%2F8%2F9-Supported-yellow)

**Salt Shaker** is a 100% portable **Salt-SSH** toolkit for air-gapped **RHEL/CentOS/Rocky**.
It never installs system packages on controllers or targets—everything runs from a self-contained project folder.

- EL7 targets use a Python-2 **thin** (2019.2.x).
- EL8/EL9 use **onedir** builds (bundled Python 3.10).
- Clean logs, idempotent modules, friendly menus, and EL7-safe Bash.

---

## 🚀 Menus (interactive)

Salt Shaker ships with TUI-style launchers that wrap modules **01–07** with ✓/⚠/✖ feedback and logging.

**On EL8/EL9 controllers (recommended):**
```bash
./salt-shaker.sh
````

**On EL7 controllers (legacy/compatible):**

```bash
./salt-shaker-el7.sh
```

### EL8 / EL9 Menu Example

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                     S A L T • S H A K E R v1.11                             ║
║     Portable SaltStack Automation for Air-Gapped Environments               ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ Project: /sto/salt-shaker │ OS: Rocky Linux release 8.10 │ Modules: 8       ║
╚══════════════════════════════════════════════════════════════════════════════╝

┌─ Salt Shaker Menu ──────────────────────────────────────────────────────┐
│
│ 1. check-dirs           - Verify project directory skeleton
│ 2. create-csv           - Create-csv module
│ 3. verify-packages      - Verify Salt RPMs and onedir tarballs
│ 4. extract-binaries     - Extract onedir + overlay RPMs to vendor
│ 5. build-thin-el7       - Build EL7 Python2 salt-ssh thin (2019.2....)
│ 6. check-vendors        - Check vendor onedirs (el7/el8/el9) + EL7...
│ 7. remote-test          - Wizard/CLI remote smoke test via salt-ssh
│ 8. generate-configs     - Generate sample Salt configurations
│
└─ Options: [Q]uit  [N]ext  [P]rev  [R]efresh  [H]elp
   Page 0/1  (8 modules loaded)

Select option (number/Q/N/P/R/H):
```

### EL7 Menu Example

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                         S A L T • S H A K E R v8.10                          ║
╠══════════════════════════════════════════════════════════════════════════════╣
║          Portable SaltStack Automation for Air-Gapped Environments           ║
║                      Rocky Linux 8.10 • Green Obsidian                       ║
╠══════════════════════════════════════════════════════════════════════════════╣
║   1)       check dirs                                                        ║
║   2)       create csv                                                        ║
║   3)       verify packages                                                   ║
║   4)       extract binaries                                                  ║
║   5)       build thin el7                                                    ║
║   6)       check vendors                                                     ║
║   7)       remote test                                                       ║
║   8)       generate configs                                                  ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  [1-8] Select • [N] Next • [P] Prev • [R] Refresh • [H] Help • [Q] Quit      ║
╚══════════════════════════════════════════════════════════════════════════════╝
Select [1-8 / N / P / R / H / Q]:
```

Both menus:

* auto-detect `PROJECT_ROOT` (no hardcoded paths),
* show module descriptions before running,
* keep all artifacts under the project tree,
* return clear exit statuses and write to `logs/salt-shaker.log`.

---

## 📦 Modules

* `01-check-dirs.sh` – verify/create project skeleton; `--fix`, `--dry-run`, `--fix-perms`
* `02-create-csv.sh` – roster CSV template generator
* `03-verify-packages.sh` – verify RPMs/tarballs for EL7/8/9 + thin extras/backports
* `04-extract-binaries.sh` – extract onedir tarballs + overlay RPMs → `vendor/elX/salt`
* `05-build-thin-el7.sh` – build **EL7 Py2 thin** (2019.2.x) with optional backports; offers wrapper install
* `06-check-vendors.sh` – controller onedir + thin validation (relaxed, green “READY ✓”)
* `07-remote-test.sh` – guided Salt-SSH ping/grains to a host (password or key auth)

---

## 🧰 Wrappers (`bin/`)

* `salt-ssh-el7` – controller onedir + ships EL7 thin; legacy SSH tunings; `--print-env`
* `salt-ssh-el8`, `salt-call-el8` – onedir execution for EL8/EL9

All wrappers:

* auto-create minimal `conf/`, `.cache/`, and `roster/hosts.yml`
* force `cachedir=${PROJECT_ROOT}/.cache`
* path-agnostic (no hardcoded roots)
* optional `--print-env` for quick troubleshooting

---

## 🌳 Project Tree

```
salt-shaker/
├── salt-shaker.sh         # EL8/EL9 menu
├── salt-shaker-el7.sh     # EL7-compatible menu
├── modules/01..07         # build/test modules
├── bin/                   # wrappers
├── offline/
│   └── salt/
│       ├── el7/ el8/ el9/     # RPMs
│       ├── tarballs/          # onedir tarballs (3006/3007)
│       └── thin/el7/          # EL7 thin deps + six (+ optional backports)
├── vendor/
│   ├── el7/{salt,thin/}
│   ├── el8/salt
│   └── el9/salt
├── roster/ file-roots/ pillar/
├── logs/ .cache/ tmp/
├── support/ scripts/ tools/ rpm/
└── github/                # dev helpers; excluded from air-gap builds
```

All logs/cache/tmp/vendor live **inside** the project root.
`clean-house.sh` empties those directories without deleting them.

---

## 🧭 Build Flow (short)

1. **Skeleton**

   ```bash
   ./setup.sh                 # optional (create empty tree anywhere)
   ./modules/01-check-dirs.sh --fix
   ```

2. **Stage artifacts under `offline/salt/…`**

   * Onedir tarballs: `salt-3006.15-onedir-…`, `salt-3007.8-onedir-…`
   * RPMs for el7/el8/el9 (`salt`, `salt-ssh`, `salt-cloud`)
   * EL7 thin deps in `offline/salt/thin/el7/` (core + optional backports)

3. **Verify**

   ```bash
   ./modules/03-verify-packages.sh --summary
   ```

4. **Extract onedir**

   ```bash
   ./modules/04-extract-binaries.sh
   ```

5. **Build EL7 thin**

   ```bash
   ./modules/05-build-thin-el7.sh
   # creates vendor/el7/thin/salt-thin.tgz and can auto-install wrappers
   ```

6. **Check vendors**

   ```bash
   ./modules/06-check-vendors.sh
   # shows green READY ✓; relaxed thin check (accepts salt/... or ./salt/…)
   ```

7. **Remote test**

   ```bash
   ./modules/07-remote-test.sh
   # wizard: target platform/host/user, --ask-pass if needed
   ```

---

## 🔐 SSH & Elevation

* Username/password (`--askpass`) and key auth supported.
* `sudo` by default; non-sudo **“suroot”** environments can be shimmed (planned add-on).
* Wrappers include legacy KEX/HostKey options for EL7 “fossil” SSH.

---

## 🧹 Cleanup Between Iterations

```bash
./clean-house.sh
```

Empties `vendor/*`, `tmp/*`, `.cache/*`, `logs/*` — preserves directories.

---


## 📄 Docs

* `QUICKSTART.md` – step-by-step build/run
* `CHANGELOG.md` – notable changes per version

---

## 🛡️ Design Rules

* EL7-safe Bash (no associative arrays, `mapfile`, here-strings, etc.)
* Air-gap first; strict project-relative paths
* Idempotent modules; clear ✓/⚠/✖ console with detailed logs

---

## 🧑‍💻 Maintainer & License

* Maintainer: **To3Knee**
* © 2025 Salt Shaker contributors 
