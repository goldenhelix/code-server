#!/bin/bash

# Try to set up the private (per user) User Data folder
set +e
mkdir -p $HOME/Workspace/Documents/$USERNAME/code-server
export XDG_DATA_HOME=$HOME/Workspace/Documents/$USERNAME
set -e

echo 'export PS1="$USERNAME:\w\$ "' >> $HOME/.bashrc

# Set the default project folder
DEFAULT_PROJECT_FOLDER="$HOME/Workspace/"

# Use the provided PROJECT_FOLDER or default to DEFAULT_PROJECT_FOLDER
STARTING_FOLDER="${PROJECT_FOLDER:-$DEFAULT_PROJECT_FOLDER}"

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

/opt/code-server/bin/code-server \
    --disable-telemetry \
    --disable-update-check \
    --allow-shutdown \
    --disable-workspace-trust \
    --locale=$LANG \
    --welcome-text="Welcome to your Golden Helix VSCode environment" \
    --ignore-last-opened \
    $STARTING_FOLDER