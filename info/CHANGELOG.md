
---

### CHANGELOG.md
```markdown
# Changelog — Salt Shaker

All notable changes to this project will be documented here.

## [Unreleased]
- Module 08 (generate-configs), 09 (state templates), 10 (exec tests), 11 (hash gen), 12 (RPM build), 13 (air-gap package)
- “suroot” elevation shim (non-`sudo`) for restricted environments

---

## [0.9.0] — 2025-09-30
### Added
- **Wrappers (bin/)**
  - `salt-ssh-el7` with `--print-env`, legacy SSH defaults, auto-cachedir
  - `salt-ssh-el8`, `salt-call-el8` onedir wrappers
  - Auto-create minimal `conf/`, `.cache/`, `roster/hosts.yml` if missing
- **Modules**
  - `01-check-dirs.sh` (renamed from `01-init-dirs.sh`) with `--fix/--fix-perms/--dry-run`
  - `03-verify-packages.sh` with `--summary`, thin backports hints
  - `04-extract-binaries.sh` v9.x: robust EL7-safe extraction; better logging, disk checks
  - `05-build-thin-el7.sh` v3.x: EL7 thin builder with optional backports detection, “missing: …” notice, wrapper install prompt
  - `06-check-vendors.sh` v5.x: greener “READY ✓” output, relaxed thin member validation, wrapper smoke checks
  - `07-remote-test.sh` v1.1: interactive wizard + `-t/-H/-u/--ask-pass/-v`, controller-local cache usage
- **Support**
  - `clean-house.sh` v2.x: empties vendor/tmp/.cache/logs (keeps dirs)
  - `ssh-debug.sh`: prints env + exact salt-ssh command for stubborn hosts
- **GitHub helpers (github/)**
  - `setup-git-ssh.sh`: keypair/config/env; `--regen-key`, `--print-config`; connectivity test
  - `status.sh`: branch/remote/commits + SSH sanity
  - `push.sh`: add-all/commit-timestamp/push; optional message
  - `download-salt-shaker.sh`: optional repo fetcher for bootstrap
  - `menu.sh`: tidy menu for setup/status/push
  - `test.sh`: chains status + dry-run push plan

### Changed
- **Path handling**: eliminated hardcoded roots; all modules auto-detect `PROJECT_ROOT`
- **Logging**: quieter console (✓/⚠/✖), detailed logs in `logs/`, consistent color palette
- **Thin check (06)**: demoted “no python2 on controller” to informational & green READY

### Fixed
- EL7 Bash compatibility (removed associative arrays, mapfile, here-strings, etc.)
- Tarball/RPM extraction edge cases; permissions and shebang normalization

### Known Issues
- Alternative elevation (`suroot` vs `sudo`) not yet built-in (planned as a shim)
- Module 08–13 are stubs/roadmapped

---

## [0.8.0] — 2025-09-28
- First working end-to-end onedir extraction + thin build + wrappers + vendor checks
- Early menus and CSV/roster utilities

---

## [0.1.0] — 2025-09-20
- Initial repository layout and scaffolding

