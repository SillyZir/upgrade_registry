package upgrade_registry

import (
	"std"
	"strconv"
	"strings"
)

// ContractEntry represents a registered contract and its upgrade status.
type ContractEntry struct {
	Address    string
	Owner      string
	Name       string
	Deprecated bool
	Successor  string // address of the upgraded contract, empty if current
}

var (
	entries        map[string]*ContractEntry
	entryAddrs     []string // insertion-ordered for deterministic Render
	ownerContracts map[string][]string
)

func init() {
	entries = make(map[string]*ContractEntry)
	entryAddrs = []string{}
	ownerContracts = make(map[string][]string)
}

func caller() string {
	return string(std.PreviousRealm().Address())
}

// ---------- write operations ----------

// Register adds a contract to the registry. The caller becomes the owner.
// Panics if inputs are empty or address is already taken.
func Register(_ realm, contractAddr, name string) string {
	if contractAddr == "" || name == "" {
		panic("contractAddr and name must not be empty")
	}
	if _, exists := entries[contractAddr]; exists {
		panic("contract already registered: " + contractAddr)
	}

	owner := caller()
	entries[contractAddr] = &ContractEntry{
		Address: contractAddr,
		Owner:   owner,
		Name:    name,
	}
	entryAddrs = append(entryAddrs, contractAddr)
	ownerContracts[owner] = append(ownerContracts[owner], contractAddr)
	return "registered " + name + " at " + contractAddr
}

// Deprecate marks a contract as deprecated and points to its successor.
// Only the registered owner can deprecate. The successor address must
// not create a circular chain back to the current contract.
func Deprecate(_ realm, contractAddr, successorAddr string) string {
	entry := mustGet(contractAddr)
	if entry.Owner != caller() {
		panic("only the owner can deprecate this contract")
	}
	if successorAddr == "" {
		panic("successor address must not be empty")
	}
	if entry.Deprecated {
		panic("contract is already deprecated")
	}
	if successorAddr == contractAddr {
		panic("successor cannot be the contract itself")
	}

	// Prevent circular chains: walk from successor and ensure we don't
	// loop back to contractAddr.
	visited := make(map[string]bool)
	visited[contractAddr] = true
	cur := successorAddr
	for {
		if visited[cur] {
			panic("circular migration chain: " + cur + " leads back to " + contractAddr)
		}
		e, exists := entries[cur]
		if !exists || !e.Deprecated || e.Successor == "" {
			break
		}
		visited[cur] = true
		cur = e.Successor
	}

	entry.Deprecated = true
	entry.Successor = successorAddr
	return "deprecated " + entry.Name + ", successor: " + successorAddr
}

// TransferOwnership hands control of a registry entry to a new owner.
// Updates both the entry and the ownerContracts index.
func TransferOwnership(_ realm, contractAddr, newOwner string) string {
	entry := mustGet(contractAddr)
	oldOwner := entry.Owner
	if oldOwner != caller() {
		panic("only the owner can transfer ownership")
	}
	if newOwner == "" {
		panic("new owner must not be empty")
	}

	// Update ownerContracts index: remove from old, add to new
	old := ownerContracts[oldOwner]
	for i, addr := range old {
		if addr == contractAddr {
			ownerContracts[oldOwner] = append(old[:i], old[i+1:]...)
			break
		}
	}
	ownerContracts[newOwner] = append(ownerContracts[newOwner], contractAddr)

	entry.Owner = newOwner
	return "ownership transferred to " + newOwner
}

// ---------- read-only queries ----------

// GetLatest follows the migration chain from a contract address and
// returns the latest non-deprecated address. Safe against circular refs.
func GetLatest(contractAddr string) string {
	visited := make(map[string]bool)
	current := contractAddr

	for {
		entry, exists := entries[current]
		if !exists {
			return current
		}
		if !entry.Deprecated || entry.Successor == "" {
			return current
		}
		if visited[current] {
			return current // break on circular
		}
		visited[current] = true
		current = entry.Successor
	}
}

// GetMigrationChain returns the full upgrade path starting from the
// given address. Each hop is formatted as "address (name)" joined by " -> ".
func GetMigrationChain(contractAddr string) string {
	visited := make(map[string]bool)
	current := contractAddr
	var parts []string

	for {
		entry, exists := entries[current]
		if !exists {
			if len(parts) == 0 {
				return "not found: " + contractAddr
			}
			parts = append(parts, current+" (unregistered)")
			break
		}
		if visited[current] {
			parts = append(parts, current+" (circular)")
			break
		}
		visited[current] = true

		tag := ""
		if entry.Deprecated {
			tag = " [deprecated]"
		}
		parts = append(parts, entry.Address+" ("+entry.Name+")"+tag)

		if !entry.Deprecated || entry.Successor == "" {
			break
		}
		current = entry.Successor
	}

	return strings.Join(parts, " -> ")
}

// GetInfo returns a one-line summary for a contract.
func GetInfo(contractAddr string) string {
	entry := mustGet(contractAddr)
	status := "active"
	if entry.Deprecated {
		status = "deprecated -> " + entry.Successor
	}
	return entry.Name + " | owner: " + entry.Owner + " | " + status
}

// GetOwnerContracts returns all contract addresses registered by an owner.
func GetOwnerContracts(owner string) string {
	addrs, exists := ownerContracts[owner]
	if !exists || len(addrs) == 0 {
		return "none"
	}
	return strings.Join(addrs, ", ")
}

// ---------- render ----------

// Render returns a markdown overview. Never panics.
func Render(path string) string {
	if entries == nil || len(entries) == 0 {
		return "# Upgrade Registry\n\nNo contracts registered.\n"
	}

	var b strings.Builder
	b.WriteString("# Upgrade Registry\n\n")
	b.WriteString("**Registered contracts:** " + strconv.Itoa(len(entries)) + "\n\n")

	var active []string
	var deprecated []string

	for _, addr := range entryAddrs {
		entry := entries[addr]
		if entry == nil {
			continue
		}
		line := "- **" + entry.Name + "** (`" + addr + "`) — owner: `" + entry.Owner + "`"
		if entry.Deprecated {
			line += " — **DEPRECATED** -> `" + entry.Successor + "`"
			latest := GetLatest(addr)
			if latest != entry.Successor {
				line += " (latest: `" + latest + "`)"
			}
			deprecated = append(deprecated, line)
		} else {
			active = append(active, line)
		}
	}

	if len(active) > 0 {
		b.WriteString("## Active\n\n")
		for _, l := range active {
			b.WriteString(l + "\n")
		}
		b.WriteString("\n")
	}

	if len(deprecated) > 0 {
		b.WriteString("## Deprecated\n\n")
		for _, l := range deprecated {
			b.WriteString(l + "\n")
		}
		b.WriteString("\n")
	}

	return b.String()
}

// ---------- helpers ----------

func mustGet(addr string) *ContractEntry {
	entry, ok := entries[addr]
	if !ok {
		panic("contract not found: " + addr)
	}
	return entry
}
