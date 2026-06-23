---
name: tls-key-permissions
description: The `tls` role deploys server private keys with mode 0644 (world-readable) — a pre-existing issue that is activated on each new VM the role targets.
metadata:
  type: project
---

The `roles/tls/tasks/main.yml` "Deploy server key" task uses `mode: '0644'`, making the private key readable by every user on any VM where the `tls` role runs.

**Why:** Discovered during review of `web-vm.yml` (branch web-site). The `website` role does not use TLS directly, but the key lands on the host world-readable as a side-effect of the `tls` role running first.

**How to apply:** Flag as WARNING whenever a new playbook adds the `tls` role. The fix is `mode: '0640'` with `owner: root` and an appropriate group. Also note that the `tls` role is referenced in `playbooks/web-vm.yml` but nginx in the `website` role currently serves plain HTTP — the cert+key are deployed but unused, which also violates the project's HTTPS-everywhere policy.

Related: [[nginx-no-tls-website-role]]
