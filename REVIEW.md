# Repository Review

## Scope
This review covers the current repository state for WireGuard lifecycle automation scripts and README operational guidance.

## Strengths
- Scripts consistently use defensive Bash flags (`set -euo pipefail`) and keep execution non-interactive for automation contexts.
- Server install flow is idempotent for key/config generation and uses `iptables -C` checks to avoid duplicate rules in `PostUp`.
- Peer creation flow supports endpoint normalization (`host`, `host:port`, IPv6 forms) and generates ready-to-use client configs.
- README documents a practical end-to-end usage sequence (server install, peer generation, client install, uninstall paths).

## Findings and Changes Applied

### 1) Missing preflight checks in peer provisioning (fixed)
**Issue:** `wg-server-add-peer.sh` assumed server artifacts/interface already existed (`/etc/wireguard/wg0.conf`, server public key, running interface), leading to hard-to-diagnose runtime failures when prerequisites were missing.

**Impact:** Operational troubleshooting friction and partial/unclear failures on fresh or misconfigured hosts.

**Fix applied:** Added explicit checks for:
- readable server config file,
- readable server public key,
- active WireGuard interface (`wg show <if>`).

Failures now return actionable error messages.

### 2) Missing validation on resolved WG port (fixed)
**Issue:** The resolved port (from env or parsed config) was not range-validated.

**Impact:** Invalid port values could propagate into generated client endpoint configuration.

**Fix applied:** Added strict `1..65535` validation for `WG_PORT` in `wg-server-add-peer.sh`.

## Residual Recommendations
1. Strengthen `allowed_ips` validation beyond regex (semantic CIDR parsing, optional comma-separated lists).
2. Add a light test harness (e.g., `bats` or shell function tests) for endpoint rendering and validators.
3. Consider nftables support or explicit iptables backend documentation for newer Debian/Ubuntu defaults.

## Overall Assessment
- **Operational usefulness:** 9/10
- **Maintainability:** 8.5/10
- **Safety hardening:** 8/10
- **Testability:** 7/10
