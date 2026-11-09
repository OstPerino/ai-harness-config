Source: https://github.com/nextlevelbuilder/ui-ux-pro-max-skill/tree/4f2dbb67e64969a9a30ab00742f2d55d66ddec2b

License: MIT, retained in LICENSE.txt.

Reviewed 2026-11-09. Vendored src/ui-ux-pro-max/data and four runtime scripts. The JavaFX negative example uses a neutral absolute path instead of a user-home path. Local patch in design_system.py includes the project slug in generated MASTER/page references so they resolve to the persisted files. Scripts use the Python standard library, read bundled data and only persist design files when --persist is requested. No package installation, network calls or subprocess launch. The Codex entrypoint is local; upstream templates and development tooling are not installed. Dataset provenance is preserved in data/data-provenance.json.
