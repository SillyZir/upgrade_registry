# upgrade_registry

On-chain contract upgrade tracking for Gno.land.

## Problem

When a smart contract is upgraded or migrated to a new address, there's no standard way to announce the change. Users keep interacting with stale contracts. Frontends hardcode old addresses. Indexers return outdated data. The result: fragmented ecosystems where nobody agrees on which version is current.

This happens because contract addresses are immutable — once deployed, you can't redirect them. Every upgrade creates a new address, and the old one silently becomes a dead end.

## Solution

`upgrade_registry` is a shared, on-chain registry where contract owners register their deployments and record upgrade paths. When a contract is deprecated, the owner points it to its successor, creating a verifiable **migration chain** that anyone can follow to find the latest version.

```
v1 (deprecated) -> v2 (deprecated) -> v3 (active)
```

Any tool, frontend, or contract can call `GetLatest("v1_address")` and get `v3_address` back — no hardcoded addresses, no manual coordination, no trust required.

## Why this matters

- **Frontends** can auto-resolve to the latest contract without code changes
- **Indexers** can follow the chain to avoid serving stale data
- **Users** get warned when interacting with deprecated contracts
- **Developers** get a standard way to announce upgrades across the ecosystem
- **Auditors** can trace the full upgrade history of any contract

Without a registry like this, every project reinvents upgrade coordination ad-hoc — or worse, doesn't coordinate at all.

## Usage

### Register a contract

```
Register(cross, "g1owner...", "g1contract_v1...", "MyToken")
// returns: "registered MyToken at g1contract_v1..."
```

### Deprecate and point to successor

```
Register(cross, "g1owner...", "g1contract_v2...", "MyToken v2")
Deprecate(cross, "g1owner...", "g1contract_v1...", "g1contract_v2...")
// returns: "deprecated MyToken, successor: g1contract_v2..."
```

### Resolve the latest version

```
GetLatest("g1contract_v1...")
// returns: "g1contract_v2..."
```

### View the full migration chain

```
GetMigrationChain("g1contract_v1...")
// returns: "g1contract_v1... (MyToken) [deprecated] -> g1contract_v2... (MyToken v2)"
```

### Transfer ownership

```
TransferOwnership(cross, "g1owner...", "g1contract_v1...", "g1new_owner...")
```

## API

| Function | Access | Description |
|----------|--------|-------------|
| `Register(cross, owner, addr, name)` | Anyone | Register a contract. Caller-provided owner controls it. |
| `Deprecate(cross, owner, addr, successor)` | Owner | Mark as deprecated, point to successor. |
| `TransferOwnership(cross, owner, addr, newOwner)` | Owner | Hand off registry control. |
| `GetLatest(addr)` | Anyone | Follow chain to the latest active address. |
| `GetMigrationChain(addr)` | Anyone | Full upgrade path as formatted string. |
| `GetInfo(addr)` | Anyone | One-line summary of a contract entry. |
| `GetOwnerContracts(owner)` | Anyone | List all contracts registered by an owner. |
| `Render(path)` | Anyone | Markdown overview of all registered contracts. |

## Query on Gno.land

Visit `/r/upgrade_registry` on any Gno.land node to see all registered contracts, their status, and migration chains.

Query specific contracts:

```
gnokey query vm/qeval --data 'gno.land/r/upgrade_registry.GetLatest("g1contract...")' --remote <rpc>
gnokey query vm/qeval --data 'gno.land/r/upgrade_registry.GetMigrationChain("g1contract...")' --remote <rpc>
```

---
