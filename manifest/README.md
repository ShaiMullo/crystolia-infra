# Crystolia platform manifest

Single source of truth for every Crystolia market (country/locale/domain). Adding
a new market (e.g. Germany) is **one record** in `domains.manifest.yaml` plus a
provisioning apply — no edits to deploy scripts, Terraform variables or app
constants.

## Files
| File | Role |
|---|---|
| `domains.manifest.yaml` | **Canonical, human-authored** source of truth. Edit this. |
| `domains.lock.json` | **Generated**, fully-resolved (defaults merged). Consumed by Terraform, the app, deploy scripts and CI. Do not hand-edit. |
| `domains.schema.json` | JSON Schema (draft-07) validating the resolved lock. |
| `generate.py` | Resolves YAML → lock and validates against the schema. |
| `requirements.txt` | `PyYAML`, `jsonschema`. |

## Usage
```bash
pip install -r requirements.txt
python3 generate.py          # regenerate domains.lock.json + validate
python3 generate.py --check  # CI: fail if the lock is stale or invalid
```

## Status
**Step 0 — data only.** The manifest mirrors current AWS + repo reality; no
consumer is wired yet (Terraform, deploy scripts and the app still use their own
literals). Subsequent steps wire consumers as a pure, zero-drift refactor.

`crystolia.co.il` is `status: planned` (Route53 zone only — no bucket, CloudFront
or ACM cert); the manifest models it but provisions nothing.
