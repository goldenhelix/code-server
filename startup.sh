#!/bin/bash

# Try to set up the private (per user) User Data folder
set +e
mkdir -p $HOME/Workspace/Documents/$USERNAME/code-server
export XDG_DATA_HOME=$HOME/Workspace/Documents/$USERNAME
set -e

# Set up persistent ~/.gitconfig
GITCONFIG_SOURCE="$HOME/.gitconfig"
GITCONFIG_TARGET="$XDG_DATA_HOME/.gitconfig"

# If the target doesn't exist, create an empty file
if [ ! -f "$GITCONFIG_TARGET" ]; then
    echo "Creating empty gitconfig at $GITCONFIG_TARGET"
    touch "$GITCONFIG_TARGET"
fi

# Create symlink if it doesn't exist or is broken
if [ ! -L "$GITCONFIG_SOURCE" ] || [ ! -e "$GITCONFIG_SOURCE" ]; then
    echo "Creating symlink from ~/.gitconfig to $GITCONFIG_TARGET"
    ln -sf "$GITCONFIG_TARGET" "$GITCONFIG_SOURCE"
fi

grep -q 'export PS1=' $HOME/.bashrc 2>/dev/null || echo 'export PS1="$USERNAME:\w\$ "' >> $HOME/.bashrc

# Set the default project folder
DEFAULT_PROJECT_FOLDER="$HOME/Workspace/"

# Use the provided PROJECT_FOLDER or default to DEFAULT_PROJECT_FOLDER
STARTING_FOLDER="${PROJECT_FOLDER:-$DEFAULT_PROJECT_FOLDER}"

# Whether to reveal the integrated terminal panel automatically the first time
# a workspace is opened. Defaults to on; set OPEN_TERMINAL_ON_START=false to
# disable for launch contexts that don't want it.
OPEN_TERMINAL_ON_START="${OPEN_TERMINAL_ON_START:-true}"

# If OPEN_FILE is set, start a background process to open it
if [ ! -z "$OPEN_FILE" ]; then
    (
        # We need the server to start and the socket to be created (user connected) before we can open the file
        sleep 5
        echo "Opening file: $OPEN_FILE"
        export VSCODE_IPC_HOOK_CLI=$(ls /tmp/vscode-ipc-*.sock | head -n 1)
        /opt/code-server/lib/vscode/bin/remote-cli/code-server "$OPEN_FILE"
    ) &
fi

# Your script logic here
echo "Starting in folder: $STARTING_FOLDER"

# agent-host-bridge-host with no bridge port/path makes the VS Code server register
# its agent-host channel as unavailable instead of spawning the agent host and the
# GitHub Copilot CLI it launches (~400 MB RSS together). The VSCode app runs in a
# 1 GiB cgroup, and with those two processes present the OOM killer takes the
# extension host.

/opt/code-server/bin/code-server \
    --disable-telemetry \
    --disable-update-check \
    --allow-shutdown \
    --disable-workspace-trust \
    --locale=$LANG \
    --welcome-text="Welcome to your Golden Helix VSCode environment" \
    --ignore-last-opened \
    --vscode-option open-terminal-on-start=$OPEN_TERMINAL_ON_START \
    --vscode-option agent-host-bridge-host=127.0.0.1 \
    $STARTING_FOLDER