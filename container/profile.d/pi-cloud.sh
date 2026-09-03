# pi-cloud: make the box's toolchain available to SSH login shells.
# Container ENV (Dockerfile PATH) is NOT inherited by sshd sessions, which reset
# PATH from /etc/login.defs — so export everything tmux/pi/ruby/mise need here.
export PATH="/opt/tmux/bin:/opt/mise-root/local/bin:/opt/mise/shims:${PATH}"
export MISE_DATA_DIR=/opt/mise
export MISE_CONFIG_DIR=/opt/mise-root/config