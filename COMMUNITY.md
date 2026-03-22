# Zion Community

Guidelines for contributing to and participating in the Zion community.

## Getting Help

- **Issues**: https://github.com/ghostkellz/zion/issues
- **Discussions**: https://github.com/ghostkellz/zion/discussions

## Contributing

### Reporting Bugs

1. Check existing issues first
2. Include Zion version (`zion version`)
3. Include Zig version (`zig version`)
4. Provide minimal reproduction steps
5. Include error messages and logs

### Feature Requests

1. Check existing issues and roadmap (TODO.md)
2. Describe the use case clearly
3. Explain why existing features don't meet the need

### Pull Requests

1. Fork the repository
2. Create a feature branch from `main`
3. Write tests for new functionality
4. Ensure `zig build test` passes
5. Format code with `zig fmt`
6. Submit PR with clear description

### Code Style

- Follow Zig's standard style guidelines
- Use descriptive variable and function names
- Add documentation for public APIs
- Prefer explicit error handling over `catch unreachable`
- Keep functions focused and small

## Ecosystem

### Related Projects

- **GhostSpec** - Property testing framework for Zig
- **zsync** - Async runtime library
- **phantom** - TUI framework
- **zdoc** - Documentation generator

### Registries

- **GitHub** - Primary package source
- **Zigistry** - Community package registry

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help newcomers learn
- Keep discussions on-topic

## License

Zion is MIT licensed. Contributions are accepted under the same license.
