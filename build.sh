#!/usr/bin/env bash
#
# Build helper for the minecraft-plugins ecosystem.
# Wraps ./gradlew so building one module or all of them is one short command.
# Deployable jars always end up in ./jar/<module>.jar (handled by collectJar).
#
# Usage:
#   ./build.sh                # build everything (./gradlew build)
#   ./build.sh core           # build only minecraft-plugin-core
#   ./build.sh money          # build only minecraft-plugin-money
#   ./build.sh core money     # build the listed modules
#   ./build.sh -c             # clean build everything
#   ./build.sh -c money       # clean build only money
#   ./build.sh -l             # list available modules
#
# Module names are the short suffix (e.g. "money" == :minecraft-plugin-money).

set -euo pipefail

cd "$(dirname "$0")"

GRADLEW="./gradlew"
PREFIX="minecraft-plugin-"

# Discover modules from settings.gradle.kts so this stays in sync automatically.
discover_modules() {
  grep -oE 'include\("'"$PREFIX"'[a-z0-9-]+"\)' settings.gradle.kts \
    | sed -E 's/.*"'"$PREFIX"'([a-z0-9-]+)".*/\1/'
}

clean=0
args=()
for arg in "$@"; do
  case "$arg" in
    -c|--clean) clean=1 ;;
    -l|--list)
      echo "Available modules:"
      discover_modules | sed 's/^/  /'
      exit 0
      ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
    *) args+=("$arg") ;;
  esac
done

tasks=()
[[ "$clean" == 1 ]] && tasks+=("clean")

if [[ ${#args[@]} -eq 0 ]]; then
  # No module given -> build the whole ecosystem.
  tasks+=("build")
else
  for m in "${args[@]}"; do
    tasks+=(":${PREFIX}${m}:build")
  done
fi

echo "==> $GRADLEW ${tasks[*]}"
"$GRADLEW" "${tasks[@]}"

echo
echo "==> Deployable jars in ./jar:"
ls -1 jar/ 2>/dev/null | sed 's/^/  /' || echo "  (none)"
