#!/bin/bash

# Build a Golden Helix docker image for code-server with changes to support App Streaming on VSWarehouse

# Form maintaing the code-server image, add the upstream repository if you haven't already
# git remote add upstream https://github.com/coder/code-server.git

# Fetch the latest changes from upstream
# git fetch upstream

# Checkout your main branch
# git checkout main

# Pop all quilt patches
# quilt pop -a

# If thee are still changes to the vscode lib, reset them
# git -C lib/vscode checkout -- .

# Merge the changes from the latest tagged version to your local main branch
# git merge v4.135.0

# You may need to reset the vscode lib to the latest version (git the hash from git diff lib/vscode)
# git -C lib/vscode reset --hard 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5

# Apply the patches
# quilt push -a

# If a patch fails, you need to merge fix it, for example if shutdown.diff fails
# quilt push -f shutdown.diff # Needed to apply as much of the changes as possible
# Manually fix failed chunks/files
# quilt refresh
# quilt push -a (continue until all patches are applied)

# Handle any merge conflicts if they arise

# Follow the directions under [CONTRIBUTING.md](docs/CONTRIBUTING.md) to build the image
# See ./package.sh for these commands

# git submodule update --init
# quilt push -a
# npm install
# npm run build
# VERSION=4.135.0 npm run build:vscode

# Upstream removed the old release/package/release:standalone 3-step process
# (coder/code-server#7721) -- a single `npm run release` with KEEP_MODULES=1
# now produces a ready-to-run directory directly (see package.sh).
# export RELEASE_PATH=release-standalone
# KEEP_MODULES=1 npm run release
# VERSION=4.135.0 npm run package

# Run install_system_extensions.sh to extensions listed in extensions.txt
# ./install_system_extensions.sh

# Note that lib/vscode/package.json may need the following change (remove --max-old-space-size=8192 )
#    "gulp": "node ./node_modules/gulp/bin/gulp.js",

set -euo pipefail

export VERSION=4.135.0-2

# Ensure we're in the correct directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Add "code" as symlink
ln -sfn code-linux.sh release-standalone/lib/vscode/bin/remote-cli/code

# The bundled node binary and the Copilot CLI are excluded from the build context by .dockerignore

echo "PWD: $PWD"

docker build --no-cache \
  -t registry.goldenhelix.com/public/code-server:${VERSION} .

# Run like (startup.sh reads PROJECT_FOLDER, positional arguments are ignored)
# docker run -it -p 8081:8080 -e PASSWORD=your_secure_password123 -e IDLE_TIMEOUT=2 -e PROJECT_FOLDER=/home/ghuser/Workspace -v /home/rudy/Workspace:/home/ghuser/Workspace registry.goldenhelix.com/public/code-server:4.135.0
