# Muscu

Une application iOS pour la gestion personnalisée des entraînements de musculation et du suivi des performances.

## Documentation

- [Spécification complète](docs/superpowers/specs/2026-07-16-muscu-app-design.md)

## Build

### MuscuEngine (bibliothèque Swift)

```bash
cd Packages/MuscuEngine
swift test
```

### Application iOS

```bash
xcodegen
xcodebuild -scheme Muscu -configuration Release
```
