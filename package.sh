npm run build

# Note that lib/vscode/package.json may need the following change (remove --max-old-space-size=8192 )
#    "gulp": "node ./node_modules/gulp/bin/gulp.js",


#export NODE_OPTIONS="--max-old-space-size=16384"
VERSION=4.100.2 NODE_OPTIONS="--max-old-space-size=4096" npm run build:vscode
npm run release

VERSION=4.100.2 npm run package
cd release
npm install --omit=dev
cd ..
npm run release:standalone

./install_system_extensions.sh