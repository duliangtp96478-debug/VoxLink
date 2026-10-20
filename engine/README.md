# External Flutter Windows engine (not included)

The original VoxLink 1.0.1 Stable project references a specific Flutter 3.47.6 engine patched with a Fix7 accessibility null-parent guard. The custom binary `flutter_windows.dll` was intentionally **excluded** from this public-source preparation.

To run the legacy packaging step unchanged, a project owner must provide and verify the authorized patched engine at `engine/flutter_windows.dll`. The build script checks expected SHA256; do not use a random Flutter DLL or remove its hash verification. Build/publish an updated patch from licensed upstream source as a separate, audited follow-up.

`windows/tools/package_stable.ps1` will fail without this file. This is an explicit source-only publishing limitation, not a completed reproducible public binary release.
