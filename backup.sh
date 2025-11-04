#!/usr/bin/env bash
# backup.sh - Automated backup system with retention, checksum, verification, logging, dry-run, lockfile, restore & list.
# Usage:
#   ./backup.sh [--dry-run] /path/to/source
#   ./backup.sh --list
#   ./backup.sh --restore backup-YYYY-MM-DD-HHMM.tar.gz --to /path/to/restore
#
# Place a backup.config file next to this script (example provided). If missing, sensible defaults used.

############# Helpers & Defaults #############
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/backup.config"

# Defaults
: "${BACKUP_DESTINATION:="$HOME/backups"}"
: "${EXCLUDE_PATTERNS:=".git,node_modules,.cache"}"
: "${DAILY_KEEP:=7}"
: "${WEEKLY_KEEP:=4}"
: "${MONTHLY_KEEP:=3}"
: "${CHECKSUM_ALGO:="sha256"}"
: "${NOTIFY_EMAIL:=""}"
: "${LOG_FILE:="backup.log"}"

# Load config if present
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

# Resolve and create destination
mkdir -p "$BACKUP_DESTINATION" 2>/dev/null || {
  echo "Error: Cannot create backup destination $BACKUP_DESTINATION" >&2
  exit 1
}
LOG_PATH="$BACKUP_DESTINATION/$LOG_FILE"

# Logging function
log() {
  local level="$1"; shift
  local msg="$*"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "[$ts] $level: $msg" | tee -a "$LOG_PATH"
}

# Dry-run flag
DRY_RUN=0

# Lockfile
LOCKFILE="/tmp/backup.lock"

# Trap cleanup
cleanup_and_exit() {
  local code=$1
  if [[ -f "$LOCKFILE" ]]; then
    local ownerpid
    ownerpid="$(cat "$LOCKFILE" 2>/dev/null || echo "")"
    # only remove if file belongs to this PID
    if [[ "$ownerpid" == "$$" ]]; then
      rm -f "$LOCKFILE"
    fi
  fi
  exit "$code"
}
trap 'log "INFO" "Interrupted"; cleanup_and_exit 2' INT TERM

############# Utility functions #############
# Check that a command exists
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { log "ERROR" "Required command '$1' not found"; exit 1; }
}

# Pick checksum program
checksum_cmd() {
  if [[ "$CHECKSUM_ALGO" == "sha256" ]]; then
    if command -v sha256sum >/dev/null 2>&1; then
      echo "sha256sum"
      return
    fi
  fi
  if command -v md5sum >/dev/null 2>&1; then
    echo "md5sum"
    return
  fi
  # macOS compatibility
  if command -v shasum >/dev/null 2>&1; then
    echo "shasum -a 256"
    return
  fi
  log "ERROR" "No checksum tool available (sha256sum, md5sum or shasum required)"
  exit 1
}

# Create tar exclude args from comma separated list
make_exclude_args() {
  local list="$1"
  IFS=',' read -ra parts <<< "$list"
  local args=()
  for p in "${parts[@]}"; do
    p="$(echo "$p" | xargs)"  # trim
    [[ -z "$p" ]] && continue
    args+=(--exclude="$p")
  done
  echo "${args[@]}"
}

# Human readable filesize
hr_size() {
  local file="$1"
  if [[ -f "$file" ]]; then
    # Use stat or du depending on platform
    if stat --version >/dev/null 2>&1; then
      stat -c%s "$file"
    else
      # macOS stat
      stat -f%z "$file"
    fi
  else
    echo 0
  fi
}

# Send (simulate) email by appending to email.txt inside BACKUP_DESTINATION
send_email() {
  local subject="$1"; shift
  local body="$*"
  local mailfile="$BACKUP_DESTINATION/email.txt"
  echo "To: $NOTIFY_EMAIL" >>"$mailfile"
  echo "Subject: $subject" >>"$mailfile"
  echo "Date: $(date -R)" >>"$mailfile"
  echo "" >>"$mailfile"
  echo "$body" >>"$mailfile"
  echo "-----" >>"$mailfile"
}

############# Parse args #############
if [[ $# -eq 0 ]]; then
  echo "Usage: $0 [--dry-run] /path/to/source"
  echo "       $0 --list"
  echo "       $0 --restore BACKUPFILE --to /path/to/restore"
  exit 1
fi

MODE="backup"
SRC=""
RESTORE_FILE=""
RESTORE_TO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --list) MODE="list"; shift ;;
    --restore) MODE="restore"; shift; RESTORE_FILE="$1"; shift ;;
    --to) RESTORE_TO="$2"; shift 2 ;;
    --help|-h) echo "Usage: $0 [--dry-run] /path/to/source"; exit 0 ;;
    *) 
      # If not flag and mode still backup, treat as source path
      if [[ "$MODE" == "backup" && -z "$SRC" ]]; then
        SRC="$1"; shift
      else
        echo "Unknown argument: $1" >&2; exit 1
      fi
      ;;
  esac
done

############# LIST MODE #############
list_backups() {
  shopt -s nullglob
  echo "Available backups in $BACKUP_DESTINATION:"
  printf "%-30s %-12s %-10s %s\n" "FILENAME" "DATE" "SIZE" "CHECKSUM"
  for f in "$BACKUP_DESTINATION"/backup-*.tar.gz; do
    fname="$(basename "$f")"
    # date part from filename
    datepart="${fname#backup-}"; datepart="${datepart%.tar.gz}"
    size=$(hr_size "$f")
    checksum_file="$f.md5"
    cs=""
    if [[ -f "$checksum_file" ]]; then
      cs="$(cut -d' ' -f1 "$checksum_file")"
    fi
    printf "%-30s %-12s %-10s %s\n" "$fname" "$datepart" "$size" "$cs"
  done
  shopt -u nullglob
}

if [[ "$MODE" == "list" ]]; then
  list_backups
  exit 0
fi

############# RESTORE MODE #############
if [[ "$MODE" == "restore" ]]; then
  if [[ -z "$RESTORE_FILE" || -z "$RESTORE_TO" ]]; then
    echo "Usage: $0 --restore BACKUPFILE --to /path/to/restore"
    exit 1
  fi
  archive="$RESTORE_FILE"
  # If not absolute, look in BACKUP_DESTINATION
  if [[ ! -f "$archive" ]]; then
    if [[ -f "$BACKUP_DESTINATION/$archive" ]]; then
      archive="$BACKUP_DESTINATION/$archive"
    else
      log "ERROR" "Restore file not found: $RESTORE_FILE"
      exit 1
    fi
  fi
  mkdir -p "$RESTORE_TO" || { log "ERROR" "Cannot create restore directory $RESTORE_TO"; exit 1; }
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "Would restore $archive to $RESTORE_TO"
    exit 0
  fi
  log "INFO" "Restoring $archive to $RESTORE_TO"
  tar -xzf "$archive" -C "$RESTORE_TO"
  if [[ $? -eq 0 ]]; then
    log "SUCCESS" "Restored $archive to $RESTORE_TO"
    [[ -n "$NOTIFY_EMAIL" ]] && send_email "Restore success: $(basename "$archive")" "Restore completed to $RESTORE_TO"
    exit 0
  else
    log "ERROR" "Restore failed for $archive"
    [[ -n "$NOTIFY_EMAIL" ]] && send_email "Restore failed: $(basename "$archive")" "Restore failed for $archive"
    exit 1
  fi
fi

############# BACKUP MODE #############
# Basic checks
if [[ -z "$SRC" ]]; then
  echo "Error: Source folder not provided"
  exit 1
fi
if [[ ! -e "$SRC" ]]; then
  echo "Error: Source folder not found"
  exit 1
fi
if [[ ! -r "$SRC" ]]; then
  echo "Error: Cannot read folder, permission denied"
  exit 1
fi

# Prevent multiple runs
if [[ -f "$LOCKFILE" ]]; then
  existing_pid="$(cat "$LOCKFILE" 2>/dev/null || echo "")"
  if [[ -n "$existing_pid" ]] && ps -p "$existing_pid" >/dev/null 2>&1; then
    log "ERROR" "Another backup appears to be running (PID $existing_pid). Exiting."
    exit 1
  else
    # Stale lock
    rm -f "$LOCKFILE"
  fi
fi

echo "$$" > "$LOCKFILE"

# Will clean lockfile on exit
trap 'cleanup_and_exit $?' EXIT

# Compose filename
TIMESTAMP="$(date '+%Y-%m-%d-%H%M')"
ARCHIVE_NAME="backup-${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="$BACKUP_DESTINATION/$ARCHIVE_NAME"
CHECKSUM_FILE="$ARCHIVE_PATH.md5"

EXCLUDE_ARGS=()
read -r -a EXCLUDE_ARGS <<< "$(make_exclude_args "$EXCLUDE_PATTERNS")"

# Space check: estimate source size and require free space at dest
# Estimate source size in bytes
if command -v du >/dev/null 2>&1; then
  SRC_BYTES=$(du -sb "$SRC" 2>/dev/null | awk '{print $1}') || SRC_BYTES=0
else
  SRC_BYTES=0
fi

# Free bytes at destination
# Use df --output=avail -B1
if df --version >/dev/null 2>&1; then
  FREE_BYTES=$(df --output=avail -B1 "$BACKUP_DESTINATION" 2>/dev/null | tail -1 | tr -d ' ')
else
  # macOS fallback: df -k and convert
  FREE_KB=$(df -k "$BACKUP_DESTINATION" 2>/dev/null | awk 'NR==2{print $4}')
  FREE_BYTES=$((FREE_KB * 1024))
fi

# If we couldn't compute, skip check
if [[ -n "$SRC_BYTES" && -n "$FREE_BYTES" && "$SRC_BYTES" -gt 0 ]]; then
  # require at least SRC_BYTES + 10% slack
  REQUIRED=$((SRC_BYTES + SRC_BYTES/10 + 1024*1024)) # +1MB extra
  if [[ "$FREE_BYTES" -lt "$REQUIRED" ]]; then
    log "ERROR" "Not enough disk space for backup. Required approx $REQUIRED bytes, available $FREE_BYTES bytes"
    cleanup_and_exit 1
  fi
fi

# Build tar command
TAR_CMD=(tar -czf "$ARCHIVE_PATH")
for a in "${EXCLUDE_ARGS[@]}"; do TAR_CMD+=("$a"); done
TAR_CMD+=(-C "$(dirname "$SRC")" "$(basename "$SRC")")

# Dry-run check
if [[ $DRY_RUN -eq 1 ]]; then
  log "INFO" "DRY RUN: Would start backup of $SRC to $ARCHIVE_PATH"
  log "INFO" "DRY RUN: Would run: ${TAR_CMD[*]}"
  log "INFO" "DRY RUN: Would create checksum file: $CHECKSUM_FILE"
else
  log "INFO" "Starting backup of $SRC"
  # Create archive
  if ! "${TAR_CMD[@]}"; then
    log "ERROR" "Failed to create archive $ARCHIVE_PATH"
    cleanup_and_exit 1
  fi
  log "SUCCESS" "Backup created: $(basename "$ARCHIVE_PATH")"
fi

# Compute checksum
CHKSUM_TOOL="$(checksum_cmd)"
if [[ $DRY_RUN -eq 1 ]]; then
  log "INFO" "DRY RUN: Would compute checksum with $CHKSUM_TOOL"
else
  # compute and write checksum file
  if [[ "$CHKSUM_TOOL" == "sha256sum" || "$CHKSUM_TOOL" == "md5sum" ]]; then
    $CHKSUM_TOOL "$ARCHIVE_PATH" > "$CHECKSUM_FILE"
  else
    # shasum -a 256 returns "digest  filename"; make same format
    if [[ "$CHKSUM_TOOL" == "shasum -a 256" ]]; then
      shasum -a 256 "$ARCHIVE_PATH" > "$CHECKSUM_FILE"
    fi
  fi
  if [[ $? -eq 0 ]]; then
    log "SUCCESS" "Checksum created: $(basename "$CHECKSUM_FILE")"
  else
    log "ERROR" "Checksum creation failed"
    cleanup_and_exit 1
  fi
fi

# Verification: compare checksum and attempt to list archive
if [[ $DRY_RUN -eq 1 ]]; then
  log "INFO" "DRY RUN: Would verify checksum and attempt archive extraction test"
else
  # re-calc
  TMPCHK=$(mktemp)
  if [[ "$CHKSUM_TOOL" == "sha256sum" || "$CHKSUM_TOOL" == "md5sum" ]]; then
    $CHKSUM_TOOL "$ARCHIVE_PATH" > "$TMPCHK"
  else
    shasum -a 256 "$ARCHIVE_PATH" > "$TMPCHK"
  fi
  if cmp -s "$TMPCHK" "$CHECKSUM_FILE"; then
    log "INFO" "Checksum verified successfully"
  else
    log "FAILED" "Checksum mismatch!"
    rm -f "$TMPCHK"
    cleanup_and_exit 1
  fi
  rm -f "$TMPCHK"

  # Try to list archive contents (quick integrity test)
  if tar -tzf "$ARCHIVE_PATH" >/dev/null 2>&1; then
    log "INFO" "Archive list OK"
    # attempt to extract a single small file to /tmp test - safer to just do a list but we'll attempt a --to-stdout of first file
    firstfile=$(tar -tzf "$ARCHIVE_PATH" | head -n 1)
    if [[ -n "$firstfile" ]]; then
      if tar -xOf "$ARCHIVE_PATH" "$firstfile" >/dev/null 2>&1; then
        log "SUCCESS" "Archive extraction test passed"
        echo "SUCCESS"
      else
        log "FAILED" "Archive extraction test failed"
        echo "FAILED"
        cleanup_and_exit 1
      fi
    else
      # empty archive? treat as success (but warn)
      log "INFO" "Archive appears empty"
      echo "SUCCESS"
    fi
  else
    log "FAILED" "Archive is corrupted (tar -tzf failed)"
    echo "FAILED"
    cleanup_and_exit 1
  fi
fi

# Retention: delete old backups according to daily/weekly/monthly policy
# Algorithm: list all backups sorted by date desc, iterate and keep first occurrence per-day up to DAILY_KEEP,
# then keep by week up to WEEKLY_KEEP, then keep by month up to MONTHLY_KEEP; others are deleted.

if [[ $DRY_RUN -eq 1 ]]; then
  log "INFO" "DRY RUN: Retention policy would be applied"
else
  log "INFO" "Applying retention policy: daily=$DAILY_KEEP, weekly=$WEEKLY_KEEP, monthly=$MONTHLY_KEEP"
fi

# gather backups
mapfile -t backups < <(ls -1t "$BACKUP_DESTINATION"/backup-*.tar.gz 2>/dev/null || true)

declare -A kept_days kept_weeks kept_months
daily_count=0
weekly_count=0
monthly_count=0

for b in "${backups[@]}"; do
  bn="$(basename "$b")"
  datepart="${bn#backup-}"; datepart="${datepart%.tar.gz}"
  # parse datepart expecting YYYY-MM-DD-HHMM
  # convert to YYYY-MM-DD for day, week via date
  day="${datepart:0:10}"
  # get week and month; use date -d; some systems require different flags; attempt portable approach
  if date -d "$day" +'%G-%V' >/dev/null 2>&1; then
    week="$(date -d "$day" +'%G-%V')"   # ISO week e.g. 2024-45
    month="$(date -d "$day" +'%Y-%m')"
  else
    # macOS BSD date fallback: use python if available, else approximate with YYYY-WW from day
    if command -v python3 >/dev/null 2>&1; then
      week="$(python3 -c "import datetime as d; x=d.date.fromisoformat('$day'); print(x.isocalendar()[0], '{:02d}'.format(x.isocalendar()[1]), sep='-')")"
      month="$(python3 -c "import datetime as d; x=d.date.fromisoformat('$day'); print(f'{x.year}-{x.month:02d}')")"
    else
      week="${day:0:7}" # fallback crude
      month="${day:0:7}"
    fi
  fi

  keep="no"
  if [[ -z "${kept_days[$day]}" && "$daily_count" -lt "$DAILY_KEEP" ]]; then
    keep="yes"
    kept_days[$day]=1
    daily_count=$((daily_count+1))
  elif [[ -z "${kept_weeks[$week]}" && "$weekly_count" -lt "$WEEKLY_KEEP" ]]; then
    keep="yes"
    kept_weeks[$week]=1
    weekly_count=$((weekly_count+1))
  elif [[ -z "${kept_months[$month]}" && "$monthly_count" -lt "$MONTHLY_KEEP" ]]; then
    keep="yes"
    kept_months[$month]=1
    monthly_count=$((monthly_count+1))
  fi

  if [[ "$keep" == "yes" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      log "INFO" "DRY RUN: Would keep $bn"
    else
      log "INFO" "Keeping $bn"
    fi
  else
    if [[ $DRY_RUN -eq 1 ]]; then
      log "INFO" "DRY RUN: Would delete $bn and its checksum"
    else
      log "INFO" "Deleting old backup: $bn"
      rm -f "$b" "$b.md5"
      if [[ $? -eq 0 ]]; then
        log "SUCCESS" "Deleted old backup: $bn"
      else
        log "ERROR" "Failed to delete $bn"
      fi
    fi
  fi
done

# Completed
log "INFO" "Backup job finished for $SRC"
[[ -n "$NOTIFY_EMAIL" ]] && send_email "Backup completed: $(basename "$ARCHIVE_PATH")" "Backup completed for $SRC at $TIMESTAMP"

cleanup_and_exit 0
