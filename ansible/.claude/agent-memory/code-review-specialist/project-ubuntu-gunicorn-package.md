---
name: ubuntu-gunicorn-package
description: On Ubuntu 22.04 the gunicorn APT package is named `gunicorn`, not `python3-gunicorn` — the latter does not exist in Jammy repos.
metadata:
  type: project
---

On Ubuntu 22.04 (Jammy), the correct APT package name for gunicorn is `gunicorn`.
The variant `python3-gunicorn` was dropped after Ubuntu 20.04.

**Why:** This caused a hard deployment failure in the `website` role (PR web-site) — the `apt` task aborted with "no candidate" and nothing else in the play ran.

**How to apply:** Any new role or task that installs gunicorn via APT on Ubuntu 22.04 must use `gunicorn`, not `python3-gunicorn`. Flag immediately as CRITICAL if the wrong name appears.
