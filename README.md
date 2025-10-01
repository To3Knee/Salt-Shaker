<p align="center">
  <img src="https://github.com/To3Knee/Salt-Shaker/blob/main/info/logo.png" 
       alt="Salt Shaker" 
       width="200"/>
</p>

# 🧂 Salt Shaker — Portable Salt-SSH for Air-Gapped EL7/8/9

## ❌This is Just an idea and at this point 100% not functional (yet) - You have been warned❌

[![Linux](https://img.shields.io/badge/platform-Linux-blue?logo=linux&logoColor=white)](#)
[![Bash](https://img.shields.io/badge/shell-bash-green?logo=gnu-bash&logoColor=white)](#)
[![Salt](https://img.shields.io/badge/SaltStack-portable-orange)](#)
![Air-Gapped](https://img.shields.io/badge/Air--Gapped-First-red)
![EL7/8/9](https://img.shields.io/badge/RHEL/Rocky-7%2F8%2F9-yellow)

Salt Shaker is a **self-contained Salt-SSH toolkit** designed for **air-gapped** environments.  
No system packages are installed; everything runs from the project folder.

- **EL8/EL9 controller**: “onedir” builds (bundled Python 3.10) — recommended.  
- **EL7 targets**: Python 2 **thin** client (2019.2.x) shipped over SSH.  
- **Clear, idempotent modules** with ✓/⚠/✖ output and detailed logs.  
- **EL7-safe Bash** (works on EL7/EL8/EL9).

---

## 📦 What’s inside

### Modules (`modules/`)
1. **01-check-dirs.sh** — verify/create skeleton; `--fix`, `--fix-perms`, `--dry-run`.
2. **02-create-csv.sh** — roster CSV template generator.
3. **03-verify-packages.sh** — verify offline **RPMs/tarballs** (EL7/8/9) and thin extras/backports.
4. **04-extract-binaries.sh** — unpack onedir tarballs + overlay RPMs → `vendor/elX/salt`.
5. **05-build-thin-el7.sh** — build EL7 **thin** (2019.2.8) including optional backports (futures, backports_abc, singledispatch, enum34, certifi). Offers to install wrappers when done.
6. **06-check-vendors.sh** — validates controller onedir + EL7 thin; relaxed checks; prints **READY ✓** summary.
7. **07-remote-test.sh** — friendly wizard for salt-ssh ping & grains against a target; supports password auth, sudo/TTY toggles, custom ssh args.

### Wrappers (`bin/`)
- **salt-ssh-el7** — controller onedir + EL7 thin; legacy SSH options for “fossil” EL7 servers; `--print-env`.
- **salt-ssh-el8**, **salt-call-el8** — onedir execution on EL8/EL9.

All wrappers:
- auto-detect project root,  
- force `cachedir=$PROJECT_ROOT/.cache`,  
- ensure minimal `roster/hosts.yml` and `conf/` exist,  
- never hardcode absolute paths.

> Install wrappers anytime via `env/90-install-env-wrappers.sh`
> (also offered at the end of module **05**).

### GitHub helpers (`github/`) — **dev convenience, excluded from air-gap**
- **setup-git-ssh.sh** — create ed25519 key & SSH config; `--print-config`, `--regen-key`; optional connectivity test.  
- **init-repo.sh** — set remote, first commit, and push. **No default commit message** (empty message OK).  
- **push.sh** — add-all / commit (blank or custom message) / push.  
- **status.sh** — show branch, remote, last commits + SSH check.  
- **wipe-remote-repo.sh** — interactively **soft/hard** wipe the remote `main` (with confirmations).  
- **download-salt-shaker.sh** — optional fetcher when bootstrapping elsewhere.  
- **github-menu.sh** — small menu that ties the above together.

---

## 🌳 Project tree (at a glance)

```

salt-shaker/
├─ salt-shaker.sh         salt-shaker-el7.sh
├─ modules/01..07         bin/                  env/
├─ offline/
│  └─ salt/
│     ├─ el7/ el8/ el9/   # RPMs
│     ├─ tarballs/        # onedir tarballs (e.g., 3006.15, 3007.8)
│     └─ thin/el7/        # EL7 thin deps + six/backports
├─ vendor/
│  ├─ el7/{salt,thin/}
│  ├─ el8/salt
│  └─ el9/salt
├─ roster/                file-roots/          pillar/
├─ logs/                  .cache/              tmp/
├─ support/               scripts/             tools/   rpm/
└─ github/                # dev-only helpers; not shipped to air-gap

````

All logs/cache/tmp/vendor live **inside** the project root.  
`clean-house.sh` **empties** these directories without deleting them.

---

## ⚡ Quickstart

### 0) (Optional) Create an empty skeleton anywhere
```bash
./setup.sh                      # asks destination, perms, creates tree
````

### 1) Verify & create required directories

```bash
./modules/01-check-dirs.sh --fix
```

### 2) Stage offline artifacts

Place files under `offline/`:

* **Onedir tarballs** (EL8/EL9):
  `offline/salt/tarballs/salt-3007.8-onedir-linux-x86_64.tar.xz`
  *(and 3006.15 if desired)*

* **RPMs**:
  `offline/salt/el8/` and `offline/salt/el9/` (salt, salt-ssh, salt-cloud)

* **EL7 thin deps** in `offline/salt/thin/el7/` (core + backports; see “EL7 thin backports” below)

### 3) Verify packages/tarballs

```bash
./modules/03-verify-packages.sh --summary
```

### 4) Extract controller onedir(s)

```bash
./modules/04-extract-binaries.sh
# → vendor/el8/salt and/or vendor/el9/salt
```

### 5) Build EL7 thin (Py2)

```bash
./modules/05-build-thin-el7.sh
# Includes: salt,msgpack,yaml,tornado,six,jinja2,markupsafe,requests
# Optional backports auto-detected: futures, backports_abc, singledispatch, enum34, certifi
# Offers to install wrappers (recommended)
```

### 6) Sanity check vendors

```bash
./modules/06-check-vendors.sh
# Prints a green READY ✓ summary. Relaxed thin validation (salt/... or ./salt/...).
```

### 7) Try a remote

```bash
./modules/07-remote-test.sh        # wizard prompts for platform, host, user
# or non-interactive:
./modules/07-remote-test.sh -t el8 -H 192.0.2.10 -u admin --ask-pass
```

---

## 📥 EL7 thin backports (recommended)

Drop these in `offline/salt/thin/el7/` to maximize EL7 target compatibility:

* `python2-futures-3.x-*.el7.noarch.rpm`
* `python2-backports_abc-0.5-*.el7.noarch.rpm`
* `python-singledispatch-3.4.0.*-*.el7.noarch.rpm`
* `python-enum34-1.*-*.el7.noarch.rpm`
* `python2-certifi-*.el7.noarch.rpm`

Module **05** will list any missing ones as a one-liner (e.g., “missing: futures, …”).

---

## 🧰 Wrapper tips

* `bin/salt-ssh-el7 --print-env` *(and `salt-ssh-el8`)* prints the resolved environment
  (PATH, PYTHONHOME, onedir path, cachedir).
* Wrappers auto-create:

  * `roster/hosts.yml` (minimal template if missing),
  * `conf/master` (temp), forcing:

    * `cachedir: $PROJECT_ROOT/.cache`
    * `ssh_wipe: True`
    * **EL7** only: a default `ssh_ext_alternatives` for thin mode.

---

## 🧹 Cleanup between iterations

```bash
./clean-house.sh
# Empties vendor/*, tmp/*, .cache/*, logs/* (keeps directories)
```

---

## 🔐 Security & elevation

* Password auth is supported (`--ask-pass`).
* `sudo` is supported and controllable in **07**.
* Environments without `sudo` (e.g., “suroot”) can be shimmed with a custom wrapper/roster — planned helper coming soon.

---

## 🧑‍💻 Maintainer & License

**Maintainer:** To3Knee
**License:** MIT (or project license of your choice)

---

## 🧭 Troubleshooting (quick hits)

* **06 shows “READY ✓” but wrappers warn** → run `env/90-install-env-wrappers.sh` again after rebuilding vendors.
* **EL7 thin import fails in 06** → rebuild with **05** and ensure backports exist in `offline/salt/thin/el7/`.
* **07 fails with password auth** → re-try with:

  ```
  --ssh-args "-oPreferredAuthentications=password -oPubkeyAuthentication=no"

---

### ❤️ Thanks

Huge thanks to everyone testing across EL7/8/9 and helping make this rock-solid in air-gapped environments.

```
