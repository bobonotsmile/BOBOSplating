#!/usr/bin/env bash
# Run inside disposable Ubuntu container without Docker socket or GPU access.
set -euo pipefail
fixture=$(mktemp -d '/tmp/bobo install.XXXXXX')
mkdir -p "$fixture/publish-config" "$fixture/mock"
cp /source/dev-config/install.sh "$fixture/install.sh"
printf 'BOBO_PUBLIC_HOST=example.local\n' > "$fixture/.env"
printf 'services: {}\n' > "$fixture/compose.yml"
printf 'cfg() { case "$1" in --ports|BOBO_HTTPS_PORT) echo 9134;; BOBO_PUBLIC_HOST) echo example.local;; esac; }\n' > "$fixture/publish-config/release-common.sh"
for step in prepare load-images install-gpu-runtime start; do
    printf 'echo "%s" >> "$TRACE"\n' "$step" > "$fixture/$step.sh"
done
printf '#!/bin/bash\ncase "$*" in\n"compose up --help") echo --wait;;\n"compose ps -q") echo "${MOCK_RUNNING:-}";;\n"info --format"*) echo "${MOCK_RUNTIME:-present}";;\nesac\n' > "$fixture/mock/docker"
printf '#!/bin/bash\nread -r runtime\n[[ "$runtime" == present ]]\n' > "$fixture/mock/python3"
printf '#!/bin/bash\necho "${MOCK_PORT:-}"\n' > "$fixture/mock/ss"
printf '#!/bin/bash\nexit 0\n' > "$fixture/mock/nvidia-smi"
chmod +x "$fixture/mock/"*
cd "$fixture"
sha256sum install.sh publish-config/release-common.sh prepare.sh load-images.sh install-gpu-runtime.sh start.sh > checksums.txt
export PATH="$fixture/mock:$PATH" TRACE="$fixture/trace"
run_case() {
    local label=$1 expected=$2 input=$3
    : > "$TRACE"
    set +e
    printf '%s\n' "$input" | bash ./install.sh > "$fixture/output" 2>&1
    result=$?
    set -e
    if [[ $expected == success ]]; then [[ $result == 0 ]]; else [[ $result != 0 ]]; fi
    echo "PASS: $label"
}
run_case 'existing runtime reused' success ''
! grep -q install-gpu-runtime "$TRACE"
grep -q start "$TRACE"
export MOCK_RUNTIME=missing
run_case 'declined restart does not install or start' failure no
! grep -Eq 'install-gpu-runtime|start' "$TRACE"
run_case 'explicit restart installs then starts' success RESTART
[[ $(tail -2 "$TRACE" | tr '\n' ' ') == 'install-gpu-runtime start ' ]]
export MOCK_RUNTIME=present MOCK_PORT=occupied
run_case 'occupied port stops before preparation' failure ''
[[ ! -s "$TRACE" ]]
unset MOCK_PORT
export MOCK_RUNNING=container-id
run_case 'running instance is preserved' failure ''
[[ ! -s "$TRACE" ]]
unset MOCK_RUNNING
printf '# tampered\n' >> prepare.sh
run_case 'damaged package stops before execution' failure ''
[[ ! -s "$TRACE" ]]
echo 'All 6 installer control-flow checks passed (host operations mocked).'
