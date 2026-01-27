# Nix Flake Design Patterns - Shoe Comparison Table

A comprehensive comparison of different approaches to structuring NixOS configurations.

## Quick Summary

| Pattern | Best For | Complexity | Learning Curve |
|---------|----------|------------|----------------|
| **Monolithic** | Single host, beginners | Low | Easy |
| **Simple Modular** | 2-5 hosts, solo dev | Low-Medium | Easy |
| **Dendritic + Flake-Parts** | Multi-host, teams | Medium | Medium |
| **Snowfall-lib** | Convention-loving teams | Medium-High | Medium |
| **Digga/devos** | Enterprise, large teams | High | Steep |

---

## Detailed Comparison

### 1. Monolithic Flake (Your Current Approach)

**Structure:**
```
flake.nix              # Everything defined here
├── hosts/
│   └── hostname/
│       ├── configuration.nix
│       └── hardware-configuration.nix
├── modules/           # Custom modules
└── home-manager/
```

| Aspect | Rating | Notes |
|--------|--------|-------|
| **Simplicity** | ⭐⭐⭐⭐⭐ | Everything in one place |
| **Debugging** | ⭐⭐⭐⭐ | Easy to trace issues |
| **Scalability** | ⭐⭐ | Gets unwieldy at 3+ hosts |
| **Reusability** | ⭐⭐ | Manual copy-paste between hosts |
| **Team Collaboration** | ⭐⭐ | Merge conflicts in flake.nix |
| **Boilerplate** | ⭐⭐⭐⭐⭐ | Minimal |

**Pros:**
- Zero learning curve beyond basic Nix
- No external dependencies/frameworks
- Full control, no magic
- Easy to understand entire config at a glance

**Cons:**
- Module lists grow long in flake.nix
- Repetitive patterns between hosts
- No standardized structure for sharing

---

### 2. Simple Modular (Without Frameworks)

**Structure:**
```
flake.nix
├── lib/
│   └── mkHost.nix     # Helper functions
├── hosts/
│   └── hostname/
│       └── default.nix
├── modules/
│   ├── nixos/         # NixOS modules
│   └── home/          # Home-manager modules
└── profiles/          # Composable role bundles
    ├── desktop.nix
    └── server.nix
```

| Aspect | Rating | Notes |
|--------|--------|-------|
| **Simplicity** | ⭐⭐⭐⭐ | Slightly more structure |
| **Debugging** | ⭐⭐⭐⭐ | Clear module boundaries |
| **Scalability** | ⭐⭐⭐ | Good for small-medium setups |
| **Reusability** | ⭐⭐⭐ | Profiles help share configs |
| **Team Collaboration** | ⭐⭐⭐ | Less flake.nix contention |
| **Boilerplate** | ⭐⭐⭐⭐ | Some helper code needed |

**Pros:**
- Natural evolution from monolithic
- Custom `mkHost` functions reduce repetition
- Profiles enable role-based composition
- Still no external framework dependencies

**Cons:**
- Must write own helper functions
- No standard conventions (your own patterns)
- Cross-platform (Darwin) needs manual handling

---

### 3. Dendritic Design + Flake-Parts

**Structure:**
```
flake.nix              # Uses flake-parts
├── flake-modules/     # Flake-level modules
├── modules/
│   ├── nixos/
│   └── home-manager/
├── features/          # Composable features
│   ├── desktop/
│   ├── server/
│   └── development/
├── hosts/
└── packages/
```

| Aspect | Rating | Notes |
|--------|--------|-------|
| **Simplicity** | ⭐⭐⭐ | Framework adds indirection |
| **Debugging** | ⭐⭐⭐⭐⭐ | Errors localized to features |
| **Scalability** | ⭐⭐⭐⭐⭐ | Designed for growth |
| **Reusability** | ⭐⭐⭐⭐⭐ | Features are highly portable |
| **Team Collaboration** | ⭐⭐⭐⭐ | Clear boundaries |
| **Boilerplate** | ⭐⭐⭐ | Some flake-parts setup |

**Pros:**
- Philosophy-first: focuses on *how* to structure code
- 8 design aspects (Inheritance, Factory, DRY, etc.)
- Flake-parts provides modular flake composition
- Cross-platform support built-in
- Features adapt to different contexts (Multi-Context Aspect)

**Cons:**
- Requires learning flake-parts
- More files/directories
- Philosophy may be overkill for simple setups
- Less community examples than snowfall

**Key Concepts:**
- **Features**: Discrete, composable functionality units
- **Aspects**: Design patterns (Simple, Multi-Context, Inheritance, Conditional, Collector, Constants, DRY, Factory)

---

### 4. Snowfall-lib

**Structure:**
```
flake.nix              # Uses snowfall-lib
├── lib/               # Custom library functions
├── modules/
│   ├── nixos/
│   ├── darwin/
│   └── home/
├── systems/
│   ├── x86_64-linux/
│   │   └── hostname/
│   └── aarch64-darwin/
├── homes/
│   └── user@hostname/
└── packages/
```

| Aspect | Rating | Notes |
|--------|--------|-------|
| **Simplicity** | ⭐⭐⭐ | Convention-heavy |
| **Debugging** | ⭐⭐⭐ | Magic can obscure issues |
| **Scalability** | ⭐⭐⭐⭐ | Good structure |
| **Reusability** | ⭐⭐⭐⭐ | Strong conventions help |
| **Team Collaboration** | ⭐⭐⭐⭐ | Everyone knows where things go |
| **Boilerplate** | ⭐⭐⭐⭐⭐ | Auto-discovery reduces it |

**Pros:**
- Convention over configuration
- Auto-discovery of modules, packages, systems
- Built-in Darwin/Home-Manager integration
- Active community and examples
- Channels/overlays handling included

**Cons:**
- Must follow snowfall conventions exactly
- Magic auto-discovery can be confusing
- Debugging requires understanding internals
- Framework lock-in

---

### 5. Digga/devos

**Structure:**
```
flake.nix
├── cells/             # Grouped functionality
│   ├── common/
│   ├── hosts/
│   └── users/
├── profiles/
├── suites/
└── lib/
```

| Aspect | Rating | Notes |
|--------|--------|-------|
| **Simplicity** | ⭐⭐ | Heavy abstraction |
| **Debugging** | ⭐⭐ | Deep abstraction layers |
| **Scalability** | ⭐⭐⭐⭐⭐ | Enterprise-grade |
| **Reusability** | ⭐⭐⭐⭐⭐ | Cells are highly modular |
| **Team Collaboration** | ⭐⭐⭐⭐⭐ | Clear ownership boundaries |
| **Boilerplate** | ⭐⭐ | Significant setup required |

**Pros:**
- Cell-based architecture for large organizations
- Suites bundle profiles elegantly
- Excellent for 10+ hosts/users
- Strong separation of concerns

**Cons:**
- Steep learning curve
- Overkill for personal configs
- Heavy framework dependency
- Less maintained recently (digga deprecated)

---

## Migration Path Recommendation

```
Monolithic → Simple Modular → Dendritic/Flake-Parts → Snowfall
     ↓              ↓                   ↓
  1-2 hosts      3-5 hosts          5+ hosts
```

### For Your Current Config

Your current setup is a well-organized **Monolithic** pattern. Consider evolving to:

1. **Short-term**: Add a `lib/mkHost.nix` helper to reduce flake.nix duplication
2. **Medium-term**: If adding more hosts, consider **Dendritic + Flake-Parts**
3. **Long-term**: If team grows, evaluate **Snowfall-lib**

---

## Complexity vs Flexibility Matrix

```
High Flexibility │                          ┌─────────┐
                 │                   ┌──────│ Digga   │
                 │          ┌────────│      └─────────┘
                 │   ┌──────│Dendritic
                 │   │      └────────┐
                 │   │Snowfall       │
                 │   └───────────────┤
                 │     Simple Modular│
                 │   ┌───────────────┘
                 │   │
Low Flexibility  │───│Monolithic
                 └───┴────────────────────────────────────
                    Low Complexity          High Complexity
```

---

## Decision Checklist

Choose **Monolithic** if:
- [ ] Single host or just starting out
- [ ] Want to understand every line
- [ ] No team collaboration needed

Choose **Simple Modular** if:
- [ ] 2-5 hosts with similar configurations
- [ ] Want profiles without frameworks
- [ ] Comfortable writing helper functions

Choose **Dendritic + Flake-Parts** if:
- [ ] Growing number of hosts
- [ ] Want principled design patterns
- [ ] Need cross-platform support
- [ ] Value debuggability and feature isolation

Choose **Snowfall-lib** if:
- [ ] Prefer convention over configuration
- [ ] Multiple platforms (Linux + Darwin)
- [ ] Want auto-discovery magic
- [ ] Team with varying Nix experience

Choose **Digga** if:
- [ ] Enterprise/organization scale
- [ ] 10+ hosts, multiple teams
- [ ] Need strict boundaries between cells

---

## References

- [Dendritic Design with Flake-Parts](https://github.com/Doc-Steve/dendritic-design-with-flake-parts)
- [Flake-Parts](https://flake.parts/)
- [Snowfall-lib](https://github.com/snowfallorg/lib)
- [Digga](https://github.com/divnix/digga) (deprecated, see hive)
