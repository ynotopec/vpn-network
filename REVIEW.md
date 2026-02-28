# Repository Review

## Scope
This review covers the current repository state with three executable WireGuard automation scripts and supporting documentation.

## What is good
- Scripts are versioned in `scripts/` and follow defensive bash defaults (`set -euo pipefail`).
- Server bootstrap is mostly idempotent (key generation/config creation guarded, `PostUp` uses `iptables -C` checks).
- `wg-server-add-peer.sh` includes baseline input validation and emits a ready-to-install client config.
- README documents an operational end-to-end flow (server install → peer creation → client install).

## Findings

### 1) Addressing mismatch risk in peer generation (fixed)
**Issue:** Client IP assignment in `wg-server-add-peer.sh` used a hardcoded `10.10.0.X` prefix, even when `WG_SERVER_IP` is customized. This could generate peers outside the intended server subnet.

**Impact:** Misconfigured peers, failed routing, and harder troubleshooting in non-default topologies.

**Fix applied:** Client IP now derives its prefix from `WG_SERVER_IP` (`${WG_SERVER_IP%.*}`), preserving the selected subnet.

### 2) Missing validation for `WG_SERVER_IP` (fixed)
**Issue:** `WG_SERVER_IP` was accepted without structural validation.

**Impact:** Invalid values could produce malformed client configs and server-side peer entries.

**Fix applied:** Added strict IPv4 octet validation for `WG_SERVER_IP`.

### 3) Weak sanitization for `client_name` (fixed)
**Issue:** `client_name` flowed into marker tags and temp file names without sanitization.

**Impact:** Unexpected characters could break formatting and file handling.

**Fix applied:** Added `client_name` validation (`[a-zA-Z0-9._-]+`).

## Residual recommendations
1. Consider validating CIDR ranges semantically (not just with regex) for `allowed_ips`.
2. Add automated CI checks for `bash -n` and `shellcheck` if not already present in workflow files.
3. Add collision detection based on existing `AllowedIPs` in addition to comment markers to prevent duplicate subnet assignments.

## Overall assessment
- **Operational usefulness:** 8.5/10
- **Maintainability:** 8/10
- **Safety hardening:** 7/10
- **Testability:** 6.5/10
