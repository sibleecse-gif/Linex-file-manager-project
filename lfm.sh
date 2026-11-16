#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0.0"

usage() {
cat <<'EOF'
lfm - Linux File Manager

Usage:
  lfm <command> [path] [options]

Commands:
  help                         Show this help
  init <path>                  Initialize lfm in directory
  list <path> [--type t] [--max-depth N] [--human]
  find <path> [--name PAT] [--regex RE] [--ignore-case]
  report <path> [--by size|ext]
  archive <path> --output FILE.tar.gz [--exclude PAT]...
  backup <path> --to TARGET [--dry-run] [--exclude PAT]...
  trash <path> <file...>      Move files/dirs to trash
  restore <path> <file...>    Restore files/dirs from trash
  purge-trash                  Permanently delete trashed items (prompts)
  dedupe <path> [--apply]     Detect (and optionally remove) duplicates
  log <path>                  Show lfm log for path
  version                      Show version

Examples:
  lfm init /data/project
  lfm list /data/project --type file --max-depth 2 --human
  lfm find /data/project --name "*.csv"
  lfm report /data/project --by size
  lfm archive /data/project --output /backups/project.tar.gz --exclude ".git"
  lfm backup /data/project --to /backups/project --dry-run

EOF
}

error() { echo "Error: $*" >&2; exit 1; }
info()  { echo "[lfm] $*" >&2; }

# --- Config handling ---
expand_path() { # expands ~ and vars
  local p="$1"
  eval "echo \"$p\""
}

config_get() {
  local key="$1" default="$2"
  local proj="$3"

  local cfg_candidates=()
  if [[ -n "$proj" ]]; then
    cfg_candidates+=("$proj/.lfm/lfm.conf")
  fi
  if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
    cfg_candidates+=("$XDG_CONFIG_HOME/lfm/config")
  else
    cfg_candidates+=("$HOME/.config/lfm/config")
  fi

  for cfg in "${cfg_candidates[@]}"; do
    if [[ -f "$cfg" ]]; then
      local val
      val="$(awk -F'=' -v key="$key" '
        $0 !~ /^#/ {
          gsub(/^[ \t]+|[ \t]+$/, "", $0)
          split($0, parts, "=")
          gsub(/^[ \t]+|[ \t]+$/, "", parts[1])
          if (parts[1] == key) {
            sub(/^[^=]*=/, "", $0)
            gsub(/^[ \t]+|[ \t]+$/, "", $0)
            print $0
            exit
          }
        }' "$cfg")"
      if [[ -n "$val" ]]; then
        echo "$val"
        return 0
      fi
    fi
  done
  echo "$default"
}

ensure_init() {
  local dir="$1"
  [[ -d "$dir" ]] || error "Directory not found: $dir"
  mkdir -p "$dir/.lfm"
  local log_rel
  log_rel="$(config_get 'log_file' '.lfm/lfm.log' "$dir")"
  local log_path="$dir/$log_rel"
  mkdir -p "$(dirname "$log_path")"
  touch "$log_path"
}

log_op() {
  local dir="$1"; shift
  local log_rel
  log_rel="$(config_get 'log_file' '.lfm/lfm.log' "$dir")"
  local log_path="$dir/$log_rel"
  printf "%s | %s\n" "$(date -Is)" "$*" >> "$log_path"
}

is_number() { [[ "$1" =~ ^[0-9]+$ ]]; }

# --- Subcommands ---

cmd_init() {
  local dir="$1"
  mkdir -p "$dir/.lfm"
  if [[ ! -f "$dir/.lfm/lfm.conf" ]]; then
    cat > "$dir/.lfm/lfm.conf" <<'CFG'
# Project-local lfm config
[core]
trash_dir = ~/.local/share/lfm/trash
log_file = .lfm/lfm.log

[backup]
rsync_flags = -aHAX --delete --info=stats1,progress2
exclude = .git,.lfm,*.tmp,*.swp
CFG
  fi
  touch "$dir/.lfm/lfm.log"
  echo "Initialized lfm in $dir"
}

cmd_list() {
  local dir="$1"; shift
  local type="" max_depth="" human=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type) type="$2"; shift 2;;
      --max-depth) max_depth="$2"; shift 2;;
      --human) human=1; shift;;
      *) error "Unknown option: $1";;
    esac
  done

  ensure_init "$dir"

  local find_cmd=(find "$dir" -mindepth 1)
  [[ -n "$max_depth" ]] && find_cmd+=(-maxdepth "$max_depth")
  if [[ -n "$type" ]]; then
    case "$type" in file|f) find_cmd+=(-type f);;
      dir|d) find_cmd+=(-type d);;
      link|l) find_cmd+=(-type l);;
      *) error "Invalid type: $type (file|dir|link)";;
    esac
  fi

  if [[ $human -eq 1 ]]; then
    "${find_cmd[@]}" -print0 | xargs -0 du -sh -- 2>/dev/null | sort -h
  else
    "${find_cmd[@]}"
  fi
  log_op "$dir" "list type=$type max_depth=${max_depth:-} human=$human"
}

cmd_find() {
  local dir="$1"; shift
  local name="" regex="" ignore=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2;;
      --regex) regex="$2"; shift 2;;
      --ignore-case) ignore=1; shift;;
      *) error "Unknown option: $1";;
    esac
  done
  ensure_init "$dir"

  local find_cmd=(find "$dir" -mindepth 1)
  if [[ -n "$name" ]]; then
    if [[ $ignore -eq 1 ]]; then
      find_cmd+=(-iname "$name")
    else
      find_cmd+=(-name "$name")
    fi
  fi
  if [[ -n "$regex" ]]; then
    if [[ $ignore -eq 1 ]]; then
      find_cmd+=(-iregex "$regex")
    else
      find_cmd+=(-regex "$regex")
    fi
  fi
  "${find_cmd[@]}"
  log_op "$dir" "find name=${name:-} regex=${regex:-} ignore=$ignore"
}

cmd_report() {
  local dir="$1"; shift
  local by="size"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --by) by="$2"; shift 2;;
      *) error "Unknown option: $1";;
    esac
  done
  ensure_init "$dir"

  case "$by" in
    size)
      du -sh "$dir" 2>/dev/null
      echo "Top 20 largest items:"
      du -ah "$dir" 2>/dev/null | sort -rh | head -n 20
      ;;
    ext)
      find "$dir" -type f -printf "%f\n" | awk -F. 'NF>1{print tolower($NF)}' \
        | sort | uniq -c | sort -rn
      ;;
    *)
      error "Unknown report type: $by"
      ;;
  esac
  log_op "$dir" "report by=$by"
}

cmd_archive() {
  local dir="$1"; shift
  local output="" excludes=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output) output="$2"; shift 2;;
      --exclude) excludes+=("$2"); shift 2;;
      *) error "Unknown option: $1";;
    esac
  done
  [[ -n "$output" ]] || error "--output FILE.tar.gz is required"
  ensure_init "$dir"

  local tar_args=(--exclude=".lfm")
  for e in "${excludes[@]:-}"; do tar_args+=(--exclude="$e"); done
  mkdir -p "$(dirname "$output")"
  (cd "$dir" && tar -czf "$output" "${tar_args[@]}" .)
  echo "Archive created: $output"
  log_op "$dir" "archive output=$output excludes=${excludes[*]:-}"
}

cmd_backup() {
  local dir="$1"; shift
  local to="" dry=0 excludes=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --to) to="$2"; shift 2;;
      --dry-run) dry=1; shift;;
      --exclude) excludes+=("$2"); shift 2;;
      *) error "Unknown option: $1";;
    esac
  done
  [[ -n "$to" ]] || error "--to TARGET is required"
  ensure_init "$dir"
  mkdir -p "$to"

  local flags
  flags="$(config_get 'rsync_flags' '-aHAX --delete --info=stats1,progress2' "$dir")"
  IFS=',' read -r -a cfg_excl <<< "$(config_get 'exclude' '' "$dir")"
  local rsync_cmd=(rsync $flags)
  for e in "${cfg_excl[@]}"; do [[ -n "$e" ]] && rsync_cmd+=(--exclude "$e"); done
  for e in "${excludes[@]:-}"; do rsync_cmd+=(--exclude "$e"); done
  [[ $dry -eq 1 ]] && rsync_cmd+=("--dry-run")

  rsync_cmd+=("$dir"/ "$to"/)
  # shellcheck disable=SC2068
  ${rsync_cmd[@]}
  log_op "$dir" "backup to=$to dry=$dry excludes=${excludes[*]:-}"
}

trash_dir_for() {
  local dir="$1"
  local tdir
  tdir="$(config_get 'trash_dir' '~/.local/share/lfm/trash' "$dir")"
  expand_path "$tdir"
}

cmd_trash() {
  local dir="$1"; shift
  [[ $# -gt 0 ]] || error "Specify at least one file/dir to trash"
  ensure_init "$dir"
  local tdir; tdir="$(trash_dir_for "$dir")"
  mkdir -p "$tdir"
  for rel in "$@"; do
    local src="$dir/$rel"
    [[ -e "$src" ]] || { echo "Skip (not found): $rel" >&2; continue; }
    local stamp; stamp="$(date +%s)"
    local base; base="$(basename "$rel")"
    local dst="$tdir/${base}.${stamp}"
    mv "$src" "$dst"
    echo "Trashed: $rel -> $dst"
  done
  log_op "$dir" "trash items=$*"
}

cmd_restore() {
  local dir="$1"; shift
  [[ $# -gt 0 ]] || error "Specify at least one file/dir to restore"
  ensure_init "$dir"
  local tdir; tdir="$(trash_dir_for "$dir")"
  for name in "$@"; do
    local cand
    cand="$(ls -1t "$tdir"/"$name".* 2>/dev/null | head -n1 || true)"
    [[ -n "$cand" ]] || { echo "Not found in trash: $name" >&2; continue; }
    mv "$cand" "$dir/$name"
    echo "Restored: $name"
  done
  log_op "$dir" "restore items=$*"
}

cmd_purge_trash() {
  read -rp "Permanently delete ALL items in trash? (y/N): " ans
  if [[ "${ans,,}" == "y" ]]; then
    local tdir; tdir="$(trash_dir_for "$PWD")"
    rm -rf "$tdir"/*
    echo "Trash purged."
  else
    echo "Aborted."
  fi
}

cmd_dedupe() {
  local dir="$1"; shift
  local apply=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply) apply=1; shift;;
      *) error "Unknown option: $1";;
    esac
  done
  ensure_init "$dir"

  declare -A map
  while IFS= read -r -d '' f; do
    # Skip lfm internal dir
    [[ "$f" == "$dir/.lfm"* ]] && continue
    local sum
    sum="$(sha256sum "$f" | awk '{print $1}')"
    if [[ -n "${map[$sum]:-}" ]]; then
      echo "DUPLICATE: $f == ${map[$sum]}"
      if [[ $apply -eq 1 ]]; then
        rm -f "$f"
        echo "Removed: $f"
      fi
    else
      map[$sum]="$f"
    fi
  done < <(find "$dir" -type f -print0)
  log_op "$dir" "dedupe apply=$apply"
}

cmd_log() {
  local dir="$1"
  ensure_init "$dir"
  local log_rel
  log_rel="$(config_get 'log_file' '.lfm/lfm.log' "$dir")"
  cat "$dir/$log_rel"
}

main() {
  local cmd="${1:-help}"
  case "$cmd" in
    help|-h|--help) usage ;;
    version|--version|-v) echo "$VERSION" ;;
    init) shift; [[ $# -ge 1 ]] || error "init requires <path>"; cmd_init "$@";;
    list) shift; [[ $# -ge 1 ]] || error "list requires <path>"; cmd_list "$@";;
    find) shift; [[ $# -ge 1 ]] || error "find requires <path>"; cmd_find "$@";;
    report) shift; [[ $# -ge 1 ]] || error "report requires <path>"; cmd_report "$@";;
    archive) shift; [[ $# -ge 1 ]] || error "archive requires <path>"; cmd_archive "$@";;
    backup) shift; [[ $# -ge 1 ]] || error "backup requires <path>"; cmd_backup "$@";;
    trash) shift; [[ $# -ge 2 ]] || error "trash requires <path> <file...>"; cmd_trash "$@";;
    restore) shift; [[ $# -ge 2 ]] || error "restore requires <path> <file...>"; cmd_restore "$@";;
    purge-trash) shift; cmd_purge_trash "$@";;
    dedupe) shift; [[ $# -ge 1 ]] || error "dedupe requires <path>"; cmd_dedupe "$@";;
    log) shift; [[ $# -ge 1 ]] || error "log requires <path>"; cmd_log "$@";;
    *) usage; error "Unknown command: $cmd";;
  esac
}

main "$@"
