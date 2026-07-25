# Cydia Installer for RootHide — experimental iOS 16 port

This branch contains an automated, reproducible test build of Cydia Installer 1.1.38 for RootHide on iOS 16.

## What the build changes

- Starts from the Cydia Installer 1.1.38 Debian package published by Sam Bingner.
- Converts its Mach-O binaries and package layout with RootHidePatcher.
- Adds a Cydia-only compatibility layer that translates APT, dpkg and Cydia filesystem paths through RootHide's `jbroot()` API.
- Updates the dependency list to the modern bootstrap package names used by RootHide/Procursus.
- Removes Cydia's legacy launch daemon and bundled APT source list.
- Uses a separate package identifier, keeps Sileo installed and does not replace Sileo files.

## Safety status

This is an experimental compatibility port, not an official RootHide or Saurik release. Building successfully proves only that the package was assembled and structurally validated. Refreshing sources, downloading packages, installing, removing, upgrading and recovery must still be tested on an actual RootHide iOS 16 device.

Do not merge the generated package into the public repository until it has passed device tests. Keep Sileo installed as the recovery package manager.

## Build

Run the **Build Cydia RootHide iOS 16** GitHub Actions workflow on the `cydia-roothide-ios16` branch. A successful run creates:

`CydiaInstaller_RootHide_1.1.38-0.1_iOS16.deb`

## Device test order

1. Create a RootHide bootstrap backup/snapshot and confirm Sileo opens.
2. Install the generated DEB from Filza or Sileo.
3. Open Cydia without refreshing first.
4. Refresh sources and confirm no dpkg lock or path errors.
5. Install and remove one harmless package.
6. Close and reopen both Cydia and Sileo.
7. Reboot, jailbreak again and repeat the refresh check.

Uninstall `com.nextsolution.cydia.roothide` immediately if Cydia reports persistent APT/dpkg errors or if Sileo can no longer refresh.

## Licensing and attribution

Cydia is Copyright © Jay Freeman (saurik) and distributed under GNU GPL version 3 or later. The compatibility-layer source in this directory is also distributed under GNU GPL version 3 or later so that the combined work remains redistributable under compatible terms.

This project also uses work from Sam Bingner, RootHide, RootHidePatcher, Theos and Procursus. It is not endorsed by those projects.
