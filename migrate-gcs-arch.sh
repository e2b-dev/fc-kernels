#!/bin/bash
# Copies kernel files from x86_64/ to amd64/ subdirectories in GCS buckets.
#
# The infra orchestrator's TargetArch() normalizes x86_64 -> amd64 (Go convention),
# so kernels stored under x86_64/ are never found by the arch-aware path resolution,
# causing a gcsfuse stat penalty on every sandbox create.
#
# Usage:
#   ./migrate-gcs-arch.sh <bucket>                     # dry-run: show what would be copied
#   ./migrate-gcs-arch.sh <bucket> --apply              # copy x86_64/ -> amd64/
#   ./migrate-gcs-arch.sh <bucket> --delete-old         # dry-run: show what old x86_64/ files would be deleted
#   ./migrate-gcs-arch.sh <bucket> --delete-old --apply # actually delete old x86_64/ files
#
# Recommended workflow:
#   1. ./migrate-gcs-arch.sh gs://my-bucket              # review what will be copied
#   2. ./migrate-gcs-arch.sh gs://my-bucket --apply       # copy to amd64/
#   3. ... verify everything works ...
#   4. ./migrate-gcs-arch.sh gs://my-bucket --delete-old  # review what will be deleted
#   5. ./migrate-gcs-arch.sh gs://my-bucket --delete-old --apply  # clean up old x86_64/

set -euo pipefail

BUCKET="${1:?Usage: $0 <bucket> [--apply] [--delete-old]}"
shift

APPLY=false
DELETE_OLD=false
for arg in "$@"; do
  case "$arg" in
    --apply)     APPLY=true ;;
    --delete-old) DELETE_OLD=true ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

# Normalize bucket name — strip gs:// prefix if provided, we add it back
BUCKET="${BUCKET#gs://}"

echo "Scanning gs://${BUCKET} for x86_64/ paths..."
echo ""

objects=$(gsutil ls -r "gs://${BUCKET}/**/x86_64/**" 2>/dev/null || true)

if [[ -z "$objects" ]]; then
  echo "No x86_64/ paths found in gs://${BUCKET}"
  exit 0
fi

count=0
if [[ "$DELETE_OLD" == true ]]; then
  while IFS= read -r src; do
    [[ -z "$src" ]] && continue
    [[ "$src" == */ ]] && continue

    if [[ "$APPLY" == true ]]; then
      echo "  DELETE  $src"
      gsutil rm "$src"
    else
      echo "  [dry-run] would delete  $src"
    fi
    ((count++)) || true
  done <<< "$objects"

  echo ""
  echo "Total: $count objects"
  if [[ "$APPLY" != true ]]; then
    echo ""
    echo "This was a dry run. Add --apply to actually delete."
  fi
else
  while IFS= read -r src; do
    [[ -z "$src" ]] && continue
    [[ "$src" == */ ]] && continue

    dst="${src/\/x86_64\///amd64/}"

    if [[ "$APPLY" == true ]]; then
      echo "  COPY  $src"
      echo "    ->  $dst"
      gsutil cp "$src" "$dst"
    else
      echo "  [dry-run] $src"
      echo "         -> $dst"
    fi
    ((count++)) || true
  done <<< "$objects"

  echo ""
  echo "Total: $count objects"
  if [[ "$APPLY" != true ]]; then
    echo ""
    echo "This was a dry run. Add --apply to actually copy."
  fi
fi
