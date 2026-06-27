#!/usr/bin/env bash
# Sourced helper: append-only TSV results log (karpathy format).
results_init(){
  outdir="$1"; direction="$2"; mkdir -p "$outdir"
  {
    printf '# metric_direction: %s\n' "$direction"
    printf 'iteration\ttimestamp\tcommit\tmetric\tdelta\tguard\tstatus\tdescription\n'
  } > "$outdir/results.tsv"
}
results_append(){
  outdir="$1"; mkdir -p "$outdir"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$2" "$ts" "$3" "$4" "$5" "$6" "$7" "$8" >> "$outdir/results.tsv"
}
