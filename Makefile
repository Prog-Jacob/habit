.PHONY: check lint test

# check runs lint then tests; CI invokes the same targets.
check: lint test

# Lint from the entry points so -x follows every sourced lib and analyzes the
# assembled program (the libs are sourced fragments, not standalone scripts).
# SC1091 (unfollowable source paths) is the only remaining noise; silence it.
lint:
	shellcheck -x -e SC1091 bin/habit-tools.sh hooks/*.sh install.sh

test:
	bats test/
