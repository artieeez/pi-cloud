# pi-cloud: make the box's toolchain available to SSH login shells.
# Container ENV (Dockerfile PATH) is NOT inherited by sshd sessions, which reset
# PATH from /etc/login.defs — so export everything pi/ruby/mise need here, plus
# the context marker and model env keys that the boot herdr server would
# otherwise own alone (agents started from an ssh session get the same env).
export PATH="/opt/nvim/bin:/opt/mise-root/local/bin:/opt/mise/shims:${PATH}"
export MISE_DATA_DIR=/opt/mise
export MISE_CONFIG_DIR=/opt/mise-root/config

# pi-cloud context marker (activates the pi-cloud-context extension).
export PI_CLOUD=1

# Custom-provider env keys for models.json ($VAR resolution); read from the
# sealed pi-auth volume (root-only box; never committed anywhere).
[ -r /secrets/pi/DEEPINFRA_API_KEY ] && export DEEPINFRA_API_KEY="$(cat /secrets/pi/DEEPINFRA_API_KEY)"

# gh cli API token (same sealed pi-auth volume). gh reads GH_TOKEN
# automatically; git pushes stay on the ssh deploy key.
[ -r /secrets/pi/GH_TOKEN ] && export GH_TOKEN="$(cat /secrets/pi/GH_TOKEN)"

# playwright-cli chromium headless shell (baked at /opt/ms-playwright during
# image build) + global config pointing at it: the CLI defaults would look for
# system Google Chrome (channel 'chrome') or the full chrome-for-testing build;
# PLAYWRIGHT_MCP_CONFIG pins browserName=chromium with no channel so the baked
# headless shell is used. sshd resets the container env, so re-export both for
# login shells.
export PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
export PLAYWRIGHT_MCP_CONFIG=/opt/pi-cloud-playwright-cli.config.json
