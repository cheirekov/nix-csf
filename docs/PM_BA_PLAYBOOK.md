# PM/BA Playbook

Purpose: keep prioritization deterministic and avoid scope drift.

## Priority policy

1. `P0`: safety break or lockout risk.
2. `P1`: stability/regression.
3. `P2`: quality/usability gap.
4. `P3`: enhancement.

If no `P0/P1`, score candidate tickets:

- User impact (1-5)
- Security impact (1-5)
- Learning speed (1-5)
- Unblock value (0-3)
- Effort (1-5, subtract)

`score = userImpact + securityImpact + learningSpeed + unblockValue - effort`

## Batch rules

- One active ticket only.
- Keep scope frozen inside the active ticket.
- Every done ticket requires:
  - changelog update,
  - board update,
  - session brief update.

## DoD template

```md
## DoD — <ticket>
- Behavior outcome:
  - Module API:
  - Runtime behavior:
- Risk impact:
  - none / explicit
- Validation:
  - commands:
  - observed result:
- Stop/rollback condition:
```
