# Run motionEye's dev branch on a canary camera

## What it does

One or two cameras run motionEye's `dev` branch, plus your own open pull requests, all the time. They catch problems before a release reaches the other cameras. In our setup the canaries are cam-a and cam-c. The rest run the PyPI release.

You build a wheel on a PC, copy it to the camera, and install it with `tools/canary/canary-deploy.sh`. The script backs up the installed package and `/etc/motioneye` first, so rollback is a restore.

## Requirements

- A PC with git and Python 3 with pip. The commands below are for a bash shell (Git Bash works on Windows).
- A camera with motionEye installed with pip, either in the system Python or in a venv under `/opt/motioneye`. `canary-deploy.sh` detects which and adds `--break-system-packages` only for the system Python.
- ssh and scp to the camera as an admin user with sudo.
- Useful: [alert logging](log-notification-outcomes.md) and [health checks](health-checks.md).

Do not build on the Pi. We tried, and it failed: the system Python has no setuptools. Keep build tools off the camera. The wheel is pure Python, so building elsewhere is fine.

## Install

### 1. Make a fresh canary branch

Start from a fresh copy of `dev` every time. Then merge each of your open PR branches (here they live on a remote called `fork`):

```sh
git fetch origin && git fetch fork
git switch -C canary origin/dev
git merge --no-edit fork/<pr-branch>      # once per open PR
git diff --stat origin/dev                # only the files your PRs change
```

Never merge an updated PR branch into an old canary branch. We did that once. The merge silently duplicated a call (a startup migration ran twice) and also hit a conflict. Only checking the diff caught it.

With no open PRs, the canary is just `dev`.

### 2. Give it a dev version

Set `VERSION` in `motioneye/__init__.py` to dev's version plus `.devYYYYMMDDNN`, for example `0.45.0a1.dev2026100701`. Commit it on the canary branch only. Never push this branch.

```sh
git commit -am "canary: version 0.45.0a1.dev2026100701"
```

Why:

- motionEye adds `?v=<version>` to its CSS and JavaScript URLs. A new version makes browsers load the new files instead of cached ones.
- It is a PEP 440 pre-release. The nightly `pip install --upgrade` (without `--pre`) leaves it alone until a newer final release ships. See [Nightly updates](nightly-updates.md).

### 3. Build a wheel with LF line endings

On a Windows checkout with `core.autocrlf=true`, files get CRLF line endings, and shell scripts inside the package then fail on the Pi. Export with LF:

```sh
rm -rf canary-build canary-wheel && mkdir canary-build
git -c core.autocrlf=false -c core.eol=lf archive --format=tar HEAD | tar -x -C canary-build
grep -rlI $'\r' canary-build | wc -l       # expect 0
python -m pip wheel --no-deps -w canary-wheel ./canary-build
```

You get one pure-Python wheel, `motioneye-<version>-py3-none-any.whl`. Built on Windows, its METADATA file may have CRLF endings. That is harmless.

### 4. Copy and install

```sh
scp canary-wheel/motioneye-*.whl admin@cam-a:/tmp/
ssh admin@cam-a 'sudo bash -s' < tools/canary/canary-deploy.sh
```

The script:

1. stops right away if there is no `motioneye-*.whl` in `/tmp`,
2. backs up the installed package (`motioneye/` and its `.dist-info`) and `/etc/motioneye` to `/root/canary-backup-<timestamp>/`, and stops if the backup failed,
3. stops motionEye, runs `pip install --no-deps` on the wheel (with `--break-system-packages` for the system Python), and starts motionEye,
4. waits for the web UI,
5. runs `motioneye-notify-heal` if installed (a new version may rewrite `on_event_start` on first start),
6. prints the version, the `main.js?v=` cache key and the last minutes of motionEye's warnings,
7. deletes the wheel from `/tmp`.

`--no-deps` leaves the installed dependencies alone. If dev adds or raises a dependency, install it separately.

## Check it works

- The web UI answers 200, exactly one motion process runs, and the new version shows.
- No new errors: `sudo journalctl -u motioneye --since "-10 min" | grep -iE 'error|warning|traceback'`. With the [bridge](csi-camera-mjpeg-bridge.md), one `motion_init: Error capturing first image` per motion start is normal.
- Alerts: wait for the first frame, then fire a test event and read the result: `sudo bash canary-event.sh` from [`tools/canary`](../../tools/canary) does both ([how it reads the result](log-notification-outcomes.md#check-it-works)). Expect `result=sent` on each channel. An event fired before motion has captured its first frame after the restart never runs the event commands, so nothing is sent and nothing is logged; that looks like a broken build and isn't. The script waits for a fresh snapshot first.
- UI: open it in a browser and reload without the cache. If images or layout are missing, open the browser console and look for "Refused to". dev sends a Content-Security-Policy header (#3435), and a blocked resource shows up there. Check the header with `curl -s -D - -o /dev/null http://127.0.0.1:8765/ | grep -i content-security-policy`.
- The next morning, and daily after that, run the [health check](health-checks.md).

### Refreshing the canary

Rebuild whenever dev or one of your PR branches changes, always from step 1. Redeploy only when the code differs from what is installed. Compare without the version commits:

```sh
git diff --stat <previous-canary-commit>~1 canary~1     # empty: nothing to deploy
```

## Undo (rollback)

Restore the backup the script made (use `/opt/motioneye/bin/python` instead of `python3` for a venv install):

```sh
B=/root/canary-backup-<timestamp>
SP=$(python3 -c 'import motioneye, os; print(os.path.dirname(os.path.dirname(motioneye.__file__)))')
sudo systemctl stop motioneye
sudo rm -rf "$SP/motioneye" "$SP"/motioneye-*.dist-info
sudo tar -xzf "$B/package.tgz" -C "$SP"
sudo tar -xzf "$B/etc-motioneye.tgz" -C /etc
sudo systemctl start motioneye
```

Restore `/etc/motioneye` too, not just the package. A newer version may migrate the config on first start (dev moves notification secrets into config keys), and an older motionEye cannot read that. Settings changed since the backup are lost.
