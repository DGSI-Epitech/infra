---
name: nginx-no-tls-website-role
description: The `website` role's nginx config serves plain HTTP on port 80 with no TLS, violating the project's HTTPS-everywhere policy.
metadata:
  type: project
---

`roles/website/templates/nginx.conf.j2` only has a `listen 80` block — no HTTPS redirect, no `listen 443 ssl` block.

The `tls` role runs before `website` in `playbooks/web-vm.yml` and places a cert+key at `/etc/ssl/internal/`, so the material to fix this is already on the host.

**Why:** The project rule (services-state.md) mandates "HTTPS partout (CA interne)". This was flagged as a WARNING in the web-site branch review.

**How to apply:** Any new nginx config in this repo should include TLS termination using certs from `/etc/ssl/internal/`. Flag as WARNING if a new role deploys plain HTTP when the `tls` role is also present in the playbook.

Related: [[tls-key-permissions]]
