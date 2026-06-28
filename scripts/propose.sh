#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"

cmd="${1:-}"; [ "$cmd" = "write" ] || shadow_die "usage: propose.sh write <state> <out> <branch>"
sf="${2:-}"; out="${3:-}"; branch="${4:-}"
[ -f "$sf" ] || { echo "propose: state file not found: $sf" >&2; exit 1; }
[ -n "$out" ] && [ -n "$branch" ] || shadow_die "propose: out and branch required"
mkdir -p "$(dirname "$out")"

dir="$(jq -r '.direction' "$sf")"
# best arm: direction-aware over arms with a non-null best
best_id="$(jq -r --arg d "$dir" '
  [.arms[] | select(.best != null)] as $a
  | if ($a|length)==0 then ""
    elif $d=="lower_is_better" then ($a | sort_by(.best) | .[0].id)
    else ($a | sort_by(-.best) | .[0].id) end' "$sf")"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
  printf '# PROPOSAL — Shadow Legion campaign result\n\n'
  printf -- '- generated: %s\n' "$ts"
  printf -- '- metric direction: %s\n' "$dir"
  printf -- '- integration branch: `%s`\n\n' "$branch"

  if [ -n "$best_id" ]; then
    desc="$(jq -r --arg id "$best_id" '.arms[]|select(.id==$id).desc' "$sf")"
    best="$(jq -r --arg id "$best_id" '.arms[]|select(.id==$id).best' "$sf")"
    md="$(jq -r --arg id "$best_id" '.arms[]|select(.id==$id).mean_delta | (.*100|round)/100' "$sf")"
    printf '## Winning approach: %s\n\n' "$desc"
    printf -- '- best metric: **%s** (mean delta %s)\n\n' "$best" "$md"
  else
    printf '## No winning approach\n\nNo arm produced a measured improvement.\n\n'
  fi

  printf '## Integrate manually (the army never pushes or merges)\n\n'
  printf '```bash\n'
  printf 'git merge --ff-only %s        # fast-forward integrate the verified branch\n' "$branch"
  printf '# or, to take just the winning commit:\n'
  printf '# git cherry-pick <commit-from-results.tsv>\n'
  printf '```\n\n'

  printf '## All directions\n\n'
  printf '| arm | approach | attempts | best | mean_delta | dead | reason |\n'
  printf '|---|---|---|---|---|---|---|\n'
  jq -r '.arms[] | "| \(.id) | \(.desc) | \(.attempts) | \(.best // "-") | \(.mean_delta) | \(.dead) | \(.dead_reason // "") |"' "$sf"
  printf '\n'

  deadcount="$(jq -r '[.arms[]|select(.dead==true)]|length' "$sf")"
  if [ "$deadcount" -gt 0 ]; then
    printf '## Dead directions (do not retry)\n\n'
    jq -r '.arms[]|select(.dead==true)|"- **\(.desc)** — \(.dead_reason // "no reason recorded")"' "$sf"
    printf '\n'
  fi
} > "$out"
