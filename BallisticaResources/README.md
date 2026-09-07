# Local Ballistica resources

This directory is a local-only folder reference copied into the iOS app
bundle. It is intentionally not part of the public source release and may
contain proprietary game data.

From the BombSquadVR-iOS checkout, first prepare an authorized Ballistica checkout:

~~~sh
cd ballistica
make env
make assets-ios
cd ../BombSquadVR
./Scripts/sync_ballistica_assets.sh
~~~

The sync script copies build/assets/ba_data, duplicates
build/assets/pylib-apple as both pylib-apple and pylib, copies the generated
GUI-minimal manifest to ba_data/manifest.json, and stages the content-addressed
files from .cache/assetdata under ba_data/assets. It replaces those generated
destination directories each time; it does not download assets itself and does
not change their licensing status.

If you do not have permission to obtain or use the Ballistica resources, stop
after building the code-only parts and do not attempt to redistribute an app
bundle containing this directory.
