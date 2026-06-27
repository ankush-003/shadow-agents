#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"
[ -n "$cmd" ] || { echo "refuse: empty command" >&2; exit 1; }

refuse(){ echo "refuse: $1" >&2; exit 1; }

case "$cmd" in
  *"rm -rf"*|*"rm -fr"*)            refuse "recursive force delete" ;;
  *":(){"*)                         refuse "fork bomb" ;;
  *"| sh"*|*"|sh"*|*"| bash"*|*"|bash"*) refuse "pipe to shell" ;;
  *"git push"*)                     refuse "git push (no remote writes)" ;;
  *"sudo "*)                        refuse "sudo escalation" ;;
  *"mkfs"*|*"dd if="*)              refuse "disk-destructive command" ;;
  *"> /etc"*|*">/etc"*)             refuse "write to /etc" ;;
  *"AWS_SECRET"*|*"PRIVATE KEY"*|*"password="*) refuse "credential literal" ;;
esac
echo "ok"
