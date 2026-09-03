# Agent Environment: pi-cloud box (artr OKE cluster)

## Location
- OS: Debian bookworm (ARM64) in Kubernetes on OCI (artr cluster, oracle-cluster context)
- Hostname: pi-cloud pod
- Home: /root
- Workspace: /workspace (persistent volume; clone repos here: artr-gitops, home, oracle-cluster, pi-config, pi-cloud, ...)
- SSH: key-only, root; attach via `tmux attach -t pi` (or run `pi` inside a new window with Ctrl+B c)

## Tooling
- pi CLI: global npm install (@earendil-works/pi-coding-agent), Node 24
- Ruby: mise-managed at /opt/mise; use `mise exec`/`mise install` per repo (.ruby-version aware). Home repo uses ruby 4.0.5.
- Git: ~/.ssh/id_ed25519 deploy key (read/write on artieeez repos); github.com in known_hosts.
- LLM auth: ~/.pi/agent/auth.json (opencode-go provider; also deepseek/google entries if sealed).
  Default provider: opencode-go (https://opencode.ai/zen/go/v1). Refresh catalogs with `pi update --models`.

## Conventions (same as on the Mac)
- All code, comments, commits, and docs in English.
- Global instructions in /workspace/*/AGENTS.md per repo.
- Agents do not commit or push unless the human asks (repos follow their own AGENTS.md).
- Roadmaps/product questions → Hermes (ask_hermes) when configured; this box may not have hermes-acp wired yet.