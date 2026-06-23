# Network & Security Testing Guide

This document provides a step-by-step guide to execute the network and security test suite.

## Quick Start

### Prerequisites
1. **SSH Access**: Ensure SSH keys are configured for pfSense-OP (`192.168.255.254`)
2. **nmap**: Install on test host (`apt-get install nmap` or `choco install nmap`)
3. **CA Certificate**: Retrieve `~/.ansible-tls/ca.crt` for HTTPS testing
4. **Workspace**: Clone the infra repo and navigate to the workspace root

### Run All Tests
```bash
cd /path/to/infra
bash scripts/run_network_security_tests.sh all
```

### Run Specific Test
```bash
# VPN connectivity only
bash scripts/run_network_security_tests.sh vpn_connectivity

# Firewall nmap only
bash scripts/run_network_security_tests.sh firewall_nmap
```

---

## Test Execution Phases

### Phase 1: Pre-flight Checks
```bash
# 1. Verify SSH access to pfSense-OP (jump host)
ssh admin@192.168.255.254 "echo 'SSH OK'"

# 2. Verify SSH to ops-vm via ProxyJump
ssh -J admin@192.168.255.254 ubuntu@172.16.0.253 "echo 'SSH OK'"

# 3. Verify ops-vm has connectivity to web-vm
ssh -J admin@192.168.255.254 ubuntu@172.16.0.253 "ping -c 1 192.168.255.243"

# 4. Check nmap is installed locally
nmap --version
```

**Expected Results**:
- All SSH connections succeed
- Ping returns 0% packet loss
- nmap version prints

---

### Phase 2: Automated Tests (Script Execution)

#### Run the test suite
```bash
bash scripts/run_network_security_tests.sh all

# Or run individual tests:
bash scripts/run_network_security_tests.sh vpn_connectivity
bash scripts/run_network_security_tests.sh dns_resolution
bash scripts/run_network_security_tests.sh firewall_nmap
```

**Output**: Results saved to `test_results/test_results_YYYYMMDD_HHMMSS.txt`

#### Review Results
```bash
cat test_results/test_results_*.txt

# Latest results
cat test_results/test_results_$(ls -t test_results | head -1)
```

---

### Phase 3: Manual Tests (Kill Switch, Teleport)

#### 3a. Kill Switch Test
Follow the steps in [NETWORK_SECURITY_TESTS.md § 2](./NETWORK_SECURITY_TESTS.md#2-kill-switch-activation--deactivation--recovery)

1. **Baseline**: Ping ops-vm → web-vm (expect success)
   ```bash
   ssh -J admin@192.168.255.254 ubuntu@172.16.0.253 "ping -c 10 192.168.255.243"
   ```

2. **Disable VPN**: Access pfSense-OP UI or CLI
   ```bash
   ssh admin@192.168.255.254
   # Menu: Status > IPsec > Disable Tunnel
   # Or CLI: ipsecctl -D
   ```

3. **Verify Outage**: Ping should fail or timeout
   ```bash
   ssh -J admin@192.168.255.254 ubuntu@172.16.0.253 "ping -c 10 192.168.255.243"
   # Expected: 100% packet loss or timeout
   ```

4. **Re-enable VPN**: pfSense-OP UI or CLI
   ```bash
   ssh admin@192.168.255.254
   # Menu: Status > IPsec > Enable Tunnel
   # Or CLI: ipsecctl -f
   sleep 5
   ```

5. **Verify Recovery**: Ping should succeed again
   ```bash
   ssh -J admin@192.168.255.254 ubuntu@172.16.0.253 "ping -c 10 192.168.255.243"
   # Expected: 0% packet loss
   ```

6. **Document Results**: Record recovery time and any observations

#### 3b. Teleport Access Test
Follow the steps in [NETWORK_SECURITY_TESTS.md § 3](./NETWORK_SECURITY_TESTS.md#3-teleport-access-ssh--web-console)

1. **Check Teleport Service**: On bastion
   ```bash
   ssh -J admin@192.168.255.254 ubuntu@10.255.255.249 "systemctl status teleport"
   ```

2. **If Running**: Setup SSH tunnel
   ```bash
   # Terminal 1: Create tunnel
   ssh -J admin@192.168.255.254 -L 3080:10.255.255.249:3080 ubuntu@10.255.255.249
   
   # Terminal 2: Open browser
   open https://localhost:3080  # or firefox, chrome, etc.
   ```

3. **If Not Running**: Document for deployment task
   - Add issue to [NETWORK_SECURITY_TESTS.md § 6](./NETWORK_SECURITY_TESTS.md#6-document-issues-found)
   - Create task: "Deploy Teleport to bastion"

---

### Phase 4: Document Issues

For each failure or finding, add an entry to [NETWORK_SECURITY_TESTS.md § 6](./NETWORK_SECURITY_TESTS.md#6-document-issues-found):

```markdown
### Issue #<N> : <Title>

**Severité** : Critical | High | Medium | Low
**Composant** : [VPN | Firewall | DNS | Teleport | Architecture]
**Description** : [What happened]
**Impact** : [Why it matters]
**Mitigation** : [How to fix]
**Status** : [ ] Open | [x] Fixed | [ ] Blocked
```

Example:
```markdown
### Issue #1 : DNS resolution fails for web.internal from ops-vm

**Severité** : High
**Composant** : DNS
**Description** : nslookup web.internal from ops-vm returns NXDOMAIN
**Impact** : Can't reach web-vm via hostname (only IP works)
**Mitigation** : Add forward zone in pfSense-OP Unbound config
**Status** : [ ] Open
```

---

## Results Interpretation

### VPN Connectivity Test
| Status | Meaning | Action |
|--------|---------|--------|
| `PASS` | Ping 0% loss | No action needed |
| `FAIL` | Packet loss >0% | Check IPsec tunnel health, firewall rules |
| `FAIL` | SSH timeout | Verify SSH credentials, ProxyJump configuration |

### Firewall Test (nmap)
| Port | Expected | Meaning | Action if Different |
|------|----------|---------|----------------------|
| 22 | open | SSH allowed inter-site | Verify firewall rules |
| 443 | open | HTTPS allowed | Verify firewall rules |
| 8200 | open | Vault inter-site | Verify firewall rules |
| 9200 | open | Elasticsearch inter-site | Verify firewall rules |
| 5044 | closed/filtered | Logstash discontinued | Expected (no action) |

### DNS Resolution Test
| Test | Expected | Meaning | Action if Different |
|------|----------|---------|----------------------|
| `vault.internal` | 172.16.0.253 | Resolves to ops-vm | Add record in Unbound |
| `kibana.internal` | 10.255.255.249 | Resolves to bastion | Add record in Unbound |
| `web.internal` | 192.168.255.243 | Resolves cross-site | Add forward zone in pfSense |

---

## Troubleshooting

### SSH ProxyJump Fails
```bash
# Test jump host directly
ssh -v admin@192.168.255.254

# Test with explicit key
ssh -i ~/.ssh/infra_key admin@192.168.255.254

# Check key permissions
ls -la ~/.ssh/infra_key*
# Expected: 600 (rw-------)

# If key not authorized on pfSense, use web UI:
# Proxmox Console → pfSense SSH → Diagnostics → SSH
```

### Ping Timeout or No Route
```bash
# Check VPN tunnel status on pfSense-OP
ssh admin@192.168.255.254
# Status > IPsec > Active Tunnel (should show green)

# If tunnel is down, check logs
tail -f /var/log/charon.log

# Restart IPsec
# Status > IPsec > Disable → Enable
```

### DNS Resolution NXDOMAIN
```bash
# Check pfSense Unbound config
ssh admin@192.168.255.254
# Services > DNS > Resolver > Forward Zones

# Test nameserver directly
nslookup vault.internal 172.16.0.1

# If fails, add record:
# Services > DNS > Resolver > Custom Options
# → add host override or forward zone
```

### nmap Not Found Locally
```bash
# Install nmap
# macOS
brew install nmap

# Linux
sudo apt-get install nmap

# Windows
choco install nmap

# Verify
nmap --version
```

---

## Integration with CI/CD

### GitHub Actions Workflow
See `.github/workflows/network-tests.yml` (if created):
```yaml
name: Network Security Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run network tests
        run: bash scripts/run_network_security_tests.sh all
      - name: Upload results
        uses: actions/upload-artifact@v3
        with:
          name: test-results
          path: test_results/
```

---

## Next Steps

1. **Execute all tests** using `run_network_security_tests.sh all`
2. **Review results** in `test_results/test_results_*.txt`
3. **Document issues** in [NETWORK_SECURITY_TESTS.md § 6](./NETWORK_SECURITY_TESTS.md#6-document-issues-found)
4. **Create tasks** for each issue (Ansible playbooks, Terraform changes)
5. **Re-test** after fixes
6. **Create PR** with results and fixes

---

## References

- [Test Plan](./NETWORK_SECURITY_TESTS.md)
- [Configuration Reference](./NETWORK_SECURITY_TESTS_CONFIG.md)
- [Services State](./SERVICES_STATE.md)
- [Architecture](./ARCHITECTURE.md)
- [Runbooks](./RUNBOOKS.md)

