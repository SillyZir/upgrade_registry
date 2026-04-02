# upgrade_registry — Technical Specification

## Overview

`upgrade_registry` is a Gno realm that maintains a directed graph of contract upgrade relationships. Each node is a contract address; each edge is a deprecation pointing to a successor. The graph is append-only: once a contract is deprecated, the pointer is permanent.

## Data Structures

### ContractEntry

```
type ContractEntry struct {
    Address    string   // the contract's on-chain address
    Owner      string   // address that controls this entry
    Name       string   // human-readable identifier
    Deprecated bool     // true once deprecated
    Successor  string   // points to the next version, empty if current
}
```

### Storage

```
entries        map[string]*ContractEntry   // keyed by contract address
ownerContracts map[string][]string         // owner -> list of registered addresses
```

## Upgrade Chain

When a contract is deprecated, its `Successor` field is set to the address of the new version. This creates a singly-linked list:

```
addr_v1 -> addr_v2 -> addr_v3
```

`GetLatest(addr_v1)` walks this chain and returns `addr_v3`.

`GetMigrationChain(addr_v1)` returns the full path:
```
addr_v1 (TokenV1) [deprecated] -> addr_v2 (TokenV2) [deprecated] -> addr_v3 (TokenV3)
```

### Chain traversal

Both `GetLatest` and `GetMigrationChain` use a visited-set to detect cycles. If a cycle is found, traversal stops at the repeated node rather than looping infinitely.

## Invariants

1. **No duplicate addresses**: `Register` panics if the address already exists.
2. **One deprecation per entry**: once `Deprecated == true`, calling `Deprecate` again panics.
3. **No self-referential deprecation**: `Deprecate(addr, addr)` panics.
4. **No circular chains**: `Deprecate` walks from the proposed successor forward. If it encounters the current contract, it panics before writing.
5. **Owner-only mutations**: `Deprecate` and `TransferOwnership` verify `caller == entry.Owner`.
6. **Successor permanence**: once set, a successor pointer is never changed. The deprecation graph is append-only.

## Safety Guarantees

### Circular reference prevention

When `Deprecate(owner, contractAddr, successorAddr)` is called:

1. Build a visited set starting with `contractAddr`.
2. Walk from `successorAddr` following each entry's `Successor` field.
3. If any visited address is encountered, panic with "circular migration chain".
4. If a non-existent or non-deprecated entry is reached, the chain is valid.

This runs at deprecation time, not at query time, so `GetLatest` never encounters a cycle in well-formed state. The visited-set in `GetLatest` is a defense-in-depth fallback.

### Ownership enforcement

Only the address stored in `entry.Owner` can:
- Deprecate the entry
- Transfer ownership to a new address

Registration is open — anyone can register any unregistered address. Ownership is assigned to the caller-provided owner address at registration time.

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| `GetLatest` on unregistered address | Returns the address as-is |
| `GetMigrationChain` on unregistered address | Returns "not found: addr" |
| `GetLatest` on active (non-deprecated) contract | Returns the same address |
| `Deprecate` with successor not in registry | Allowed — the successor doesn't need to be registered yet |
| `Deprecate` twice | Panics: "contract is already deprecated" |
| Circular chain `A -> B -> A` | Prevented at deprecation time |
| `TransferOwnership` then `Deprecate` | New owner can deprecate; old owner cannot |
| Very long chain (100+ hops) | Works, bounded by visited-set; no stack recursion |

## Limitations

- No on-chain event emission — consumers must poll or query.
- Ownership is address-based, not key-based. If the owner address is a realm, that realm controls the entry.
- The registry is global and permissionless. Anyone can register any address that isn't already taken. First-come-first-served.
- Deprecation is permanent. There is no "un-deprecate" operation by design — this prevents confusion about which version is canonical.
