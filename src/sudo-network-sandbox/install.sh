#!/bin/bash

cat << EOF > /etc/dnsmasq.conf
listen-address=127.0.0.1
log-queries
log-facility=/var/log/dnsmasq.log
server=1.1.1.1
ipset=/captive.apple.com/allowed-domains
ipset=/${ALLOWEDDOMAINS//,//}/allowed-domains
EOF

cat << 'EOF' >> /usr/local/bin/init-firewall.sh
#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, and pipeline failures
IFS=$'\n\t'       # Stricter word splitting

# Reject any arguments for security
if [ $# -ne 0 ]; then
    echo "Error: This script does not accept arguments"
    exit 1
fi

# Update container's resolv.conf to use local dnsmasq
echo "nameserver 127.0.0.1" > /etc/resolv.conf

wait_for_dnsmasq() {
    local timeout=20
    local count=0

    echo "Waiting for dnsmasq DNS to be functional..."

    while [ $count -lt $timeout ]; do
        # Try to resolve a test domain through dnsmasq
        if dig @127.0.0.1 +time=1 +tries=1 captive.apple.com > /dev/null 2>&1; then
            echo "✓ dnsmasq DNS is functional"
            return 0
        fi

        sleep 1
        count=$((count + 1))
    done

    echo "✗ Timeout waiting for dnsmasq DNS"
    return 1
}



# 1. Extract Docker DNS info BEFORE any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

ipset create allowed-domains hash:ip -exist

# 2. Selectively restore ONLY internal Docker DNS resolution
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# First allow DNS and localhost before any restrictions
# Allow outbound DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
# Allow inbound DNS responses
iptables -A INPUT -p udp --sport 53 -j ACCEPT
# Allow outbound SSH
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
# Allow inbound SSH responses
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
# Allow localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Get host IP from default route
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi

HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network detected as: $HOST_NETWORK"

# Set up remaining iptables rules
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# Set default policies to DROP first
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# First allow established connections for already approved traffic
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Then allow only specific outbound traffic to allowed domains
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Explicitly REJECT all other outbound traffic for immediate feedback
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited


# Start dnsmasq
dnsmasq || {
    echo "Failed to start dnsmasq"
    exit 1
}

# Wait for it to be ready
if ! wait_for_dnsmasq; then
    echo "Aborting due to dnsmasq failure"
    exit 1
fi

echo "Firewall configuration complete"
echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
else
    echo "Firewall verification passed - unable to reach https://example.com as expected"
fi

# We always allow captive.apple.com for testing/verification
if ! curl --connect-timeout 5 https://captive.apple.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - unable to reach https://captive.apple.com"
    exit 1
else
    echo "Firewall verification passed - able to reach https://captive.apple.com as expected"
fi

EOF

chown root:root /usr/local/bin
chmod 755 /usr/local/bin
chmod 750 /usr/local/bin/init-firewall.sh
cat << EOF > /etc/sudoers.d/zzzzzz-99-firewall-lockdown
# SECURITY LOCKDOWN - This file must load last
# Overrides all previous sudo grants

# Preserve root access
root ALL=(ALL:ALL) ALL

# Define dangerous commands
Cmnd_Alias FIREWALL_TOOLS = /sbin/iptables*, /usr/sbin/iptables*, /sbin/ip6tables*, /usr/sbin/ip6tables*, /sbin/ipset*, /usr/sbin/ipset*
Cmnd_Alias SHELLS = /bin/sh, /bin/bash, /bin/zsh, /bin/fish, /bin/dash, /usr/bin/fish
Cmnd_Alias EDITORS = /usr/bin/vim, /usr/bin/vi, /usr/bin/nano, /usr/bin/emacs, /usr/bin/ed
Cmnd_Alias DANGEROUS = FIREWALL_TOOLS, SHELLS, EDITORS

# First: explicitly deny dangerous commands (this overrides previous grants)
ALL ALL=(ALL) !DANGEROUS

# Second: revoke all other commands
ALL ALL=(ALL) !ALL

# Third: grant ONLY to start the firewall
ALL ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh

# Log all denied attempts
Defaults    logfile="/var/log/sudo-denied.log"
Defaults    log_denied
EOF

chmod 0440 /etc/sudoers.d/zzzzzz-99-firewall-lockdown
echo "#includedir /etc/sudoers.d" > /etc/sudoers
