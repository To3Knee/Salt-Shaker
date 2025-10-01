
# Pillar How-To (Salt Shaker)

**Goal:** Safely manage secrets (e.g., hashed passwords) via Salt **Pillar** in an air-gapped, portable project. Keep secrets **out of Git**, and make states consume them cleanly.

---

## What is Pillar (and why use it)?
- **Pillar** is Salt’s *per-minion* data store (YAML). Think “private variables” for targets.
- Perfect for **secrets** (password hashes, tokens) and **env-specific** data.
- States read pillar via Jinja, e.g. `{{ pillar['users']['admin']['password'] }}`.

---

## Directory & files we use
```

salt-shaker/
├── conf/master           # Salt config (module 08 will generate)
├── pillar/
│   ├── top.sls           # Pillar mapping file (loader)
│   └── data.sls          # Secret data (local only, git-ignored)
└── file-roots/
├── top.sls           # State mapping file (what states to run)
└── users/init.sls    # Example state consuming pillar

````

---

## Keep secrets out of Git
Add to `.gitignore`:
```gitignore
# Pillar secrets (local only; never push)
pillar/data.sls
pillar/private/**
pillar/*.local.sls
````

Optional if you later ignore the entire `pillar/` dir:

```gitignore
!pillar/top.sls
```

**Am I already tracking `pillar/data.sls`?**

```bash
git ls-files pillar/data.sls      # prints nothing => not tracked
git check-ignore -v pillar/data.sls  # prints a rule => ignored
```

If it had been tracked previously:

```bash
git rm --cached pillar/data.sls
git commit -m "Stop tracking pillar/data.sls (local secret)"
```

---

## Wire the Pillar loader (`pillar/top.sls`)

Create `pillar/top.sls`:

```yaml
# pillar/top.sls
base:
  '*':
    - data
```

This tells Salt: “Load `pillar/data.sls` for all targets.”

---

## Put secrets into `pillar/data.sls`

Recommended format (our tool writes a **managed block**):

```yaml
# pillar/data.sls
# salt-shaker: managed-users begin
users:
  admin:
    password: "$6$...your-sha512-hash..."
# salt-shaker: managed-users end
```

### Generate a SHA-512 crypt hash (inside project only)

Use the tool (masked input, EL7/8/9-safe):

```bash
tools/create-password-hash.sh
# → prompts for username + password, prints the hash,
#   and can write into pillar/data.sls in a managed block.
```

---

## Use pillar from a state

Example state `file-roots/users/init.sls`:

```yaml
# file-roots/users/init.sls
admin-user:
  user.present:
    - name: admin
    - password: "{{ pillar['users']['admin']['password'] }}"
```

Map the state in `file-roots/top.sls`:

```yaml
# file-roots/top.sls
base:
  '*':
    - users
```

---

## Salt config (where pillar & file roots live)

Your `conf/master` (module 08 will generate) must include:

```yaml
# conf/master (excerpt)
file_roots:
  base:
    - salt-shaker/file-roots

pillar_roots:
  base:
    - salt-shaker/pillar
```

---

## Test and apply

List pillar data for a target:

```bash
# Using your wrapper or vendor salt-ssh:
bin/salt-ssh-el7 <target_id> pillar.items users
```

Apply the state that uses the pillar:

```bash
bin/salt-ssh-el7 <target_id> state.apply users
```

If your module 07 is set up, you can first confirm connectivity:

```bash
modules/07-remote-test.sh
```

---

## Troubleshooting

* **No pillar data**: Check `pillar/top.sls` includes `data` under the right env (`base`) and pattern (`'*'`).
* **Wrong path**: Confirm `conf/master` has correct `pillar_roots` to your project path.
* **Duplicate `users:` keys**: If you hand-edit outside the managed block, YAML can contain duplicate keys; last one wins. Prefer updating via the tool (managed block).
* **Permissions**: Keep `pillar/data.sls` as `0600` locally.
* **Debug**: Add `-l debug` to `salt-ssh` to see pillar compilation logs.

---

## FAQ

**Q:** Do controller and target OS need to match?
**A:** No. Pillar is static data. Salt-SSH deploys a thin to the target; pillar compilation happens on the controller.

**Q:** Can I have different pillar per host or group?
**A:** Yes. Use more SLS files (`- data_pod01`, `- data_db`) and smarter targeting patterns in `pillar/top.sls` (e.g., by `minion_id` or grains).

**Q:** Is `data.sls` required?
**A:** No—it’s a convention. You can split by role/env; just ensure `pillar/top.sls` maps them.

```
