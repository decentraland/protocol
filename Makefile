BIN="./node_modules/.bin" 
BUF_VERSION=1.8.0
OS = $(shell uname -s)
OS_ARCH = $(shell uname -m)

node_modules/.bin/buf:
	curl -sSL https://github.com/bufbuild/buf/releases/download/v$(BUF_VERSION)/buf-$(OS)-$(OS_ARCH) -o node_modules/.bin/buf
	chmod +x node_modules/.bin/buf

buf-lint: node_modules/.bin/buf
	./node_modules/.bin/buf lint proto/

buf-build: node_modules/.bin/buf
	./node_modules/.bin/buf build proto/

buf-breaking: node_modules/.bin/buf
	./node_modules/.bin/buf breaking proto/ --against 'https://github.com/decentraland/protocol.git#subdir=proto'

test: buf-lint
	bash scripts/test.sh

all: buf-lint buf-build test

install:
	npm i

list-components-ids:
	@bash scripts/list-components-ids.sh

check-component-id:
	@bash scripts/check-component-id.sh $(ID)
