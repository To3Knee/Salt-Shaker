#!/usr/bin/env bash
#===============================================================
#Script Name: 02-create-csv.sh
#Date: 09/22/2025
#Created By: T03KNEE
#Github: https://github.com/To3Knee/Salt-Shaker
#Version: 1.0
#Short: Generate package CSV
#About: Builds CSV inputs for offline processing and audits.
#===============================================================
#!/bin/bash
# Script Name: 02-create-csv.sh
# Date: 10/04/2025
# Created By: T03KNEE
# Github: https://github.com/To3Knee/Salt-Shaker
# Version: 1.0
# Short: Create/seed CSV
# About: Seeds/updates inventory CSV used to generate roster/configs.
#!/bin/bash

set -euo pipefail
LC_ALL=C

usage(){ cat <<'HLP'
Usage:
  02-create-csv.sh            # write template if missing
  02-create-csv.sh --lint     # validate CSV and suggest fixes
  02-create-csv.sh --autofix  # strip BOM/CRLF in-place (writes .bak)
HLP
}
about(){ awk 'NR==1,/#===/{print}' "$0"; }

EXPECTED="pod,target,host,ip,port,user,passwd,sudo,ssh_args,description"

SELF="${BASH_SOURCE[0]:-$0}"
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
CSV_DIR="$ROOT/roster/data"
CSV_FILE="$CSV_DIR/hosts_all_pods.csv"
LOG="$ROOT/logs/salt-shaker.log"
mkdir -p "$CSV_DIR" "$(dirname "$LOG")"

ts(){ date '+%F %T'; }
log(){ printf '%s [%s] %s\n' "$(ts)" "$1" "$2" | tee -a "$LOG"; }

write_template(){
  if [ -f "$CSV_FILE" ]; then
    log INFO "CSV exists: $CSV_FILE"
    return 0
  fi
  cat > "$CSV_FILE" <<CSV
$EXPECTED
core,web01,web01.example,192.168.1.10,22,root,,false,"StrictHostKeyChecking=no UserKnownHostsFile=/dev/null","Sample web node"
core,db01,db01.example,192.168.1.11,22,root,,false,"StrictHostKeyChecking=no UserKnownHostsFile=/dev/null","Sample db node"
CSV
  log INFO "Template written: $CSV_FILE"
}

detect_bom_crlf(){
  local fb; fb="$(head -c3 "$CSV_FILE" | od -An -t x1 | tr -d ' \n')"
  HAS_BOM=0; [ "$fb" = "efbbbf" ] && HAS_BOM=1
  if grep -q $'\r' "$CSV_FILE"; then HAS_CRLF=1; else HAS_CRLF=0; fi
}

lint_csv(){
  [ -f "$CSV_FILE" ] || { echo "CSV not found: $CSV_FILE"; exit 2; }

  detect_bom_crlf

  hdr="$(head -n1 "$CSV_FILE" | sed 's/\r$//')"
  if [ "$hdr" != "$EXPECTED" ]; then
    echo "ERR: Header mismatch"
    echo "Expected: $EXPECTED"
    echo "Found   : $hdr"
    bad_header=1
  else
    bad_header=0
  fi

  awk '
    BEGIN{FS=","; total=0; empty=0; dupes=0; badargs=0}
    NR==1{next}
    {
      total++
      tgt=$2; host=$3; ip=$4; port=$5; user=$6; ssh_args=$9
      gsub(/^"/,"",tgt); gsub(/"$/,"",tgt)
      gsub(/^"/,"",host); gsub(/"$/,"",host)
      gsub(/^"/,"",ip); gsub(/"$/,"",ip)
      gsub(/^"/,"",port); gsub(/"$/,"",port)
      gsub(/^"/,"",user); gsub(/"$/,"",user)
      gsub(/^"/,"",ssh_args); gsub(/"$/,"",ssh_args)
      key=tgt; if(key==""){ if(host!="") key=host; else key=ip }
      if (key=="") empty++
      if (user=="" || port=="" || port=="0") empty++
      if (ssh_args ~ /(^|[[:space:]])-o[[:space:]]/) badargs++
      if (seen[key]++==1) dupes++
    }
    END{printf("SUMMARY total=%d empty=%d dupes=%d bad_args=%d\n", total, empty, dupes, badargs)}
  ' "$CSV_FILE" > "$ROOT/tmp/csv_lint_summary.txt"
  read -r SUM < "$ROOT/tmp/csv_lint_summary.txt"
  echo "$SUM"

  if [ ${HAS_BOM:-0} -eq 1 ] || [ ${HAS_CRLF:-0} -eq 1 ]; then
    echo "Detected: $( [ ${HAS_BOM:-0} -eq 1 ] && echo -n 'BOM ' )$( [ ${HAS_CRLF:-0} -eq 1 ] && echo 'CRLF' )"
  fi

  ec=0
  [ ${bad_header:-0} -ne 0 ] && ec=2
  nums="$(echo "$SUM" | sed 's/[^0-9 ]//g')"
  set -- $nums # total empty dupes bad_args
  if [ "${2:-0}" -gt 0 ] || [ "${3:-0}" -gt 0 ] || [ "${4:-0}" -gt 0 ]; then ec=2; fi
  exit $ec
}

autofix_csv(){
  [ -f "$CSV_FILE" ] || { echo "CSV not found: $CSV_FILE"; exit 2; }
  detect_bom_crlf
  cp -p "$CSV_FILE" "$CSV_FILE.bak"
  tmp="$CSV_FILE.tmp"
  if [ ${HAS_BOM:-0} -eq 1 ]; then tail -c +4 "$CSV_FILE" > "$tmp"; else cp "$CSV_FILE" "$tmp"; fi
  tr -d '\r' < "$tmp" > "$CSV_FILE"
  rm -f "$tmp"
  echo "Autofixed in-place: stripped $( [ ${HAS_BOM:-0} -eq 1 ] && echo -n 'BOM ' )$( [ ${HAS_CRLF:-0} -eq 1 ] && echo 'CRLF' )"
  echo "Backup: $CSV_FILE.bak"
}

case "${1:-}" in
  -h|--help) usage; exit 0;;
  -a|--about) about; exit 0;;
  --lint) lint_csv ;;
  --autofix) autofix_csv ;;
  *) write_template ;;
esac
