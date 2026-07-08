# OLSPanel Hotfixes

Reusable hotfix package for fresh OLSPanel servers.

This repository provides:

- Installer script to apply validated hotfixes
- Uninstaller script to roll back from backup snapshots
- Runbook for operations and troubleshooting

## Repository Contents

- `apply_olspanel_hotfixes.sh`: applies one or all hotfix groups
- `uninstall_olspanel_hotfixes.sh`: restores files from backups (latest or selected snapshot)
- `HOTFIX_RUNBOOK.md`: detailed operational notes
- `.gitignore`: excludes runtime backup folders from git

## Hotfix Groups Included

### 1) ImunifyAV fixes (`imunify`)

- Hardens Imunify installer flow in `whm/function.py`
- Installs and extracts the `imunify-ui-generic` bundle when available
- Normalizes ownership/permissions after deploy
- Rewrites Imunify auto-login bridge in `3rdparty/imunifyfav/auto_index.php`

### 2) Webmail route fix (`webmail`)

- Fixes `/webmail` behavior by redirecting to `webmail_service` using first mailbox
- Target file: `users/views.py`

### 3) WHM PHP extension/module fixes (`php-installers`)

- Improves extension install/uninstall result handling in `whm/views.py`
- Improves PHP module install reliability (package-manager-first, fallback flow)
- Fixes backend extension manager logic in `users/server_core.py`
- Fixes extension UI button handler in `whm/templates/whm/php_ext.html`

## Requirements

- Root access (`sudo`)
- Existing OLSPanel installation (default path: `/usr/local/olspanel/mypanel`)
- `python3`, `bash`, `systemctl`

## Installation On Fresh Server

```bash
cd /root
git clone https://github.com/cotlaswebhost/olspanelhotfixes.git
cd olspanelhotfixes
sudo bash apply_olspanel_hotfixes.sh all
```

## Usage

Apply specific hotfix group:

```bash
sudo bash apply_olspanel_hotfixes.sh imunify
sudo bash apply_olspanel_hotfixes.sh webmail
sudo bash apply_olspanel_hotfixes.sh php-installers
```

Apply all groups:

```bash
sudo bash apply_olspanel_hotfixes.sh all
```

## What Installer Does

1. Creates timestamped backup under `backups/<timestamp>`
2. Applies selected patch set
3. Compiles patched Python files
4. Restarts `cp`
5. Restarts OpenLiteSpeed service (`lsws` or `openlitespeed`)

## Uninstall / Rollback

List available snapshots:

```bash
sudo bash uninstall_olspanel_hotfixes.sh --list
```

Restore all from latest snapshot:

```bash
sudo bash uninstall_olspanel_hotfixes.sh all latest
```

Restore all from specific snapshot:

```bash
sudo bash uninstall_olspanel_hotfixes.sh all 20260707_102517
```

Restore only one group from latest snapshot:

```bash
sudo bash uninstall_olspanel_hotfixes.sh imunify latest
sudo bash uninstall_olspanel_hotfixes.sh webmail latest
sudo bash uninstall_olspanel_hotfixes.sh php-installers latest
```

## Backup Paths

- Installer backups: `/root/olspanel-hotfixes/backups/<timestamp>/...`
- Uninstaller pre-restore safety backups: `/root/olspanel-hotfixes/uninstall-backups/<timestamp>/...`

## Reinstall Test Cycle

```bash
cd /root/olspanel-hotfixes
sudo bash uninstall_olspanel_hotfixes.sh all latest
sudo bash apply_olspanel_hotfixes.sh all
```

## Environment Override

If your OLSPanel path differs, set `OLSPANEL_BASE_DIR`:

```bash
sudo OLSPANEL_BASE_DIR=/custom/path/mypanel bash apply_olspanel_hotfixes.sh all
sudo OLSPANEL_BASE_DIR=/custom/path/mypanel bash uninstall_olspanel_hotfixes.sh all latest
```

## Notes

- Use on OLSPanel versions close to the tested baseline.
- If a patch reports "Could not patch ...", code layout has diverged; inspect manually using backups.
- Prefer staging validation before production rollout.
