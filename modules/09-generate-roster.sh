#!/usr/bin/env bash
#===============================================================
#Script Name: 09-generate-roster.sh
#Date: 09/22/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.0
#Short: Generate roster
#About: Creates salt-ssh roster (YAML/CSV sources supported).
#===============================================================
#!/bin/bash
# Script Name: 09-generate-roster.sh
# Date: 10/04/2025
# Created By: T03KNEE
# Github: https://github.com/To3Knee/Salt-Shaker
# Version: 1.0
# Short: Create roster YAML
# About: Builds runtime/roster/roster.yaml from CSV.
#!/bin/bash
set -euo pipefail
LC_ALL=C

ROOT="${SALT_SHAKER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
RUNTIME_DIR="${SALT_SHAKER_RUNTIME_DIR:-$ROOT/runtime}"
OUT="$RUNTIME_DIR/roster/roster.yaml"
CSV="$ROOT/roster/data/hosts_all_pods.csv"
LOG="$ROOT/logs/salt-shaker.log"

log(){ printf '%s [ROSTER] %s\n' "$(date '+%F %T')" "$1" | tee -a "$LOG" >&2; }

[ -f "$CSV" ] || { log "CSV not found: $CSV (run 02-create-csv.sh)"; exit 2; }
mkdir -p "$(dirname "$OUT")" "$ROOT/logs"

# CSV columns: pod,target,host,ip,port,user,passwd,sudo,ssh_args,description
# Emit yaml per host key (target if set else host/ip), with safe defaults.
{
  awk -F',' 'BEGIN{OFS=","}
    NR==1{
      for(i=1;i<=NF;i++){h[$i]=i}
      next
    }
    {
      pod=$h["pod"]; tgt=$h["target"]; host=$h["host"]; ip=$h["ip"]; port=$h["port"];
      user=$h["user"]; passwd=$h["passwd"]; sudo=$h["sudo"]; ssh_args=$h["ssh_args"];
      desc=$h["description"];
      key=tgt; if(key=="") key=host; if(key=="") key=ip;
      if(key=="") next;
      gsub(/^[ \t]+|[ \t]+$/,"",key);
      print key "\n" host "\n" ip "\n" port "\n" user "\n" passwd "\n" sudo "\n" ssh_args "\n" desc > "/dev/stderr";
      # emit yaml
      printf("%s:\n", key);
      if(host!="") printf("  host: %s\n", host);
      else if(ip!="") printf("  host: %s\n", ip);
      else printf("  host: %s\n", key);
      if(user!="") printf("  user: %s\n", user);
      if(port!="") printf("  port: %s\n", port); else printf("  port: 22\n");
      if(sudo!=""){ printf("  sudo: %s\n", tolower(sudo)); } else { printf("  sudo: false\n"); }
      printf("  tty: false\n");
      # do NOT store passwd; rely on --askpass
      if(ssh_args!=""){
        printf("  ssh_options:\n");
        n=split(ssh_args,a," ");
        for(i=1;i<=n;i++){ if(a[i]!="") printf("    - %s\n", a[i]); }
      } else {
        printf("  ssh_options:\n");
        printf("    - StrictHostKeyChecking=no\n");
        printf("    - UserKnownHostsFile=/dev/null\n");
      }
      if(desc!=""){ printf("  # %s\n", desc); }
    }' "$CSV" > "$OUT"
} 2>/dev/null

log "Roster written: $OUT (entries: $(grep -cE '^[^[:space:]].*:$' "$OUT" || echo 0))"
echo "$OUT"
