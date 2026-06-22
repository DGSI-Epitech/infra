#!/bin/bash

# Test Runner : Network & Security Tests
# Usage: ./run_network_security_tests.sh [test_name] [--verbose]
# 
# Available tests:
#   vpn_connectivity    - Test VPN connectivity S1 <-> S2
#   kill_switch         - Test kill switch activation/deactivation
#   teleport            - Test Teleport SSH + web console access
#   dns_resolution      - Test DNS resolution cross-site
#   firewall_nmap       - Test firewall with nmap port scans
#   all                 - Run all tests

set -e

# Configuration
PFSENSE_OP="5.196.45.8"
OPS_VM="172.16.0.253"
BASTION="10.255.255.249"
WEB_VM="192.168.255.243"
SERVICES_VM="172.16.0.241"

VERBOSE=${2:-0}
TEST_NAME=${1:-"all"}
RESULTS_DIR="./test_results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULTS_FILE="$RESULTS_DIR/test_results_$TIMESTAMP.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

log_test_result() {
  local test_name=$1
  local status=$2
  local message=$3
  
  echo "[$test_name] $status: $message" >> "$RESULTS_FILE"
  
  if [ "$status" == "PASS" ]; then
    log_info "$test_name: PASS"
  else
    log_error "$test_name: FAIL - $message"
  fi
}

# Setup
setup() {
  mkdir -p "$RESULTS_DIR"
  echo "Test Execution Report" > "$RESULTS_FILE"
  echo "=====================" >> "$RESULTS_FILE"
  echo "Timestamp: $(date)" >> "$RESULTS_FILE"
  echo "Hostname: $(hostname)" >> "$RESULTS_FILE"
  echo "" >> "$RESULTS_FILE"
  log_info "Test environment prepared. Results: $RESULTS_FILE"
}

# Test 1: VPN Connectivity
test_vpn_connectivity() {
  log_info "Running VPN Connectivity tests..."
  
  # Test 1.1: ops-vm -> web-vm
  log_info "Test 1.1: ops-vm (172.16.0.253) -> web-vm (192.168.255.243)"
  if timeout 10 ssh -o ConnectTimeout=5 -J admin@$PFSENSE_OP ubuntu@$OPS_VM \
    "ping -c 4 $WEB_VM" > /tmp/test_1_1.txt 2>&1; then
    
    LOSS=$(grep -oP '(\d+)(?=% packet loss)' /tmp/test_1_1.txt || echo "100")
    if [ "$LOSS" == "0" ]; then
      log_test_result "VPN_1.1" "PASS" "ops-vm -> web-vm (0% loss)"
      echo "ops-vm -> web-vm: $(cat /tmp/test_1_1.txt | tail -1)" >> "$RESULTS_FILE"
    else
      log_test_result "VPN_1.1" "FAIL" "Packet loss: ${LOSS}%"
    fi
  else
    log_test_result "VPN_1.1" "FAIL" "SSH connection timeout or failed"
  fi
  
  # Test 1.2: bastion -> services-vm
  log_info "Test 1.2: bastion (10.255.255.249) -> services-vm (172.16.0.241)"
  if timeout 10 ssh -o ConnectTimeout=5 -J admin@$PFSENSE_OP ubuntu@$BASTION \
    "ping -c 4 $SERVICES_VM" > /tmp/test_1_2.txt 2>&1; then
    
    LOSS=$(grep -oP '(\d+)(?=% packet loss)' /tmp/test_1_2.txt || echo "100")
    if [ "$LOSS" == "0" ]; then
      log_test_result "VPN_1.2" "PASS" "bastion -> services-vm (0% loss)"
      echo "bastion -> services-vm: $(cat /tmp/test_1_2.txt | tail -1)" >> "$RESULTS_FILE"
    else
      log_test_result "VPN_1.2" "FAIL" "Packet loss: ${LOSS}%"
    fi
  else
    log_test_result "VPN_1.2" "FAIL" "SSH connection timeout or failed"
  fi
}

# Test 2: Kill Switch (simplified - verification only)
test_kill_switch() {
  log_info "Running Kill Switch tests..."
  log_warn "Kill switch tests require manual intervention. Documenting verification steps..."
  
  echo "" >> "$RESULTS_FILE"
  echo "=== Kill Switch Manual Test ===" >> "$RESULTS_FILE"
  echo "1. Baseline: ping ops-vm -> web-vm (should succeed)" >> "$RESULTS_FILE"
  echo "2. Disable IPsec tunnel on pfSense-OP (Status > IPsec)" >> "$RESULTS_FILE"
  echo "3. Re-test ping (should timeout or fail)" >> "$RESULTS_FILE"
  echo "4. Re-enable IPsec tunnel" >> "$RESULTS_FILE"
  echo "5. Verify ping succeeds again" >> "$RESULTS_FILE"
  echo "Expected recovery time: < 10 seconds" >> "$RESULTS_FILE"
  
  log_test_result "KILL_SWITCH" "MANUAL" "See test results file for manual steps"
}

# Test 3: Teleport Access
test_teleport() {
  log_info "Running Teleport access tests..."
  
  # Check if Teleport is installed on bastion
  log_info "Test 3.1: Check Teleport daemon on bastion"
  if ssh -o ConnectTimeout=5 -J admin@$PFSENSE_OP ubuntu@$BASTION \
    "systemctl is-active teleport" > /tmp/test_3_1.txt 2>&1; then
    
    if grep -q "active" /tmp/test_3_1.txt; then
      log_test_result "TELEPORT_3.1" "PASS" "Teleport daemon is active"
    else
      log_test_result "TELEPORT_3.1" "FAIL" "Teleport daemon is not active"
    fi
  else
    log_test_result "TELEPORT_3.1" "FAIL" "Cannot check Teleport status"
  fi
  
  # Document web console access steps
  echo "" >> "$RESULTS_FILE"
  echo "=== Teleport Web Console Manual Test ===" >> "$RESULTS_FILE"
  echo "1. SSH tunnel to bastion Teleport proxy:" >> "$RESULTS_FILE"
  echo "   ssh -J admin@$PFSENSE_OP -L 3080:$BASTION:3080 ubuntu@$BASTION" >> "$RESULTS_FILE"
  echo "2. Open browser: https://localhost:3080" >> "$RESULTS_FILE"
  echo "3. Login and verify access to SSH and web apps" >> "$RESULTS_FILE"
  
  log_test_result "TELEPORT_3.2" "MANUAL" "Web console access documented"
}

# Test 4: DNS Resolution
test_dns_resolution() {
  log_info "Running DNS Resolution tests..."
  
  # Test 4.1: DNS from ops-vm
  log_info "Test 4.1: DNS resolution from ops-vm"
  if timeout 5 ssh -o ConnectTimeout=5 -J admin@$PFSENSE_OP ubuntu@$OPS_VM \
    "nslookup vault.internal 2>&1" > /tmp/test_4_1.txt 2>&1; then
    
    if grep -q "Name: vault.internal" /tmp/test_4_1.txt || grep -q "172.16.0.253" /tmp/test_4_1.txt; then
      log_test_result "DNS_4.1" "PASS" "vault.internal resolves"
      grep "Address:" /tmp/test_4_1.txt >> "$RESULTS_FILE" 2>/dev/null || true
    else
      log_test_result "DNS_4.1" "FAIL" "vault.internal did not resolve"
    fi
  else
    log_test_result "DNS_4.1" "FAIL" "Cannot execute nslookup on ops-vm"
  fi
  
  # Test 4.2: DNS from bastion (cross-site)
  log_info "Test 4.2: DNS resolution from bastion (cross-site)"
  if timeout 5 ssh -o ConnectTimeout=5 -J admin@$PFSENSE_OP ubuntu@$BASTION \
    "nslookup vault.internal 2>&1" > /tmp/test_4_2.txt 2>&1; then
    
    if grep -q "Name: vault.internal" /tmp/test_4_2.txt || grep -q "172.16.0.253" /tmp/test_4_2.txt; then
      log_test_result "DNS_4.2" "PASS" "Cross-site DNS: vault.internal from bastion resolves"
      grep "Address:" /tmp/test_4_2.txt >> "$RESULTS_FILE" 2>/dev/null || true
    else
      log_test_result "DNS_4.2" "FAIL" "Cross-site DNS failed"
    fi
  else
    log_test_result "DNS_4.2" "FAIL" "Cannot execute nslookup on bastion"
  fi
}

# Test 5: Firewall Port Scans (nmap)
test_firewall_nmap() {
  log_info "Running Firewall nmap tests..."
  
  # Check if nmap is installed
  if ! command -v nmap &> /dev/null; then
    log_warn "nmap not installed. Installing..."
    if command -v apt-get &> /dev/null; then
      sudo apt-get install -y nmap
    elif command -v choco &> /dev/null; then
      choco install -y nmap
    else
      log_error "Cannot install nmap. Skipping firewall tests."
      log_test_result "FIREWALL_5.0" "SKIP" "nmap not available"
      return
    fi
  fi
  
  # Test 5.1: Scan ops-vm from bastion
  log_info "Test 5.1: Firewall scan - bastion -> ops-vm"
  if timeout 10 ssh -o ConnectTimeout=5 -J admin@$PFSENSE_OP ubuntu@$BASTION \
    "nmap -p 22,443,8200,9200 $OPS_VM" > /tmp/test_5_1.txt 2>&1; then
    
    OPEN_PORTS=$(grep -c "open" /tmp/test_5_1.txt || echo "0")
    log_test_result "FIREWALL_5.1" "PASS" "Scan completed. Open ports: $OPEN_PORTS"
    grep "open\|closed\|filtered" /tmp/test_5_1.txt >> "$RESULTS_FILE"
  else
    log_test_result "FIREWALL_5.1" "FAIL" "nmap scan failed"
  fi
  
  # Test 5.2: Verify blocked port (Logstash 5044)
  log_info "Test 5.2: Verify blocked port (5044 - Logstash)"
  if timeout 10 ssh -o ConnectTimeout=5 -J admin@$PFSENSE_OP ubuntu@$OPS_VM \
    "nmap -p 5044 localhost" > /tmp/test_5_2.txt 2>&1; then
    
    if grep -q "closed\|filtered" /tmp/test_5_2.txt; then
      log_test_result "FIREWALL_5.2" "PASS" "Port 5044 is properly blocked"
    else
      log_test_result "FIREWALL_5.2" "FAIL" "Port 5044 is open (should be blocked)"
    fi
  else
    log_test_result "FIREWALL_5.2" "FAIL" "Cannot verify port 5044"
  fi
}

# Generate summary
generate_summary() {
  log_info "Generating test summary..."
  
  echo "" >> "$RESULTS_FILE"
  echo "=== Test Summary ===" >> "$RESULTS_FILE"
  echo "Results stored in: $RESULTS_FILE" >> "$RESULTS_FILE"
  echo "Review the file for detailed results and manual test steps." >> "$RESULTS_FILE"
  
  log_info "Test execution completed!"
  log_info "Results saved to: $RESULTS_FILE"
  cat "$RESULTS_FILE"
}

# Main execution
main() {
  setup
  
  case "$TEST_NAME" in
    vpn_connectivity)
      test_vpn_connectivity
      ;;
    kill_switch)
      test_kill_switch
      ;;
    teleport)
      test_teleport
      ;;
    dns_resolution)
      test_dns_resolution
      ;;
    firewall_nmap)
      test_firewall_nmap
      ;;
    all)
      test_vpn_connectivity
      test_kill_switch
      test_teleport
      test_dns_resolution
      test_firewall_nmap
      ;;
    *)
      log_error "Unknown test: $TEST_NAME"
      echo "Available tests: vpn_connectivity, kill_switch, teleport, dns_resolution, firewall_nmap, all"
      exit 1
      ;;
  esac
  
  generate_summary
}

main
