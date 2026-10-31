# Vendored: mediaremote-adapter

Source: https://github.com/ungive/mediaremote-adapter
Commit: 0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd (2026-10-17)
Licence: BSD 3-Clause (see LICENSE in this folder)

Copied unchanged: `src/adapter`, `src/private`, `src/utility`, `include`, and
`bin/mediaremote-adapter.pl`, which lives at `../../Resources/Iceberg/mediaremote-adapter.pl`
so it is copied into the app's Resources.
Left out: the test client (`src/test`, except the header `test.m` imports), CMake files and developer scripts.

`Package.swift` builds these sources as the dynamic library product
`MediaRemoteAdapter` (`libMediaRemoteAdapter.dylib`). Iceberg does not link it:
it finds the library (inside the app, beside its program, or in the package's
`.build/release`), wraps it as `MediaRemoteAdapter.framework` in
`~/Library/Application Support/Iceberg/`, and runs
`/usr/bin/perl mediaremote-adapter.pl MediaRemoteAdapter.framework stream`, which is
how Now Playing keeps working on macOS 15.4 and later.

To update: copy the same folders from a newer commit and change the commit above.
