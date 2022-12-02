BIN="./node_modules/.bin" 
BUF_VERSION=1.8.0
OS = $(shell uname -s)
OS_ARCH = $(shell uname -m)

node_modules/.bin/buf:
	curl -sSL https://github.com/bufbuild/buf/releases/download/v$(BUF_VERSION)/buf-$(OS)-$(OS_ARCH) -o node_modules/.bin/buf
	chmod +x node_modules/.bin/buf

buf-lint: node_modules/.bin/buf
	./node_modules/.bin/buf lint proto/
	./node_modules/.bin/buf build proto/
	./node_modules/.bin/buf breaking proto/ --against '.git#branch=main,subdir=proto'

test: buf-lint
	bash scripts/test.sh

install:
	npm i
	rm -rf proto/google || true
	cp -r node_modules/ts-proto/node_modules/protobufjs/google proto/google