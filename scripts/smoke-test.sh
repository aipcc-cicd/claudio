#!/usr/bin/env bash
FAIL=0

check() {
	out=$(eval "$2" 2>&1)
	if [ $? -eq 0 ]; then
		echo "PASS: $1"
	else
		echo "FAIL: $1"
		echo "$out"
		FAIL=1
	fi
}

check "claude --version" "claude --version"
check "gcloud --version" "gcloud --version"

for bin in skopeo podman git jq python3; do
	check "$bin on PATH" "command -v $bin"
done

check "entrypoint.sh syntax" "bash -n /usr/local/bin/entrypoint.sh"
check "claudio-plugin installed" "claude plugin list 2>&1 | grep -q claudio-plugin"

for script in /usr/local/bin/pt-manager.sh /usr/local/bin/stream-claude.py; do
	check "$script executable" "test -x $script"
done

exit $FAIL
