# Pinned browser SQLite runtime

Copied without editing from the installed official `drift` 2.35.2 package:

| Asset | Origin inside drift 2.35.2 | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `drift_worker.js` | `drift_worker.js` | 360104 | `191fc9db018d2bbecb1723e81118fcf2c5c094df8644c2fcba2ed51df061e90a` |
| `sqlite3.wasm` | `extension/devtools/build/sqlite3.wasm` | 750007 | `fbcd2e8214f9231ea961e1b7706a22dd1194cfbfe6f26f13841b5aa7a0be1a1f` |

The workspace locks drift 2.35.2 and sqlite3 3.7.0. These assets are declared in
the platform package and served from the same origin as the app; no runtime CDN
is needed. Drift is MIT licensed and SQLite is public domain. Retain generated
Flutter third-party notices in the release. Confirm new runtime compatibility
and rerun the actual encrypted SQLite restart probe before changing these files.

Upstream setup: https://drift.simonbinder.eu/platforms/web/
Upstream package: https://pub.dev/packages/drift/versions/2.35.2
