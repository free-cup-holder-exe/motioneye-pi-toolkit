# canary

Run motionEye's development branch (and your own pull requests) on one or two cameras before a release reaches the rest.

`canary-deploy.sh` installs a wheel from `/tmp` on the Pi it runs on: it backs up the installed package and `/etc/motioneye` to `/root/canary-backup-<time>/`, stops motionEye, installs the wheel with `pip --no-deps`, starts motionEye, waits for the web UI, re-runs `motioneye-notify-heal` if installed, and prints the version, the `main.js?v=` cache key and recent warnings.

```sh
# on the PC, from the motionEye checkout you want to test:
git switch -c canary origin/dev                      # always start fresh from dev
git merge origin/my-feature                          # optional: your open PR branches
# give the build its own version so browsers reload JS/CSS and nightly pip upgrades leave it alone:
sed -i 's/^VERSION = .*/VERSION = "0.45.0a1.dev2026100701"/' motioneye/__init__.py
git -c core.autocrlf=false -c core.eol=lf archive -o canary.tar HEAD
mkdir canary-build && tar -xf canary.tar -C canary-build
python3 -m pip wheel --no-deps -w canary-wheel canary-build
scp canary-wheel/motioneye-*.whl admin@cam:/tmp/
ssh admin@cam 'sudo bash -s' < canary-deploy.sh
```

`canary-event.sh` checks the alerts after a deploy: it waits until motion has captured a fresh snapshot, fires a test event through motion's web control, and prints the `result=` lines of [motioneye-notify](../motioneye-notify) for email and Telegram plus the count of sender errors. Run it as root on the Pi (`sudo bash canary-event.sh`, optionally with the camera number). Fire the event only after the first frame: before that, motion runs no event commands at all, and a test looks failed for no reason.

Rollback (on the Pi, with the folder it printed):

```sh
B=/root/canary-backup-20261007-212524
SP=$(python3 -c 'import motioneye, os; print(os.path.dirname(os.path.dirname(motioneye.__file__)))')
sudo systemctl stop motioneye
sudo rm -rf "$SP"/motioneye "$SP"/motioneye-*.dist-info
sudo tar -xzf $B/package.tgz -C "$SP"
sudo tar -xzf $B/etc-motioneye.tgz -C /etc
sudo systemctl start motioneye
```

Notes:

- Build the wheel on a PC, not on the Pi: building from source on Raspberry Pi OS failed here because the system has no setuptools for pip's build backend, and installing it system-wide is not worth it.
- Always rebuild the canary branch from a fresh `dev` plus your branches. Merging an updated PR branch into an old canary once produced a silent bad merge (a call duplicated).
- A version like `0.45.0a1.dev…` sorts below `0.45.0a1`, and `pip install --upgrade` without `--pre` ignores pre-releases, so a nightly upgrade does not replace the canary until a newer stable release exists.

Guide: [docs/howto/canary-testing-dev.md](../../docs/howto/canary-testing-dev.md).
