#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${OLSPANEL_BASE_DIR:-/usr/local/olspanel/mypanel}"
ACTION="${1:-all}"
TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="/root/olspanel-hotfixes/backups/${TS}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Please run as root (sudo)."
  exit 1
fi

if [[ ! -d "$BASE_DIR" ]]; then
  echo "OLSPanel base directory not found: $BASE_DIR"
  exit 1
fi

mkdir -p "$BACKUP_DIR"

backup_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP_DIR$(dirname "$f")"
    cp -a "$f" "$BACKUP_DIR$f"
  fi
}

patch_imunify() {
  local whm_func="$BASE_DIR/whm/function.py"
  local imav_auto="$BASE_DIR/3rdparty/imunifyfav/auto_index.php"

  backup_file "$whm_func"
  backup_file "$imav_auto"

  BASE_DIR="$BASE_DIR" python3 - <<'PY'
import os, re, pathlib
base = pathlib.Path(os.environ["BASE_DIR"])
whm_func = base / "whm" / "function.py"
imav_auto = base / "3rdparty" / "imunifyfav" / "auto_index.php"

new_func = '''def install_imunifyfav_now():
    
    upgrade_script_url = "https://olspanel.com/extra/imunifyfav.sh"
    extract_path = settings.BASE_DIR.parent
    upgrade_script_path = f"{settings.BASE_DIR.parent}/imunifyfav.sh"
    imunify_ui_path = f"{settings.BASE_DIR.parent}/3rdparty/imunifyfav"
   
    
    try:
        # Step 1: Download and run the upgrade.sh script
        print("Step 1: Downloading imunifyfav.sh...")
        subprocess.run(f"wget -O {upgrade_script_path} {upgrade_script_url}", shell=True, check=True)

        # Step 2: Remove Windows-style line endings (if any) from the upgrade.sh file
        print("Step 2: Removing Windows-style line endings from imunifyfav.sh...")
        subprocess.run(f"sed -i 's/\\\\r$//' {upgrade_script_path}", shell=True, check=True)

        # Step 2.5: Prepare empty Imunify UI directory to avoid deploy abort.
        print("Step 2.5: Preparing empty UI path...")
        subprocess.run(
            f"mkdir -p {imunify_ui_path} && find {imunify_ui_path} -mindepth 1 -delete",
            shell=True,
            check=True,
        )
        
        # Step 3: Running imunifyfav.sh
        print("Step 3: Running imunifyfav.sh...")
        subprocess.run(f"chmod +x {upgrade_script_path} && {upgrade_script_path}", shell=True, check=True)

        # Step 4: Ensure UI files are readable by panel user.
        print("Step 4: Normalizing ownership and permissions...")
        subprocess.run(
            f"chown -R nobody:nogroup {imunify_ui_path} && find {imunify_ui_path} -type d -exec chmod 755 {{}} \\; && find {imunify_ui_path} -type f -exec chmod 644 {{}} \\;",
            shell=True,
            check=True,
        )

        index_file_path = os.path.join(imunify_ui_path, "index.php")
        if not os.path.exists(index_file_path):
            with open(index_file_path, "w", encoding="utf-8") as index_file:
                index_file.write("""<?php
?><!doctype html>
<html lang=\"en\">
<head>
    <meta charset=\"utf-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
    <title>ImunifyAV</title>
    <style>
        body { font-family: Arial, sans-serif; background: #f6f7fb; color: #1f2937; margin: 0; min-height: 100vh; display: grid; place-items: center; }
        .card { width: min(560px, calc(100% - 2rem)); background: #fff; border-radius: 18px; box-shadow: 0 18px 60px rgba(0,0,0,.12); padding: 32px; text-align: center; }
        .title { font-size: 28px; font-weight: 700; margin: 0 0 12px; }
        .muted { color: #6b7280; line-height: 1.5; }
        code { background: #eef2ff; padding: 0.15rem 0.35rem; border-radius: 6px; }
    </style>
</head>
<body>
    <div class=\"card\">
        <div class=\"title\">ImunifyAV</div>
        <div id=\"status\" class=\"muted\">Loading ImunifyAV dashboard...</div>
        <p class=\"muted\" style=\"margin-top: 16px;\">If the full UI bundle is present, this page will hand off to it. Otherwise this fallback prevents a 404 while the plugin is initialized.</p>
    </div>
    <script>
        const status = document.getElementById('status');
        const hash = window.location.hash || '';
        const tokenMatch = hash.match(/token=([^&]+)/);
        if (tokenMatch) {
            status.textContent = 'ImunifyAV session token detected.';
        } else {
            status.textContent = 'ImunifyAV dashboard is ready.';
        }
    </script>
</body>
</html>
""")

        

        # Step 6: Clean up by removing the downloaded upgrade script
        print("Step 6: Cleaning up...")
       
        os.remove(upgrade_script_path)
       
        print("Installation complete!")
        return "imunifyfav has been successfully installed."

    except subprocess.CalledProcessError as e:
        logger.error(f"An error occurred during the update installation: {e}")
        return f"An error occurred during the update installation: {e}"
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return f"Unexpected error: {e}"   
'''

content = whm_func.read_text(encoding='utf-8')
content2, n = re.subn(
    r"def install_imunifyfav_now\(\):.*?(?=\n\ndef download_softaculous_pkg\()",
    new_func.rstrip() + "\n\n",
    content,
    flags=re.S,
)
if n != 1:
    raise SystemExit("Could not patch install_imunifyfav_now in whm/function.py")
whm_func.write_text(content2, encoding='utf-8')

imav_auto.parent.mkdir(parents=True, exist_ok=True)
imav_auto.write_text('''<?php
$candidates = [];

if (!empty($_SERVER['PANEL_USERNAME'])) {
\t$candidates[] = $_SERVER['PANEL_USERNAME'];
}

$candidates[] = 'root';
$candidates[] = 'www-data';
$candidates = array_values(array_unique($candidates));

$token = '';
foreach ($candidates as $username) {
\t$candidate = trim((string)shell_exec("imunify-antivirus login get --username " . escapeshellarg($username) . " 2>/dev/null"));
\tif ($candidate !== '') {
\t\t$token = $candidate;
\t\tbreak;
\t}
}

if ($token === '') {
\thttp_response_code(500);
\techo 'Unable to generate ImunifyAV login token.';
\texit;
}

header("Location: /3rdparty/imunifyfav/index.php#/login?token=" . urlencode($token));
exit;
''', encoding='utf-8')
PY

  php -l "$imav_auto" >/dev/null
}

patch_webmail() {
  local views_py="$BASE_DIR/users/views.py"

  backup_file "$views_py"

  BASE_DIR="$BASE_DIR" python3 - <<'PY'
import os, re, pathlib
base = pathlib.Path(os.environ["BASE_DIR"])
views = base / "users" / "views.py"

new_block = '''@login_required
@admincheck
def webmail(request):
    email_main = Emails.objects.filter(userid=request.user.id).order_by('id').first()

    if not email_main:
        messages.info(request, 'Create an email account first to open webmail.')
        return redirect('email_accounts')

    return redirect(reverse('webmail_service', args=[email_main.email]))
'''

content = views.read_text(encoding='utf-8')
content2, n = re.subn(
    r"@login_required\n@admincheck\ndef webmail\(request\):.*?(?=\n\n@login_required\n@admincheck\ndef app_install_view)",
    new_block.rstrip() + "\n\n",
    content,
    flags=re.S,
)
if n != 1:
    raise SystemExit("Could not patch users.views.webmail")
views.write_text(content2, encoding='utf-8')
PY
}

patch_php_installers() {
  local whm_views="$BASE_DIR/whm/views.py"
  local server_core="$BASE_DIR/users/server_core.py"
  local php_ext_tpl="$BASE_DIR/whm/templates/whm/php_ext.html"

  backup_file "$whm_views"
  backup_file "$server_core"
  backup_file "$php_ext_tpl"

  BASE_DIR="$BASE_DIR" python3 - <<'PY'
import os, re, pathlib
base = pathlib.Path(os.environ["BASE_DIR"])
whm_views = base / "whm" / "views.py"
server_core = base / "users" / "server_core.py"
php_ext_tpl = base / "whm" / "templates" / "whm" / "php_ext.html"

php_ext_block = '''@alogin_required
def php_ext(request):
    php_versions_only = get_php_versions() 
    php_cgi_versions = get_cgi_php_versions()
    php_versions = php_versions_only + [v for v in php_cgi_versions if v not in php_versions_only]
    
    # Check for POST request to manage PHP extensions
    if request.method == 'POST':
        php_version = request.POST.get('php_version')
        extension = request.POST.get('extension')
        action = request.POST.get('action')

        if php_version and extension and action:
            # Call the manage_php_extension function for install/uninstall action
            result = manage_php_extension(php_version, extension, action)
            status = result.get('status', 'error') if isinstance(result, dict) else 'error'
            message = result.get('message', str(result)) if isinstance(result, dict) else str(result)

            if status == 'success':
                restart_lsphp()
                restart_openlitespeed()
                messages.success(request, message)
            else:
                messages.error(request, message)
        else:
            messages.error(request, 'Failed.')
            
        return redirect('/whm/php_ext/')    

    # Render the template with the PHP versions
    return render(request, 'whm/php_ext.html', {'php_versions': php_versions})
'''

php_ext_manage_block = '''@alogin_required
def php_ext_manage(request):
    php_versions = get_php_versions()  # Fetch PHP versions

    if request.method == 'POST':
        php_version = request.POST.get('php_version')
        extension = request.POST.get('extension')
        action = request.POST.get('action')

        if php_version and extension and action:
            # Perform install/uninstall action
            result = manage_php_extension(php_version, extension, action)
            status = result.get('status', 'error') if isinstance(result, dict) else 'error'
            message = result.get('message', str(result)) if isinstance(result, dict) else str(result)

            if status == 'success':
                restart_lsphp()
                restart_openlitespeed()
                return JsonResponse({'success': True, 'message': message})

            return JsonResponse({'success': False, 'message': message})
        else:
            return JsonResponse({'success': False, 'message': 'Missing parameters.'})

    # GET request: render template
    return render(request, 'whm/php_ext.html', {'php_versions': php_versions})
'''

install_modules_block = '''@alogin_required
def install_php_modules(request):
    try:
        php_version = request.POST.get('php_version', '').strip()
        ext = request.POST.get('ext', '').strip()

        if not php_version or not ext:
            return JsonResponse({
                "status": "error",
                "message": "Missing php_version or extension name."
            }, status=400)

        # === Detect PHP binary and ini file ===
        if php_version.startswith('cgi'):
            new_php_version = php_version.replace('cgi', '').strip()
            binf = f"/usr/bin/php-cgi{new_php_version}"
            ini_candidates = [
                f"/etc/php/{new_php_version}/cgi/php.ini",
                f"/etc/php/{new_php_version}/cgi/conf.d/php.ini"
            ]
        else:
            new_php_version = php_version.replace('.', '')
            binf = f"/usr/local/lsws/lsphp{new_php_version}"
            ini_candidates = [
                f"/usr/local/lsws/lsphp{new_php_version}/etc/php/{php_version}/litespeed/php.ini",
                f"/usr/local/lsws/lsphp{new_php_version}/etc/php.ini"
            ]

        ini = next((p for p in ini_candidates if os.path.exists(p)), None)
        if not ini:
            return JsonResponse({
                "status": "error",
                "message": f"php.ini not found for version {php_version}"
            }, status=404)

        ext = ext.lower()

        os_name = getattr(settings, "MY_OS_NAME", "linux").lower()
        if php_version.startswith('cgi'):
            pkg_version = php_version.replace('cgi', '').strip()
            pkg_prefix = f"php{pkg_version}-"
        else:
            pkg_version = php_version.replace('.', '')
            pkg_prefix = f"lsphp{pkg_version}-"

        pkg_name = f"{pkg_prefix}{ext}"

        # === Streaming output from script ===
        def stream_output():
            yield f"🔽 Starting installation of {ext} for PHP {php_version}...\\n"
            yield f"📁 Using binary: {binf}\\n"
            yield f"⚙️ Using INI: {ini}\\n\\n"

            # Prefer package manager first (fast and reliable for modules like imagick).
            try:
                if os_name in ["ubuntu", "debian"]:
                    pkg_exists = subprocess.run(
                        ["apt-cache", "show", pkg_name],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    ).returncode == 0

                    if pkg_exists:
                        yield f"📦 Package detected: {pkg_name}\\n"
                        install_proc = subprocess.Popen(
                            ["apt-get", "install", "-y", pkg_name],
                            stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT,
                            text=True,
                            bufsize=1,
                        )
                        for line in iter(install_proc.stdout.readline, ''):
                            yield line
                        install_proc.wait()

                        if install_proc.returncode == 0:
                            restart_lsphp()
                            restart_openlitespeed()
                            yield f"\\n✅ Installed via package manager: {pkg_name}\\n"
                            yield "\\n🎉 Done!\\n"
                            return
                        else:
                            yield f"\\n⚠️ Package install failed for {pkg_name}. Falling back to PECL script...\\n"
                    else:
                        yield f"ℹ️ Package not found: {pkg_name}. Falling back to PECL script...\\n"

                elif os_name in ["centos", "almalinux", "rocky", "rhel", "fedora", "oraclelinux", "amazonlinux"]:
                    pm = "dnf" if subprocess.run(["command", "-v", "dnf"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0 else "yum"
                    check_proc = subprocess.run(
                        [pm, "list", "available", pkg_name],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                    if check_proc.returncode == 0:
                        yield f"📦 Package detected: {pkg_name}\\n"
                        install_proc = subprocess.Popen(
                            [pm, "install", "-y", pkg_name],
                            stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT,
                            text=True,
                            bufsize=1,
                        )
                        for line in iter(install_proc.stdout.readline, ''):
                            yield line
                        install_proc.wait()

                        if install_proc.returncode == 0:
                            restart_lsphp()
                            restart_openlitespeed()
                            yield f"\\n✅ Installed via package manager: {pkg_name}\\n"
                            yield "\\n🎉 Done!\\n"
                            return
                        else:
                            yield f"\\n⚠️ Package install failed for {pkg_name}. Falling back to PECL script...\\n"
                    else:
                        yield f"ℹ️ Package not found: {pkg_name}. Falling back to PECL script...\\n"
            except Exception as e:
                yield f"⚠️ Package install step failed unexpectedly: {str(e)}\\n"

            script_url = "https://olspanel.com/extra/php_modules.sh"
            script_path = f"{settings.BASE_DIR.parent}/php_modules.sh"

            try:
                # Download script
                yield "Downloading installer script...\\n"
                subprocess.run(["wget", "-O", script_path, script_url], check=True)
                subprocess.run(["chmod", "+x", script_path], check=True)
                subprocess.run(["sed", "-i", "s/\\r$//", script_path], check=True)

                # Run the script and stream stdout
                yield "\\n🚀 Running module installer...\\n\\n"
                process = subprocess.Popen(
                    ["bash", script_path, ext, binf, ini],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1
                )
                for line in iter(process.stdout.readline, ''):
                    yield line
                process.wait()

                if process.returncode == 0:
                    restart_lsphp()
                    restart_openlitespeed()
                    yield f"\\n✅ Installation completed successfully for {ext}.\\n"
                else:
                    yield f"\\n❌ Installation failed. Exit code: {process.returncode}\\n"

            except subprocess.CalledProcessError as e:
                yield f"\\n❌ Command failed: {e}\\n"
            except Exception as e:
                yield f"\\n⚠️ Unexpected error: {str(e)}\\n"
            finally:
                if os.path.exists(script_path):
                    os.remove(script_path)
                    yield "\\n🧹 Cleaned up temporary files.\\n"

            yield "\\n🎉 Done!\\n"

        # === Return as live stream ===
        return StreamingHttpResponse(stream_output(), content_type='text/plain')

    except Exception as e:
        return JsonResponse({
            "status": "error",
            "message": f"Unexpected error: {str(e)}"
        }, status=500)
'''

server_core_block = '''def manage_php_extension(php_version, extension, action):
    try:
        os_name = getattr(settings, "MY_OS_NAME", "linux").lower()
        extension = (extension or "").strip().lower()

        if not extension:
            return {'status': 'error', 'message': 'Missing extension name.'}

        # Determine if CGI or lsphp version
        if php_version.startswith('cgi'):
            # Extract version number with dot, e.g. '7.4'
            try:
                version_num = php_version.split(' ')[1]
            except IndexError:
                return {'status': 'error', 'message': 'Invalid PHP version format.'}
            pkg_prefix = f'php{version_num}-'  # e.g. php7.4-mbstring
        else:
            # lsphp versions, remove dot for package names
            version_num = php_version.replace('.', '')
            pkg_prefix = f'lsphp{version_num}-'  # e.g. lsphp74-mbstring

        # Determine package manager & repo setup
        if os_name in ["ubuntu", "debian"]:
            # Add LiteSpeed repo only for lsphp packages (optional: skip for system php)
            if not php_version.startswith('cgi'):
                repo_cmd = "wget -O - https://repo.litespeed.sh | sudo bash"
                subprocess.run(repo_cmd, shell=True, check=True)
                # run_package_update() may not exist in this module.
                subprocess.run(
                    ["apt-get", "update"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                )
            install_command = "apt-get"
        elif os_name in ["centos", "almalinux", "rocky", "rhel", "fedora", "oraclelinux", "amazonlinux"]:
            install_command = "dnf" if subprocess.run(["command", "-v", "dnf"], stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode == 0 else "yum"
        else:
            return {'status': 'error', 'message': f'Unsupported OS: {os_name}'}

        pkg_name = f"{pkg_prefix}{extension}"

        if action == "install":
            command = f"sudo {install_command} install {pkg_name} -y"
        elif action == "uninstall":
            command = f"sudo {install_command} remove {pkg_name} -y"
        else:
            return {'status': 'error', 'message': f'Unknown action: {action}'}

        result = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        if result.returncode == 0:
            return {'status': 'success', 'message': f'Extension {extension} {action}ed successfully.'}
        else:
            err = result.stderr.strip()
            out = result.stdout.strip()
            return {'status': 'error', 'message': err or out or 'Package manager returned a non-zero status.'}

    except subprocess.CalledProcessError as e:
        return {'status': 'error', 'message': f'Command failed: {e}'}
    except Exception as e:
        return {'status': 'error', 'message': str(e)}
'''

wv = whm_views.read_text(encoding='utf-8')

def replace_block(pattern, block, text):
    return re.subn(pattern, lambda _match: block.rstrip() + "\n\n", text, flags=re.S)

wv, n1 = replace_block(r"@alogin_required\ndef php_ext\(request\):.*?(?=\n@alogin_required\ndef php_ext_manage\()", php_ext_block, wv)
wv, n2 = replace_block(r"@alogin_required\ndef php_ext_manage\(request\):.*?(?=\n@alogin_required\ndef php_ext_load\()", php_ext_manage_block, wv)
wv, n3 = replace_block(r"@alogin_required\ndef install_php_modules\(request\):.*?(?=\n@alogin_required\ndef )", install_modules_block, wv)
if n1 != 1 or n2 != 1 or n3 != 1:
    raise SystemExit(f"Could not patch whm/views.py blocks (php_ext={n1}, php_ext_manage={n2}, install_php_modules={n3})")
whm_views.write_text(wv, encoding='utf-8')

sc = server_core.read_text(encoding='utf-8')
sc2, n4 = re.subn(r"def manage_php_extension\(php_version, extension, action\):.*?(?=\n\n\n\ndef fetch_php_extensions\()", server_core_block.rstrip()+"\n\n", sc, flags=re.S)
if n4 != 1:
    raise SystemExit("Could not patch users/server_core.py manage_php_extension")
server_core.write_text(sc2, encoding='utf-8')

tpl = php_ext_tpl.read_text(encoding='utf-8')
tpl = tpl.replace("onclick=\"manageExtension('uninstall', '${ext}', '${data.selected_version}')\"", "onclick=\"manageExtension('uninstall', '${ext}', '${data.selected_version}', this)\"")
tpl = tpl.replace("onclick=\"manageExtension('install', '${ext}', '${data.selected_version}')\"", "onclick=\"manageExtension('install', '${ext}', '${data.selected_version}', this)\"")
tpl = tpl.replace("function manageExtension(action, extension, php_version) {\n    const csrfToken = document.querySelector('input[name=\"csrfmiddlewaretoken\"]').value;\n    const button = event.target;", "function manageExtension(action, extension, php_version, button) {\n    const csrfToken = document.querySelector('input[name=\"csrfmiddlewaretoken\"]').value;")
php_ext_tpl.write_text(tpl, encoding='utf-8')
PY

  python3 -m py_compile "$BASE_DIR/whm/views.py"
  python3 -m py_compile "$BASE_DIR/users/server_core.py"
}

case "$ACTION" in
  imunify)
    patch_imunify
    ;;
  webmail)
    patch_webmail
    ;;
  php-installers)
    patch_php_installers
    ;;
  all)
    patch_imunify
    patch_webmail
    patch_php_installers
    ;;
  *)
    echo "Usage: $0 {imunify|webmail|php-installers|all}"
    exit 1
    ;;
esac

systemctl restart cp || true
systemctl restart lsws || systemctl restart openlitespeed || true

echo "Hotfix action '$ACTION' applied successfully."
echo "Backups saved under: $BACKUP_DIR"
