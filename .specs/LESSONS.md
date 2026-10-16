# LESSONS - auto-maintained by scripts/lessons.py

> Machine-owned. Do NOT hand-edit. Changes are overwritten on the next `lessons.py` write.
> Canonical state lives in `.specs/lessons.json`. Edit lessons only via the script.
> promote_threshold=2 distinct features · window_days=45 · quarantine_threshold=2

## Confirmed (load these at Specify/Design)

Corroborated across multiple features. Safe to apply as guidance.

_none_

## Candidates (under observation - do NOT load as guidance yet)

Seen once or not yet corroborated. Tracked, not trusted.

### L-001 - Treat TOML literal strings as equal to basic strings when deciding a config value is already required, or the idempotence guard rewrites semantically-compliant input

- signal: `spec_precision_gap` · recurrence: 1 feature(s) · scope: `container/herdr-config` · harmful: 0
- features: herdr-pane-config-guarantee
- evidence: container/herdr-pane-config.sh:214 (container/herdr-config)
- last seen: 2026-10-15T22:22:59Z

### L-002 - Point each spec acceptance criterion at a gate assertion that exercises it; a profile-file grep is not a pane-environment assertion

- signal: `spec_precision_gap` · recurrence: 1 feature(s) · scope: `scripts/gates` · harmful: 0
- features: herdr-pane-config-guarantee
- evidence: scripts/validate-herdr-pane-config.sh:184 (scripts/gates)
- last seen: 2026-10-15T22:22:59Z

### L-003 - State a gate's real runtime dependency floor (coreutils/grep/diff), not 'bash and awk only'

- signal: `spec_precision_gap` · recurrence: 1 feature(s) · scope: `scripts/gates` · harmful: 0
- features: herdr-pane-config-guarantee
- evidence: scripts/validate-herdr-pane-config.sh:60 (scripts/gates)
- last seen: 2026-10-15T22:22:59Z

### L-004 - Strip a TOML inline comment whether or not whitespace precedes the hash, or a valid compliant config gets rewritten

- signal: `spec_precision_gap` · recurrence: 1 feature(s) · scope: `container/herdr-config` · harmful: 0
- features: herdr-pane-config-guarantee
- evidence: container/herdr-pane-config.sh:136 (container/herdr-config)
- last seen: 2026-10-15T22:29:51Z

## Quarantined (failed when applied - ignore)

A confirmed lesson that recurred alongside failure. Kept for the maintainer to review.

_none_
