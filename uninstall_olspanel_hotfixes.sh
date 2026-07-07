#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${OLSPANEL_BASE_DIR:-/usr/local/olspanel/mypanel}"
ACTION="${1:-all}"
BACKUP_ROOT="${BACKUP_ROOT:-/root/olspanel-hotfixes/backups}"
UNINSTALL_BACKUP_ROOT="${UNINSTALL_BACKUP_ROOT:-/root/olspanel-hotfixes/uninstall-backups}"
SELECTED_BACKUP="${2:-latest}"
TS="$(date +%Y%m%d_%H%M%S)"
PRE_RESTORE_BACKUP_DIR="$UNINSTALL_BACKUP_ROOT/$TS"

if [[ "${ACTION}" == "--list" ]]; then
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort
  exit 0
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Please run as root (sudo)."
  exit 1
fi

if [[ ! -d "$BASE_DIR" ]]; then
  echo "OLSPanel base directory not found: $BASE_DIR"
  exit 1
fi

if [[ ! -d "$BACKUP_ROOT" ]]; then
  echo "Backup root not found: $BACKUP_ROOT"
  exit 1
fi

resolve_backup_dir() {
  if [[ "$SELECTED_BACKUP" == "latest" ]]; then
    local latest
    latest="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)"
    if [[ -z "$latest" ]]; then
      echo "No backup directories found in $BACKUP_ROOT"
      exit 1
    fi
    echo "$latest"
    return
  fi

  if [[ -d "$SELECTED_BACKUP" ]]; then
    echo "$SELECTED_BACKUP"
    return
  fi

  if [[ -d "$BACKUP_ROOT/$SELECTED_BACKUP" ]]; then
    echo "$BACKUP_ROOT/$SELECTED_BACKUP"
    return
  fi

  echo "Backup directory not found: $SELECTED_BACKUP"
  exit 1
}

BACKUP_DIR="$(resolve_backup_dir)"
mkdir -p "$PRE_RESTORE_BACKUP_DIR"

restore_file() {
  local rel="$1"
  local src="$BACKUP_DIR$rel"
  local dst="$rel"

  if [[ ! -f "$src" ]]; then
    echo "[warn] Missing in backup, skipping: $src"
    return
  fi

  if [[ -f "$dst" ]]; then
    mkdir -p "$PRE_RESTORE_BACKUP_DIR$(dirname "$rel")"
    cp -a "$dst" "$PRE_RESTORE_BACKUP_DIR$rel"
  fi

  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst"
  echo "[ok] Restored: $dst"
}

restore_imunify() {
  restore_file "$BASE_DIR/whm/function.py"
  restore_file "$BASE_DIR/3rdparty/imunifyfav/auto_index.php"
}

restore_webmail() {
  restore_file "$BASE_DIR/users/views.py"
}

restore_php_installers() {
  restore_file "$BASE_DIR/whm/views.py"
  restore_file "$BASE_DIR/users/server_core.py"
  restore_file "$BASE_DIR/whm/templates/whm/php_ext.html"
}

case "$ACTION" in
  imunify)
    restore_imunify
    ;;
  webmail)
    restore_webmail
    ;;
  php-installers)
    restore_php_installers
    ;;
  all)
    restore_imunify
    restore_webmail
    restore_php_installers
    ;;
  *)
    echo "Unknown action: $ACTION"
    echo "Usage: $0 [imunify|webmail|php-installers|all|--list] [backup-dir|timestamp|latest]"
    exit 1
    ;;
esac

if [[ -f "$BASE_DIR/whm/function.py" ]]; then
  python3 -m py_compile "$BASE_DIR/whm/function.py"
fi
if [[ -f "$BASE_DIR/users/views.py" ]]; then
  python3 -m py_compile "$BASE_DIR/users/views.py"
fi
if [[ -f "$BASE_DIR/whm/views.py" ]]; then
  python3 -m py_compile "$BASE_DIR/whm/views.py"
fi
if [[ -f "$BASE_DIR/users/server_core.py" ]]; then
  python3 -m py_compile "$BASE_DIR/users/server_core.py"
fi

systemctl restart cp
systemctl restart lsws 2>/dev/null || systemctl restart openlitespeed 2>/dev/null || true

echo
echo "Uninstall/rollback complete."
echo "Restored from: $BACKUP_DIR"
echo "Pre-restore copies saved to: $PRE_RESTORE_BACKUP_DIR"
echo ""
echo "Re-apply hotfixes:"
echo "  cd /root/olspanel-hotfixes && bash apply_olspanel_hotfixes.sh all"
