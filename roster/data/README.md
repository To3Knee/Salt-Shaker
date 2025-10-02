# Roster CSV format (Excel-safe)

**Filename**: `hosts-all-pods.csv` (real), example: `hosts-all-pods-example.csv` (sanitized)  
**Encoding**: UTF-8 with BOM, **CRLF** line endings (Windows/Excel friendly).  
**Naming**: use dashes, never underscores.

## Header (exact, ordered)

pod,platform,host,port,user,auth,sudo,python2_bin,ssh_args,minion_id,groups,notes


### Field guide
- **pod**: Free-form grouping label (e.g., `pod-01`).
- **platform**: One of `el7`, `el8`, `el9`. Drives thin/onedir behavior.
- **host**: Hostname or IP of target.
- **port**: SSH port (1–65535). Usually `22`.
- **user**: SSH login user (e.g., `root`, `ec2-user`).
- **auth**: `askpass` (prompt at run time) or `none`.  
  *Note*: A future module can optionally accept a `passwd` column for **non-interactive** runs; do **not** commit real passwords.
- **sudo**: `y` or `n`. If `y`, we enable `tty: True` and prompt/password as needed.
- **python2_bin**: EL7 only (e.g., `/usr/bin/python`). Leave blank for EL8/EL9.
- **ssh_args**: Extra OpenSSH options (quoted if spaces), e.g.  
  `-J jump@bastion` or `-o KexAlgorithms=+diffie-hellman-group14-sha1`
- **minion_id**: Optional stable Salt ID (e.g., `minion-el8-01`). Defaults to host if blank.
- **groups**: Comma-separated labels for targeting (quote if containing commas), e.g., `"linux,legacy"`.
- **notes**: Free text.

## Example rows

pod-01,el7,10.0.0.7,22,root,askpass,y,/usr/bin/python,,"minion-el7-01","linux,legacy","example el7 target"
pod-01,el8,10.0.0.8,22,root,askpass,y,,,"minion-el8-01","linux","example el8 target"
pod-02,el9,10.0.0.9,22,root,askpass,y,,,"minion-el9-01","linux","example el9 target"


## Excel tips
- Keep the first row as the header **exactly** as shown.
- Quote fields that contain commas (e.g., `groups`).
- Avoid trailing spaces; keep `port` numeric.

## Security
- Do **not** store secrets in Git. Real CSVs are git-ignored.
- If you later add a `passwd` column for non-interactive runs, keep it out of Git and prefer temp rosters.

