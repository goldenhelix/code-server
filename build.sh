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

# Merge the changes from upstream/main to your local main branch
# git merge upstream/main

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
# VERSION=4.96.2 npm run build:vscode
# npm run release

# VERSION=4.96.2 npm run package
# cd release
# npm install --omit=dev
# cd ..
# npm run release:standalone

# Run install_system_extensions.sh to extensions listed in extensions.txt
# ./install_system_extensions.sh

# Note that lib/vscode/package.json may need the following change (remove --max-old-space-size=8192 )
#    "gulp": "node ./node_modules/gulp/bin/gulp.js",

# Add "code" as symlink
cd release-standalone/lib/vscode/bin/remote-cli/
ln -f -s code-linux.sh code
cd ../../../../../

export VERSION=4.98.0-rc.1

# Ensure we're in the correct directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Temporarily move the bundled node out of the way
if [ -f "release-standalone/lib/node" ]; then
    mv release-standalone/lib/node ./node
fi

echo "PWD: $PWD"

docker build --no-cache \
  -t registry.goldenhelix.com/public/code-server:${VERSION} .

# Move the bundled node back
if [ -f "./node" ]; then
    mv ./node release-standalone/lib/node
fi

# Run like
# docker run -it  -p 8081:8080 -e PASSWORD=your_secure_password123 -e PORT=8080 -e IDLE_TIMEOUT=2  registry.goldenhelix.com/public/code-server:4.98.0-rc.1 /home/ghuser/Workspace/
