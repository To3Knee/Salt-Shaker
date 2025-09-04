

<p align="center">
  <img src="https://raw.githubusercontent.com/To3Knee/Salt-Shaker/main/salt-shaker/assets/shlogo.jpg" 
       alt="Salt Shaker" 
       width="150"/>
</p>


# 🧂 Salt Shaker — Portable Salt-SSH

[![Linux](https://img.shields.io/badge/platform-Linux-blue?logo=linux&logoColor=white)](#)
[![Bash](https://img.shields.io/badge/shell-bash-green?logo=gnu-bash&logoColor=white)](#)
[![Salt](https://img.shields.io/badge/SaltStack-portable-orange?logo=saltstack&logoColor=white)](#)
![Air-Gapped](https://img.shields.io/badge/Air--Gapped-Supported-red)
![RHEL/CentOS](https://img.shields.io/badge/RHEL/CentOS-6+-yellow)

> 🚀 **Salt Shaker** is a portable, air-gapped **Salt-SSH** wrapper for **RHEL/CentOS**.  
> - No Minions 🧙  
> - No Internet 🌐❌  
> - No Extra Packages 📦❌  
> - Password Auth 🔑 (no SSH keys required)  
> - Built for repeatability, clarity, and safe operations 🛡️  

---

## 📂 Default Project Structure

```text
salt-shaker/                 <-- project root
├── salt-shaker.sh           <-- main wrapper script
├── salt-ssh-config/         <-- config (contains master)
│    └── master
├── roster                   <-- target hosts
├── file-roots/              <-- states (SLS)
│    ├── top.sls
│    ├── init.sls
│    └── templates/          <-- intuitive templates
│         ├── restart-host.sls
│         ├── reset-password.sls
│         ├── install-package.sls
│         ├── service-manage.sls
│         ├── run-command.sls
│         └── combo-task.sls
├── pillar/                  <-- pillar data
│    ├── top.sls
│    └── data.sls
├── .cache/                  <-- local cache
├── vendor/                  <-- portable salt-ssh binary
│    └── salt/bin/salt-ssh
├── tools/                   <-- packaging helpers
│    ├── build-tar.sh
│    └── build-rpm.sh
├── SPECS/                   <-- RPM spec files
│    └── salt-shaker.spec
└── logs/                    <-- runtime logs
     ├── salt-shaker.log
     └── salt-ssh-transport.log
```

---

## ✨ Features

- 📦 **Portable**: self-contained project tree  
- 🔒 **Air-gapped ready**: no internet needed  
- 🔑 **Password auth**: no SSH keys required  
- 🧩 **Copy-and-edit templates**: reboot, package install, service management, etc.  
- 🧪 **Dry-run mode**: safe previews with `-t` or `SSKR_TEST=1`  
- 📝 **Human-readable logs**: auto-placed in `/home/*`, `/srv/tmp/*`, or `logs/`  
- 📦 **Packaging tools**: build tarball or RPM for transport  

---

## 🚀 Quick Start

```bash
# 1. initialize once (creates config/roster/states/pillar if missing)
./salt-shaker.sh init

# 2. verify your environment
./salt-shaker.sh check

# 3. dry-run a template (safe)
./salt-shaker.sh -t state '*' templates.install-package

# 4. apply for real
./salt-shaker.sh state 'web*' templates.service-manage

# 5. run an ad-hoc command
./salt-shaker.sh cmd db1 "cat /etc/redhat-release"

# 6. package for transport
./salt-shaker.sh build-tar
./salt-shaker.sh build-rpm
```

---

## ⚙️ Templates (Intuitive & Self-Contained)

Each template has a **CONFIG BLOCK** at the top and works out-of-the-box.

- 🔄 `restart-host.sls` — reboot safely  
- 🔐 `reset-password.sls` — reset local user password (SHA-512 hash)  
- 📦 `install-package.sls` — install one or more RPMs  
- 🛠️ `service-manage.sls` — enable/disable and start/stop a service  
- 💻 `run-command.sls` — run an arbitrary command  
- 🔗 `combo-task.sls` — combine multiple states into one  

**Example:** install packages

```yaml
{% set PACKAGES = salt['pillar.get']('templates:pkg:names', ['vim-enhanced']) %}
install_selected_packages:
  pkg.installed:
    - pkgs: {{ PACKAGES }}
    - failhard: True
```

Run with:

```bash
./salt-shaker.sh -t state '*' templates.install-package
```

---

## 🔧 Configuration

Open **`salt-shaker.sh`** and look for:

```
BEGIN: EDIT HERE (Safe Defaults)
```

That block controls:

- 📂 `PROJECT_DIR` → root of the project  
- 📂 directory names (`config`, `states`, `pillars`, etc.)  
- 🧾 `VENDOR_SALT_SSH_PATH` → bundled salt-ssh binary  
- ⚡ behavior toggles: password prompt, host key check, dry-run default  

**Override without editing** (one-time):

```bash
PROJECT_DIR="/srv/tmp/salt-shaker" FILE_ROOTS_NAME="states" ./salt-shaker.sh check
```

---

## 📝 Logging

- If run from `/home/*` or `/srv/tmp/*` → logs go **right there**  
- Otherwise → logs go to `PROJECT_DIR/logs`  
- Override with `-L`:

```bash
./salt-shaker.sh -L /srv/tmp/logs check
```

---

## 🧪 Dry-Run Mode

Preview changes without applying:

```bash
./salt-shaker.sh -t state '*' templates.service-manage
```

or:

```bash
SSKR_TEST=1 ./salt-shaker.sh state db1 templates.combo-task
```

---

## 📜 Roster Example

```yaml
web1:
  host: 192.0.2.10
  user: root
  tty: True
  sudo: False

db1:
  host: 192.0.2.20
  user: root
  tty: True
  sudo: False
```

🔑 Passwords: prompted by default (`--askpass`).  
💡 You can hardcode `passwd: "..."` in the roster, but avoid for security reasons.

---

## 📦 Packaging

**Tarball (portable):**
```bash
./tools/build-tar.sh
```

**RPM (noarch, if rpmbuild exists):**
```bash
./tools/build-rpm.sh
```

---

## 🔐 Security Notes

- ✅ Prefer interactive passwords  
- ❌ Avoid storing passwords in the roster  
- 🧾 Always review states before running against prod systems  

---

## 🛠️ Roadmap

- [ ] Add more templates (cron, sysctl, file management)  
- [ ] Add `readme` subcommand (`./salt-shaker.sh readme`)  
- [ ] Enhance packaging (auto-versioned RPMs)  

---

## 📖 Changelog

- **0.2.2**
  - Added colorful, intuitive README.md (this file 🎉)  
  - Clear “Edit Here” block in script with default tree diagram  
  - Logs auto-placed based on run dir  
  - Dry-run support (-t / SSKR_TEST=1)  
  - Self-contained templates with dash-style names  
  - Packaging tools (tar, rpm)  

---

## 💬 FAQ

**Q:** Do targets need Salt installed?  
**A:** No. Salt-SSH ships a thin payload over SSH.

**Q:** Can I run anywhere?  
**A:** Yes. Logs follow your run directory if in `/home` or `/srv/tmp`.

**Q:** Keys or passwords?  
**A:** Passwords by default. Keys possible, but not the project scope.

---

## 👥 Maintainers

- ToeKnee
