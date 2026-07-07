# OLSPanel Server Hotfix Runbook

This runbook applies the non-plugin fixes we validated on this server.

## Covered fixes

1. ImunifyAV 404/login failures
- Hardens Imunify installer flow to clear stale UI directory before deployment.
- Normalizes ownership and permissions after install.
- Updates Imunify auto-login bridge to fallback token users (`PANEL_USERNAME`, `root`, `www-data`).

2. Core webmail `/webmail` 404 behavior
- Updates user webmail route to redirect into internal `webmail_service` using first mailbox.

3. WHM PHP Extensions installer/uninstaller issues
- Fixes backend false-success behavior in extension manager.
- Fixes undefined `run_package_update` failure in `manage_php_extension`.
- Improves error messages from package manager output.
- Fixes frontend button handler to pass clicked button explicitly.

4. WHM PHP Modules installer reliability
- Tries distro package install first (`lsphpXX-module` / `phpX.Y-module`).
- Falls back to existing PECL installer script if package is unavailable.

## Files added

- `/root/olspanel-hotfixes/apply_olspanel_hotfixes.sh`
- `/root/olspanel-hotfixes/uninstall_olspanel_hotfixes.sh`

## How to run (one-by-one)

```bash
cd /root/olspanel-hotfixes
sudo bash apply_olspanel_hotfixes.sh imunify
sudo bash apply_olspanel_hotfixes.sh webmail
sudo bash apply_olspanel_hotfixes.sh php-installers
```

## How to run all fixes at once

```bash
cd /root/olspanel-hotfixes
sudo bash apply_olspanel_hotfixes.sh all
```

## What each command does

- `imunify`
  - Patches `/usr/local/olspanel/mypanel/whm/function.py` (`install_imunifyfav_now`).
  - Rewrites `/usr/local/olspanel/mypanel/3rdparty/imunifyfav/auto_index.php`.

- `webmail`
  - Patches `/usr/local/olspanel/mypanel/users/views.py` (`webmail` function).

- `php-installers`
  - Patches `/usr/local/olspanel/mypanel/whm/views.py`:
    - `php_ext`
    - `php_ext_manage`
    - `install_php_modules`
  - Patches `/usr/local/olspanel/mypanel/users/server_core.py`:
    - `manage_php_extension`
  - Patches `/usr/local/olspanel/mypanel/whm/templates/whm/php_ext.html`:
    - robust button handler argument passing.

After each action, script compiles patched Python files and restarts `cp` and OpenLiteSpeed.

## Backup and rollback

Each run stores backups under:

`/root/olspanel-hotfixes/backups/<timestamp>/...`

To rollback a file manually:

```bash
sudo cp -a /root/olspanel-hotfixes/backups/<timestamp>/usr/local/olspanel/mypanel/<relative-path> /usr/local/olspanel/mypanel/<relative-path>
sudo systemctl restart cp
```

## Uninstall script (restore hotfixes)

List available backup snapshots:

```bash
cd /root/olspanel-hotfixes
sudo bash uninstall_olspanel_hotfixes.sh --list
```

Restore all files from latest snapshot:

```bash
cd /root/olspanel-hotfixes
sudo bash uninstall_olspanel_hotfixes.sh all latest
```

Restore all files from a specific snapshot timestamp:

```bash
cd /root/olspanel-hotfixes
sudo bash uninstall_olspanel_hotfixes.sh all 20260707_102517
```

Restore one fix group only:

```bash
sudo bash uninstall_olspanel_hotfixes.sh imunify latest
sudo bash uninstall_olspanel_hotfixes.sh webmail latest
sudo bash uninstall_olspanel_hotfixes.sh php-installers latest
```

The uninstall script also stores pre-restore copies under:

`/root/olspanel-hotfixes/uninstall-backups/<timestamp>/...`

So you can re-apply previous patched versions if needed.

## Publish and use from GitHub

Repository:

`https://github.com/cotlaswebhost/olspanelhotfixes`

Install on fresh server:

```bash
cd /root
git clone https://github.com/cotlaswebhost/olspanelhotfixes.git
cd olspanelhotfixes
sudo bash apply_olspanel_hotfixes.sh all
```

## Notes

- Use only on OLSPanel versions close to the current server baseline.
- If script reports "Could not patch ...", code layout differs; apply manually from backup-aware diff.
