# Substitute BIN for your bin directory.# Substitute VERSION for the current released version.
BIN="./node_modules/.bin" 
VERSION="1.8.0"
curl -sSL "https://github.com/bufbuild/buf/releases/download/v${VERSION}/buf-$(uname -s)-$(uname -m)" -o "${BIN}/buf"
chmod +x "${BIN}/buf"