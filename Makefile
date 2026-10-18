.PHONY: check lint test

# check runs lint then tests; CI invokes the same targets.
check: lint test

# The libs are sourced fragments without a shebang, so they are linted as bash
# on their own: shellcheck cannot follow the dispatcher's loop over lib/*.sh.
# SC2016 flags the single-quoted jq programs, which must not expand.
lint:
	shellcheck bin/habit-tools.sh hooks/*.sh
	shellcheck -s bash -e SC2016 bin/lib/*.sh

test:
	bats test/
