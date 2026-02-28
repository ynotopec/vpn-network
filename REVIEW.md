# Repository Review

## Scope
This review covers the current repository state, which contains a single documentation file (`README.md`) describing WireGuard hub-and-spoke setup scripts.

## What is good
- Clear architecture assumptions (public VPS hub, NATed clients, outbound initiation from clients).
- Practical, idempotent shell script patterns (`set -euo pipefail`, key generation only if missing, config creation only if absent).
- Includes end-to-end operational flow (server install, add peer, client install, smoke tests).

## Main risks and gaps
1. **Scripts are documented but not versioned as executable files**
   - The repository only ships scripts as fenced code blocks in the README.
   - This makes testing, linting, and change tracking harder than maintaining dedicated `.sh` files.

2. **Potentially unsafe peer insertion check**
   - `wg-server-add-peer.sh` checks peer existence by marker comment (`### peer:<name>`).
   - If formatting changes manually, duplicate peers may be appended.

3. **Input validation is minimal**
   - `client_ip_last_octet` is not validated as an integer in `[2..254]`.
   - `SERVER_ENDPOINT` and `allowed_ips` are accepted as-is.

4. **Firewall persistence assumptions are implicit**
   - The README relies on WireGuard `PostUp/PostDown` iptables rules.
   - Behavior can conflict with host firewalls (`ufw`, `nftables`) or reboot-time ordering.

5. **No automated verification in repo**
   - There are no shellcheck checks, syntax checks, or CI workflow.

## Recommended next steps (priority order)
1. Move each script into tracked files:
   - `scripts/wg-server-install.sh`
   - `scripts/wg-server-add-peer.sh`
   - `scripts/wg-client-install.sh`
2. Add basic validation helpers for octet range, endpoint non-empty sanity, and CIDR input.
3. Add `shellcheck` and `bash -n` checks via a small CI workflow.
4. Document `iptables` vs `nftables` expectations and known interactions with `ufw`.
5. Keep README examples, but source them from script files (or reference file paths directly) to avoid documentation drift.

## Quick quality score (current state)
- **Operational usefulness:** 8/10
- **Maintainability in-repo:** 4/10
- **Safety hardening:** 5/10
- **Testability:** 3/10
