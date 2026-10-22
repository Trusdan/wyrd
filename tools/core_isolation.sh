#!/usr/bin/env bash
# Fail when addons/wyrd contains network, thread, or wait code.
# Comments and strings count. There is no allow-list.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

# Whole-word tokens. Case sensitive, so a lowercase "thread" is not "Thread".
tokens=(
	await
	Thread
	WorkerThreadPool
	Mutex
	Semaphore
	HTTPRequest
	HTTPClient
	StreamPeerTCP
	StreamPeerTLS
	TCPServer
	UDPServer
	PacketPeerUDP
	PacketPeerDTLS
	DTLSServer
	WebSocketPeer
	WebRTCPeerConnection
	WebRTCMultiplayerPeer
	ENetConnection
	ENetMultiplayerPeer
	MultiplayerAPI
	JavaScriptBridge
)

# Call names. The dot is literal; -w keeps OS.execute_with_pipe distinct.
calls=(
	OS.execute
	OS.execute_with_pipe
	OS.create_process
	OS.create_instance
	OS.shell_open
)

# Print each hit as path:line: token. Return 0 when the tree is clean.
scan() {
	local dir="$1"
	local found=0
	local token pattern matches file rest lineno
	for token in "${tokens[@]}"; do
		matches="$(grep -rnwE --include='*.gd' -e "$token" "$dir" || true)"
		if [[ -n "$matches" ]]; then
			while IFS= read -r line; do
				[[ -z "$line" ]] && continue
				file="${line%%:*}"
				rest="${line#*:}"
				lineno="${rest%%:*}"
				printf '%s:%s: %s\n' "$file" "$lineno" "$token"
				found=1
			done <<< "$matches"
		fi
	done
	for token in "${calls[@]}"; do
		pattern="${token//./\\.}"
		matches="$(grep -rnwE --include='*.gd' -e "$pattern" "$dir" || true)"
		if [[ -n "$matches" ]]; then
			while IFS= read -r line; do
				[[ -z "$line" ]] && continue
				file="${line%%:*}"
				rest="${line#*:}"
				lineno="${rest%%:*}"
				printf '%s:%s: %s\n' "$file" "$lineno" "$token"
				found=1
			done <<< "$matches"
		fi
	done
	return "$found"
}

self_test() {
	local tmp bad clean out
	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp"' RETURN
	bad="$tmp/bad"
	clean="$tmp/clean"
	mkdir -p "$bad" "$clean"
	cat > "$bad/planted.gd" << 'EOF'
func ready() -> void:
	await get_tree().process_frame
	var node := HTTPRequest.new()
EOF
	# Whole-word matching must ignore these lookalikes.
	cat > "$clean/ok.gd" << 'EOF'
# await_host is a name, not a wait.
var await_host := 1
var label := "HTTPRequesting"
EOF
	out="$tmp/hits"
	if scan "$bad" > "$out"; then
		echo "core isolation self-test: planted hits were not found" >&2
		exit 1
	fi
	if ! grep -q 'await$' "$out"; then
		echo "core isolation self-test: await was not named" >&2
		cat "$out" >&2
		exit 1
	fi
	if ! grep -q 'HTTPRequest$' "$out"; then
		echo "core isolation self-test: HTTPRequest was not named" >&2
		cat "$out" >&2
		exit 1
	fi
	if ! scan "$clean" > "$tmp/clean-hits"; then
		echo "core isolation self-test: clean tree failed" >&2
		cat "$tmp/clean-hits" >&2
		exit 1
	fi
	echo "core isolation self-test: ok"
}

if [[ "${1:-}" == "--self-test" ]]; then
	self_test
	exit 0
fi
if [[ $# -gt 0 ]]; then
	echo "usage: tools/core_isolation.sh [--self-test]" >&2
	exit 2
fi

cd "$root"
scan "addons/wyrd"
