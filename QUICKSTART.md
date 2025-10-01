
# 🚀 Quickstart — Salt Shaker (Air-Gapped Salt-SSH for EL7/8/9)

Salt Shaker is a **portable**, **air-gapped-friendly** Salt-SSH toolkit. Controllers run from a project folder (no system installs). EL8/EL9 use **onedir** (bundled Py3.10); EL7 targets use a **thin** (Py2) client shipped over SSH.

---

## 0) Requirements (Controller)

- RHEL/Rocky **EL8/EL9 recommended** (EL7 menu also provided).
- Tools: `bash`, `tar`, `cpio`, `rpm2cpio`, `awk`, `sed`, `sha256sum`.
- Network (for building/fetching only): access to your artifact sources (or pre-stage them offline).
- Disk: ~2–3 GB free in project directory for vendor builds and cache.

---

## 1) Create the Project Skeleton

If you’re starting from an empty directory:

```bash
# Optional one-time: create empty tree where you want the project to live
./setup.sh

# Verify and (optionally) create any missing core folders + perms
./modules/01-check-dirs.sh --fix          # add --fix-perms if you want +x set
````

Project tree (high-level):

```
salt-shaker/
├── salt-shaker.sh           # EL8/EL9 menu
├── salt-shaker-el7.sh       # EL7-compatible menu
├── modules/01..07
├── offline/salt/{el7,el8,el9,tarballs,thin/el7}
├── vendor/el{7,8,9}/salt  vendor/el7/thin/
├── bin/ env/ logs/ .cache/ tmp/ roster/ file-roots/ pillar/
└── support/ scripts/ tools/ rpm/
```

> All logs/cache/tmp/vendor live **inside** the project root.

---

## 2) Stage Offline Artifacts

Place these in `offline/salt/...` (no Internet required afterward):

**Onedir tarballs (controller runtimes):**

* `offline/salt/tarballs/salt-3006.15-onedir-linux-x86_64.tar.xz` (EL8)
* `offline/salt/tarballs/salt-3007.8-onedir-linux-x86_64.tar.xz` (EL8/EL9)

**Controller RPMs (overlay files):**

* `offline/salt/el8/` : `salt-3007.8-0.x86_64.rpm`, `salt-ssh-3007.8-0.x86_64.rpm`, `salt-cloud-3007.8-0.x86_64.rpm`
* `offline/salt/el9/` : same as EL8 (3007.8)

**EL7 Thin (Py2) Core + Extras:**

* Core: `salt-2019.2.8-1.el7.noarch.rpm`, `python2-msgpack-0.5.6-5.el7.x86_64.rpm`,
  `PyYAML-3.10-11.el7.x86_64.rpm`, `python-tornado-4.2.1-5.el7.x86_64.rpm`, `six-1.16.0.tar.gz`
* Optional (recommended): `python-jinja2-2.7.2-2.el7.noarch.rpm`, `python-markupsafe-0.11-10.el7.x86_64.rpm`, `python-requests-1.1.0-8.el7.noarch.rpm`
* Py2 backports (recommended):
  `python2-futures-3.0.5-1.el7.noarch.rpm`, `python2-backports_abc-0.5-2.el7.noarch.rpm`,
  `python-singledispatch-3.4.0.2-2.el7.noarch.rpm`, `python-enum34-1.0.4-1.el7.noarch.rpm`,
  `python2-certifi-2018.10.15-5.el7.noarch.rpm`

Put all of those under: `offline/salt/thin/el7/`

---

## 3) Verify Artifacts

```bash
./modules/03-verify-packages.sh --summary
```

You should see all required items as ✓ and a brief per-platform table.
(EL7 thin extras may show as optional; recommended for compatibility.)

---

## 4) Extract Onedir Runtimes (Controller)

```bash
./modules/04-extract-binaries.sh
```

This unpacks each onedir tarball and overlays matching RPMs into:

* `vendor/el8/salt`
* `vendor/el9/salt`

---

## 5) Build EL7 Thin

```bash
./modules/05-build-thin-el7.sh
```

* Produces: `vendor/el7/thin/salt-thin.tgz` (includes salt, msgpack, yaml, tornado, six, and optional extras/backports).
* At the end it will **offer to install wrappers** (recommended).

---

## 6) Check Vendors (Green “READY ✓”)

```bash
./modules/06-check-vendors.sh
```

You should see:

* a table for `vendor/el7|el8|el9/salt` with python + salt-* versions,
* **EL7 thin present** and **archive contains `salt/`**,
* wrappers **OK** (if installed).

---

## 7) Remote Smoke Test (Salt-SSH)

```bash
# Guided wizard (prompts for platform/host/user/sudo/askpass)
./modules/07-remote-test.sh

# Or CLI example (EL7 target, password auth):
./modules/07-remote-test.sh -t el7 -H 192.0.2.25 -u admin --ask-pass -v
```

What it does:

* Creates a **temp master** and **roster** under `tmp/rt-...`
* Uses `bin/salt-ssh-el7` (EL7) or `bin/salt-ssh-el8` (EL8/EL9)
* Runs `test.ping` and `grains.item osfinger pythonversion`
* Uses project `.cache/`, and your wrappers **auto-set** environment

> No `sudo` in your environment? A **“suroot”** shim can be added later (planned).
> For now, run as a user that can run Salt-SSH commands as needed (with or without sudo).

---

## 8) Everyday Use

* **Wrappers** (already installed by step 5):

  ```bash
  ./bin/salt-ssh-el8 --print-env          # show env used by the wrapper
  ./bin/salt-ssh-el7 -c . -i target test.ping
  ```
* **Menus**:

  ```bash
  ./salt-shaker.sh         # EL8/EL9 menu
  ./salt-shaker-el7.sh     # EL7-compatible menu
  ```

---

## 9) Cleanup Between Iterations

```bash
./clean-house.sh
```

Empties: `vendor/*`, `.cache/*`, `tmp/*`, `logs/*` (keeps directories).
Great for rebuild testing without recreating the skeleton.

---

## Troubleshooting

* **EL7 thin import fails in 06**
  Rebuild thin (step 5) and ensure the **Py2 backports** are present in `offline/salt/thin/el7/`.

* **Wrappers show `no ONEDIR`**
  Ensure step 4 was successful and vendors exist under `vendor/elX/salt`.
  Re-install wrappers with `env/90-install-env-wrappers.sh`.

* **Remote test fails with password prompts**
  Add `--ask-pass` and/or pass `--ssh-args` (e.g., to disable public key auth):

  ```bash
  ./modules/07-remote-test.sh -t el8 -H 192.0.2.33 -u admin --ask-pass \
    --ssh-args "-oPreferredAuthentications=password -oPubkeyAuthentication=no"
  ```

* **Need more logging?**
  Check `logs/salt-shaker.log` and `tmp/rt-*/` test directories.

---

## Design Rules

* EL7-safe Bash (no associative arrays, `mapfile`, here-strings, etc.)
* Air-gap first; strict project-relative paths
* Idempotent modules; clean ✓/⚠/✖ console with detailed logs

---

## Support

* Maintainer: **To3Knee**
* License: MIT (or your chosen project license)

