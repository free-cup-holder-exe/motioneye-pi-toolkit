# Python 3.14 and forkserver: why cleanup stopped deleting old media

## Question

Upstream issue
[#3411](https://github.com/motioneye-project/motioneye/issues/3411):
"Automatic video delete does not work since 0.44". On the Home Assistant
add-on, motionEye's cleanup stopped deleting old movies. "Preserve Movies:
For one day" had no effect.

The same add-on update moved motionEye to 0.44.0 and Python from 3.12 to
3.14. So it looked like a 0.44.0 bug. An early guess was file permissions.

What really stopped cleanup?

## Setup

The fault was reproduced without Docker or Home Assistant:

- Python 3.14.7 and the motionEye 0.44.0 source.
- Settings loaded from a config file in a non-default directory. The add-on
  keeps its config in `/data/motioneye`, not the built-in default.
- A three-day-old movie planted in the media folder.
- motionEye's cleanup function run in a child process with
  `multiprocessing.Process`, the way the periodic cleanup does it.

The same run was repeated with the start method set to `fork`, with the fix
applied, and on Python 3.13.5.

## Data

| Run | Config path seen by the child | Cameras found | Old movie | Child's debug lines |
|---|---|---|---|---|
| Python 3.14.7, default start method | built-in default | 0 | kept | missing |
| Python 3.14.7, start method `fork` | the real config dir | 1 | deleted | present |
| Python 3.14.7, with the fix (#3416) | the real config dir | 1 | deleted | present |
| Python 3.13.5, default start method | the real config dir | 1 | deleted | present |

The broken run still exited with code 0. Nothing in the log showed a
failure.

## Result

**Cause.** Python 3.14 changed the default `multiprocessing` start method
on Linux from `fork` to `forkserver`.

- With `fork`, the child is a copy of the parent. It has the settings the
  parent read from the config file, and the parent's logging setup.
- With `forkserver`, the child comes from a clean helper process. Modules
  are imported fresh, so it only has their import-time defaults.

motionEye's cleanup child takes no arguments. It reads the config path from
the `settings` module. Under `forkserver` that was the built-in default, not
the add-on's path. The child looked there and found no `camera-N.conf`. So
it found zero cameras and deleted nothing. Its log lines were lost too:
logging was not set up in the child, so only warnings would have shown.

**Not permissions.** The child never reached the media files. With no
cameras it had nothing to delete.

The same cause had other effects (listed in the fix's PR):

- Zip downloads were written under the built-in default media path.
- Background task workers read their upload settings from the default
  config path.
- Every child process lost its log lines.

**Who is affected.** Any install on Python 3.14. Cleanup breaks when the
config path differs from the built-in default, as on the add-on. A stock
install with default paths still deletes, but its cleanup logs are lost.
Python 3.13 and earlier are not affected. motionEye's `cleanup.py` itself
had not changed since 2022.

**Fix.** [PR #3416](https://github.com/motioneye-project/motioneye/pull/3416)
sets the start method to `fork` once, first thing at startup. That restores
the behaviour every Linux install had on Python 3.13 and earlier. A new
test checks that a child sees the parent's config path and logging. It can
only fail on Python 3.14 and later.

**Status.** Merged into motionEye `dev` on 2026-09-14. It is not in 0.44.0.
It is planned for 0.45.0. See [Fixes contributed upstream](../upstream-fixes.md).

## The general lesson

Code that relies on `fork()` copying module state breaks under `forkserver`
or `spawn` (the default on macOS and Windows). It does not raise an error.
The child just runs with defaults.

A minimal example:

```python
import multiprocessing as mp

CONF_PATH = '/etc/app'            # import-time default

def child():
    print('child sees', CONF_PATH)

if __name__ == '__main__':
    CONF_PATH = '/srv/app/conf'   # set at startup, e.g. from a config file
    p = mp.Process(target=child)
    p.start()
    p.join()
```

On Linux with Python 3.13 this prints `/srv/app/conf`. With Python 3.14 it
prints `/etc/app`.

Signs to look for:

- A background job runs, exits 0, and does nothing.
- Its log lines are missing, even at debug level.
- It started after a Python upgrade, with no change to your code.

What to do:

1. **Check your default:**
   `python3 -c 'import multiprocessing as mp; print(mp.get_start_method())'`
   prints `fork` on Linux up to Python 3.13 and `forkserver` on 3.14.
2. **Quick fix:** pin the old start method early in `main()`, before any
   pool or process exists:
   `multiprocessing.set_start_method('fork', force=True)`. This is what
   #3416 does. `fork` is not available on Windows.
3. **Lasting fix:** make children independent of the start method. Pass
   what they need (config path, media path, log level) as arguments, or
   re-load settings and logging in the child. The #3416 PR lists this as
   the follow-up for motionEye.

## Caveats

- The cameras checked in this setup run Raspberry Pi OS 13 (trixie) with
  Python 3.13.5, so they were not affected. Check `python3 --version` before
  you move motionEye to a newer Python, for example in a venv.
- On 0.44.0 with Python 3.14 and a non-default config path, cleanup will
  not delete until you upgrade. Until 0.45.0 is out, run motionEye on
  Python 3.13 or earlier, or run `dev` (see the
  [canary testing guide](../howto/canary-testing-dev.md)).
- `fork` is a stopgap. motionEye's parent process has threads when it forks.
  Python 3.12 and later warn about that (the warning is hidden by default).
  Installs on Python 3.12 and 3.13 already run this way.
- The reproduction was a direct test of the cleanup function. It was not run
  inside the Home Assistant add-on itself.
