# Single-ledger data consolidation

## Product decision

FlashCount uses one personal ledger: `生活`.

## Changes

- Startup ensures `生活` is the only ledger.
- Legacy ledgers are removed only after their transactions, budgets, and recurring rules are reassigned to `生活`.
- Imported multi-ledger backups are consolidated immediately.

## Data-safety note

No financial records are discarded by this consolidation; only the legacy ledger containers are removed.
