#!/bin/zsh
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: run-utm-windows-test.zsh <local windows exe>" >&2
    exit 2
fi

vm_name="Zing Win32 ARM64"
local_exe="$1"
guest_exe='C:\Users\Public\zing-win32-live-tests.exe'
guest_result='C:\Users\Public\zing-win32-live-tests.txt'

utmctl file push "$vm_name" "$guest_exe" < "$local_exe"
printf "START\n" | utmctl file push "$vm_name" "$guest_result"
set +e
utmctl exec "$vm_name" --cmd 'C:\Windows\System32\cmd.exe' '/c' "$guest_exe" >/dev/null
exec_status=$?
result="START"
pull_status=1
for _ in {1..30}; do
    result="$(utmctl file pull "$vm_name" "$guest_result" 2>/dev/null)"
    pull_status=$?
    if [[ $pull_status -eq 0 && "$result" != "START" ]]; then
        break
    fi
    sleep 1
done
set -e

if [[ $pull_status -ne 0 ]]; then
    exit "$exec_status"
fi
printf "%s" "$result"

if [[ "$result" != "OK"$'\n' && "$result" != "OK" ]]; then
    exit 1
fi

if [[ $exec_status -ne 0 ]]; then
    exit "$exec_status"
fi
