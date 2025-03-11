npm run build
#export NODE_OPTIONS="--max-old-space-size=16384" 
VERSION=4.98.0-rc.1 npm run build:vscode
npm run release

VERSION=4.98.0-rc.1 npm run package
cd release
npm install --omit=dev
cd ..
npm run release:standalone

./install_system_extensions.sh