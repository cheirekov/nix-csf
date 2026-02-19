# Session Brief

Last updated: 2026-02-19  
Owner: PM/BA + Codex

## 1) Batch contract

- Batch type: `DAY (2-4h)`
- Active ticket: `T-001` (Core module bootstrap)
- Goal: create a working project baseline that users can import with flakes or classic NixOS imports.
- In scope:
  - NixOS module with CSF-inspired options.
  - Runtime nftables apply/refresh path.
  - Team board and governance docs.
- Out of scope:
  - deep integration tests,
  - all CSF parity features.
- Stop/rollback condition:
  - if rule apply design is not deterministic on boot.

## 2) Definition of done

- `services.nixCsf` exists and evaluates.
- `flake.nix` exports module.
- `default.nix` works for non-flake import.
- README includes both usage modes.
- Governance docs exist with next ticket queue.

## 3) End-of-batch result

- Decision: `continue`
- Completed:
  - baseline module and runtime script delivered,
  - board/docs initialized,
  - examples included.
- Next ticket candidate:
  - `T-002` validation pipeline.
