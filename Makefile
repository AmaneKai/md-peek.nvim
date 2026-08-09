.PHONY: build format formatcheck lint check test testlua testserver checkbuild

build:
	cd server && npm run build

format:
	npm run format
	stylua lua tests

formatcheck:
	npm run format:check
	stylua --check lua tests

lint:
	npm run lint
	cd server && npm run check

testlua:
	nvim --headless --noplugin -u NONE -i NONE -c "lua dofile('tests/smoke.lua')" -c "qa!"

testserver:
	cd server && npm test

test: testlua testserver

check: formatcheck lint test build

checkbuild: build
	git diff --exit-code server/dist
