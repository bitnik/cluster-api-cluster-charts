#!/bin/bash
# Ref: https://github.com/anthropics/claude-code/blob/main/.devcontainer/init-firewall.sh
set -euo pipefail  # Exit on error, undefined vars, and pipeline failures
IFS=$'\n\t'       # Stricter word splitting

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

# Reset policies to ACCEPT right after the flush.
# Without it, any in-place re-run (or a botched restart) starts with leftover DROP,
# and the GitHub fetch below silently dies.
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD ACCEPT

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
# iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
# Allow inbound SSH responses
# iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
# Allow localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Create the allow-list as an ipset.
# An ipset is a kernel-side hash of many IPs/CIDRs that ONE iptables rule can match against (the --match-set rule near the end),
# instead of appending one iptables rule per address.
# Far faster to evaluate and updatable without touching the rules.
# hash:net stores CIDR networks; a bare IP is stored as /32.
ipset create allowed-domains hash:net
# ipset list allowed-domains

# Fetch GitHub meta information and aggregate + add their IP ranges
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta)
if [ -z "$gh_ranges" ]; then
    echo "ERROR: Failed to fetch GitHub IP ranges"
    exit 1
fi

if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    echo "ERROR: GitHub API response missing required fields"
    exit 1
fi

echo "Processing GitHub IPs..."
# `grep -v ':'` drops any IPv6 CIDRs from the feed before the IPv4-only regex/aggregate,
# so a future IPv6 range in /meta can't trip the validation and abort the script.
# (IPv6 is fully denied below, so we intentionally do not allow-list v6 ranges.)
while read -r cidr; do
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "ERROR: Invalid CIDR range from GitHub meta: $cidr"
        exit 1
    fi
    echo "Adding GitHub range $cidr"
    # ipset add allowed-domains "$cidr"
    ipset -exist add allowed-domains "$cidr"
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | grep -v ':' | aggregate -q)
# ipset list allowed-domains

# Resolve and add other allowed domains
# "sentry.io" \
# "statsig.anthropic.com" \
# "statsig.com" \
# "marketplace.visualstudio.com" \
# "vscode.blob.core.windows.net" \
# "update.code.visualstudio.com" \
# WARNING: Several domains below are CDN-fronted (npm -> Cloudflare, pypi/pythonhosted ->Fastly)
# and share rotating IP pools. This snapshot goes stale and may cause intermittent failures.
for domain in \
    "registry.npmjs.org" \
    "api.anthropic.com" \
    "pypi.org" \
    "files.pythonhosted.org" \
    "ghcr.io" ; do
    echo "Resolving $domain..."
    ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
    if [ -z "$ips" ]; then
        echo "ERROR: Failed to resolve $domain"
        exit 1
    fi

    while read -r ip; do
        if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "ERROR: Invalid IP from DNS for $domain: $ip"
            exit 1
        fi
        echo "Adding $ip for $domain"
        # ipset add allowed-domains "$ip"
        ipset -exist add allowed-domains "$ip"
    done < <(echo "$ips")
done

# Get host IP from default route
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi

# Allow the container to reach the Docker host network: the bridge gateway and any
# sibling containers on that subnet (host-side services, port-forwarding, the editor's
# dev-container server). NOTE: this derives a /24 from the gateway IP via sed, ignoring
# the real netmask — fine here because the gateway sits inside that /24.
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
# Allow return traffic for connections we initiated.
# Once an outbound packet is accepted (DNS, an allowed-domain IP, the host net),
# conntrack tracks the flow and marks the reply packets ESTABLISHED/RELATED,
# so responses come back in without a per-service inbound rule.
# This stateful match is what makes the allow-list actually usable.
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Then allow only specific outbound traffic to allowed domains
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Explicitly REJECT all other outbound traffic for immediate feedback
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# --- IPv6: default-deny everything ----------------------------------------------------
# This script builds an IPv4-only allow-list, so any IPv6 route would bypass it entirely.
# Lock IPv6 down to loopback only and DROP the rest.
if command -v ip6tables >/dev/null 2>&1; then
    echo "Locking down IPv6 (default-deny)..."
    ip6tables -F 2>/dev/null || true
    ip6tables -X 2>/dev/null || true
    ip6tables -A INPUT  -i lo -j ACCEPT 2>/dev/null || true
    ip6tables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true
    ip6tables -P INPUT   DROP 2>/dev/null || true
    ip6tables -P FORWARD DROP 2>/dev/null || true
    ip6tables -P OUTPUT  DROP 2>/dev/null || true
else
    echo "ip6tables not available — skipping IPv6 lockdown"
fi
# --------------------------------------------------------------------------------------

echo "Firewall configuration complete"
echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
else
    echo "Firewall verification passed - unable to reach https://example.com as expected"
fi

# Verify GitHub API access
if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - unable to reach https://api.github.com"
    exit 1
else
    echo "Firewall verification passed - able to reach https://api.github.com as expected"
fi
