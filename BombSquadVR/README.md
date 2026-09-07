# BombSquadVR iOS target

The authoritative setup, resource, signing and build instructions are in the
[top-level BombSquadVR-iOS README](../README.md). This directory contains the XcodeGen
specification, native Cardboard bridge and build scripts.

The app target expects ../BallisticaResources at build time. That directory is
a local staged input and may contain proprietary game data; do not commit it,
the downloaded/adapted Ballistica Plus library, or an IPA containing them.
