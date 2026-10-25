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

# The browser tests use server/dist, so build first. They skip themselves when no Chrome or
# Firefox is installed.
testserver:
	cd server && npm test

test: testlua testserver

check: formatcheck lint build test

# server/dist is committed and run directly by the plugin, so it must match the source. Fails with
# the list of out-of-date files (changed, deleted or newly produced) and the command that fixes it.
checkbuild: build
	@stale="$$(git status --porcelain -- server/dist)"; \
	if [ -n "$$stale" ]; then \
		echo "server/dist is out of date with server/src. Run 'make build' and commit server/dist."; \
		echo "$$stale"; \
		exit 1; \
	fi
