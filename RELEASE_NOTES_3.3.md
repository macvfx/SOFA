# Version 3.3 - FileVault Recovery-Key Escrow Compliance

The SimpleMDM + SOFA security scripts now report FileVault encryption and recovery-key escrow separately without retaining recovery-key values in ordinary output.

## Script changes

- Full device CSV and JSON include `filevault_key_escrowed`.
- Escrow state is derived from the documented SimpleMDM `filevault_recovery_key` value: non-empty is escrowed, explicit null/empty is not escrowed, and an absent field is unknown.
- Security Report flags FileVault enabled without an escrowed recovery key.
- Unknown FileVault inventory is reported instead of silently treated as enabled or disabled.
- Device caches are sanitized before writing and when older caches are read.
- Ordinary JSON and response exports remove `filevault_recovery_key`.
- User agent updated to `SimpleMDMExporter/3.3`.

## Explicit sensitive export

Actual recovery keys are available only through:

```bash
API_KEY="your-key" ./simpleMDM-devices-vs-SOFA-macOS-update-check-security-review-lastSEEN.sh --include-recovery-keys
```

This option:

- Implies `--force`, so values come from a fresh SimpleMDM request.
- Creates a separate `SENSITIVE_simplemdm_filevault_recovery_keys_*.csv`.
- Restricts file permissions to the owner (`0600`).
- Does not automatically open the sensitive file.

## Companion app

Simple Security Check 3.3 (Build 9) adds fleet-wide escrow indicators, missing-key compliance findings, authenticated per-device key reveal/copy, a separate authenticated sensitive export, and a SQLite migration that purges recovery keys retained by older versions.
