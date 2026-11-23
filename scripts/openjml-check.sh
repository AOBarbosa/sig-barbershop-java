#!/usr/bin/env bash
# Placeholder for the OpenJML verification (implemented in Etapa 6).
#
# Planned usage:
#   OPENJML_HOME=/path/to/openjml scripts/openjml-check.sh
#
# Etapa 6 will replace this with scripts/verify-esc.sh, verify-rac.sh and
# verify-all.sh, reading the classes to verify from verification/targets.txt
# and writing logs to docs/verification/logs/.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -z "${OPENJML_HOME:-}" ]; then
  echo "OPENJML_HOME is not set. Install OpenJML (macOS/Linux; Windows only via WSL)"
  echo "and export OPENJML_HOME pointing to its directory."
  exit 2
fi

if [ ! -x "$OPENJML_HOME/openjml" ]; then
  echo "openjml executable not found in $OPENJML_HOME"
  exit 2
fi

echo "OpenJML found at $OPENJML_HOME — verification targets not defined yet (Etapa 6)."
exit 0
