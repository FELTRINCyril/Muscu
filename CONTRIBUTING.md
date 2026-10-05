# Contributing

1. Create a focused branch and keep generated Xcode project changes consistent with `project.yml`.
2. Run `swift test` in `Packages/MuscuEngine`.
3. Regenerate the project with `xcodegen generate`, then run the `MuscuTests` scheme tests.
4. Do not add exercise media without documenting its provenance and licence in `THIRD_PARTY_NOTICES.md`.
5. Never ignore SwiftData save errors or add unvalidated fields to the import format.
