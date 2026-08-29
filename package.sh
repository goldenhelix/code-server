npm run build

# Note that lib/vscode/package.json may need the following change (remove --max-old-space-size=8192 )
#    "gulp": "node ./node_modules/gulp/bin/gulp.js",


#export NODE_OPTIONS="--max-old-space-size=16384"
VERSION=4.135.0 NODE_OPTIONS="--max-old-space-size=4096" npm run build:vscode

# Upstream removed the old release/package/release:standalone 3-step process
# (coder/code-server#7721, "Use VS Code packaging for releases") in favor of a
# single `npm run release` that can also bundle pruned node_modules directly via
# KEEP_MODULES=1 (this replaces the old separate `cd release && npm install
# --omit=dev` step). RELEASE_PATH keeps our output at ./release-standalone to
# match what build.sh, the Dockerfile, and install_system_extensions.sh expect.
export RELEASE_PATH=release-standalone
KEEP_MODULES=1 npm run release

VERSION=4.135.0 npm run package

# ./install_system_extensions.sh