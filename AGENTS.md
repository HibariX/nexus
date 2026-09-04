# Repository Guidelines

## Project Structure & Module Organization

MyRaycast is a Swift 6.2 macOS 15.2+ executable package. Application code lives in `Sources/MyRaycast/`: `App/` owns lifecycle and settings, `Core/` contains search and command abstractions, `UI/` contains shared AppKit/SwiftUI views, and feature code is grouped under `Providers/`, `Snip/`, `Todo/`, and `Plugins/`. Tests are in `Tests/MyRaycastTests/`. Bundle metadata and icons live in `Support/`; bundled external plugins live in `Plugins/<plugin-name>/`. Treat `.build/` and `build/` as generated output.

## Build, Test, and Development Commands

- `swift build` compiles a debug build for quick validation.
- `make build` creates the release executable.
- `make test` (or `swift test`) runs the complete test suite.
- `make bundle` assembles and signs `build/MyRaycast.app` using the identity configured in `Makefile`.
- `make run` rebuilds the bundle and launches it through LaunchServices so macOS TCC permissions attach to the app, not Terminal.
- `make install-plugins` copies demo plugins into Application Support for development.
- `make clean` removes generated build directories.

## Coding Style & Naming Conventions

Follow the existing Swift style: four-space indentation, braces on the declaration line, and focused files named after their primary type. Use `UpperCamelCase` for types and `lowerCamelCase` for methods, properties, and tests. Keep feature-specific code in its feature directory; put reusable launcher behavior in `Core/` or `UI/`. The package defaults modules to `@MainActor`; mark genuinely pure, thread-safe helpers `nonisolated` explicitly. No formatter or linter is configured, so preserve nearby formatting and keep compiler warnings clean.

## Testing Guidelines

Tests use Swift Testing (`@Suite`, `@Test`, `#expect`, and `#require`), not XCTest. Name files `<Subject>Tests.swift` and tests after observable behavior, such as `prefixBeatsScattered`. Add unit coverage for new parsing, matching, persistence, and settings logic, plus a regression test for each bug fix. There is no numeric coverage threshold; prioritize deterministic tests and isolate filesystem state with temporary paths.

## Commit & Pull Request Guidelines

This checkout contains no Git history to infer an established convention. Use short, imperative commit subjects, optionally scoped, for example `fix(todo): preserve reminder list selection`. Keep commits focused. Pull requests should explain the user-visible change, list validation commands, link relevant issues, and include screenshots or a short recording for UI changes. Call out permission, signing, plugin-manifest, or persistent-data changes explicitly.
