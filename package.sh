npm run build
# VERSION=4.96.2 npm run build:vscode
npm run release

VERSION=4.96.2 npm run package
cd release
npm install --omit=dev
cd ..
npm run release:standalone
