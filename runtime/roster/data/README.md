# Roster CSV (hosts-all-pods.csv)

Header (exact, comma-separated):
pod,platform,host,port,user,auth,sudo,python2_bin,ssh_args,minion_id,groups,notes

- pod: logical project/pod name grouping hosts (e.g., pod-01)
- platform: el7|el8|el9 (drives wrapper choice / thin use on EL7)
- host: SSH target (hostname or user@host if you prefer)
- port: SSH port (usually 22)
- user: SSH username
- auth: authentication: password (prompted at run-time) or hash
- sudo: yes|no — whether salt-ssh should sudo on target
- python2_bin: path to python2 on EL7 targets if needed (e.g., /usr/bin/python2)
- ssh_args: additional ssh options (quoted), e.g. "-o StrictHostKeyChecking=no"
- minion_id: explicit Salt minion_id to enforce (recommended)
- groups: semicolon-separated groups/tags (e.g., ops;db)
- notes: free text



Tips:
- If Excel adds a UTF-8 BOM, Module 09 will warn. To fix, run:
  ./modules/02-create-csv.sh --repair-bom
- For large fleets, keep everything in this single CSV. Module 09 filters by pod.
