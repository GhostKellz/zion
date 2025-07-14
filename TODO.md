# Zion v1.0.0 Community Integration TODO

> This TODO tracks all major planned community integrations for the 1.0.0 milestone.  
> All items are prioritized in recommended implementation order.  
> *(Astrolabe Build System integration is listed as low priority and may land post-1.0.0 if needed.)*

---

## 🚀 High Priority

### 1. Enhanced Ziglibs Integration
- [ ] Add `ziglibs` package metadata to search and add commands
- [ ] Show Ziglibs badges/quality indicators in CLI
- [ ] Implement `zion ziglibs list`, `zion ziglibs search`, and `--prefer-ziglibs` flag
- [ ] Display maintenance status, API stability, and other Ziglibs info
- [ ] Command: `zion ziglibs status` for current project packages

---

### 2. Zigistry API Enhancements
- [ ] Support signed publishing to Zigistry (`zion publish --zigistry --sign`)
- [ ] Show package download statistics, popularity, and health
- [ ] Integrate package ratings/reviews if available from Zigistry
- [ ] Add advanced search filters: maintainer, version compatibility, etc.
- [ ] Zigistry analytics/stats command

---

### 3. Zepplin (Self-Hosted Registry) Features
- [ ] Polish Zepplin support and document workflows
- [ ] Support authentication/authorization for private registries
- [ ] Add seamless public/private hybrid workflows (`mirror`, `audit`, etc.)
- [ ] Audit logging for enterprise/private registry actions

---

### 4. ZPI (Zig Package Index) Integration
- [ ] Implement unified search across all registries (`zion index search`)
- [ ] Display combined package metadata (duplicates, registry source, stats)
- [ ] Add ZPI registry sync and stats commands
- [ ] Registry health monitoring and failover support
- [ ] Command to compare a package across registries (`zion index compare`)

---

### 5. Deep ZLS (Zig Language Server) Integration
- [ ] Real-time dependency health checks in editor (`zion zls deps --watch`)
- [ ] Show inline package info and documentation in editor
- [ ] Implement completions for package names/versions
- [ ] Auto-generate/optimize import statements (`zion zls imports --optimize`)
- [ ] Visual dependency tree and one-click add (for supporting IDEs)

---

## 🛠️ Lower Priority

### 6. Astrolabe Build System Integration
- [ ] Integrate Astrolabe build analysis (`zion build --astrolabe`)
- [ ] Expose Astrolabe diagnostics and build optimization suggestions
- [ ] Dependency impact analysis on build times
- [ ] Command to migrate/optimize `build.zig` (`zion astrolabe migrate`)
- [ ] Document Astrolabe integration and CLI usage

---

# Community & Contributor Notes

- Want to help? See CONTRIBUTING.md and our [Discussions](https://github.com/ghostkellz/zion/discussions)
- Maintainers of Ziglibs, Zigistry, Zepplin, ZLS, ZPI, or Astrolabe — please reach out!
- All integrations are designed as pluggable modules for long-term flexibility.

---

*(Move completed items to CHANGELOG.md as you ship each integration.)*

