.PHONY: format formatcheck lint test testlua check

format:
	stylua lua tests

formatcheck:
	stylua --check lua tests

# Style and syntax are covered by stylua and by loading every module in the smoke tests.
lint: formatcheck

testlua:
	nvim -l tests/smoke.lua

test: testlua

check: formatcheck test
