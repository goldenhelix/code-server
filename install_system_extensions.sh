#!/bin/bash
#
# Bake the marketplace extensions listed in ./extensions.txt into the standalone
# release so they ship as system (built-in) extensions of the image.
#
# Usage:
#   ./install_system_extensions.sh            # install/upgrade everything in extensions.txt
#   ./install_system_extensions.sh --prune    # ...and also delete baked-in marketplace
#                                             # extensions that are no longer listed
#
# extensions.txt: one id per line ("publisher.name" or "publisher.name@1.2.3"),
# blank lines and '#' comments are ignored.
#
# Every id is installed from the marketplace into a throwaway --extensions-dir
# (nothing under ~/.local/share/code-server or ~/.config/code-server is touched),
# any existing "<id>-<version>" dirs for the listed ids are removed from the target
# and the freshly installed dirs are copied in. The script exits 1 if any listed id
# did not install or if an installed extension has a hard dependency that is not
# also listed. It ends by printing a manifest of what is baked in.

set -euo pipefail

EXTENSIONS_FILE="${EXTENSIONS_FILE:-./extensions.txt}"
CODE_SERVER="${CODE_SERVER:-./release-standalone/bin/code-server}"
TARGET_DIR="${TARGET_DIR:-./release-standalone/lib/vscode/extensions}"

PRUNE=0
for arg in "$@"; do
    case "$arg" in
        --prune) PRUNE=1 ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Error: unknown argument '$arg' (only --prune is supported)"; exit 1 ;;
    esac
done

# Check prerequisites
if [ ! -f "$CODE_SERVER" ]; then
    echo "Error: code-server not found at $CODE_SERVER"
    exit 1
fi
if [ ! -f "$EXTENSIONS_FILE" ]; then
    echo "Error: extensions file not found at $EXTENSIONS_FILE"
    exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required (it is already needed by ci/build/build-release.sh)"
    exit 1
fi

# Read extensions file line by line: SPECS keeps "id" or "id@version" as written,
# IDS keeps the bare lowercase id (VS Code compares ids case-insensitively).
SPECS=()
IDS=()
while IFS= read -r extension || [ -n "$extension" ]; do
    extension="${extension%%#*}"                 # strip trailing comments
    extension="$(echo "$extension" | tr -d '[:space:]')"
    if [[ -z "$extension" ]]; then
        continue
    fi
    id="${extension%%@*}"
    if [[ ! "$id" =~ ^[A-Za-z0-9][A-Za-z0-9-]*\.[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then
        echo "Error: '$extension' is not a valid extension id (expected publisher.name[@version])"
        exit 1
    fi
    SPECS+=("$extension")
    IDS+=("${id,,}")
done < "$EXTENSIONS_FILE"

if [ "${#IDS[@]}" -eq 0 ]; then
    echo "Error: no extensions listed in $EXTENSIONS_FILE"
    exit 1
fi

# Throwaway dirs so the build host profile is never touched. An empty
# --builtin-extensions-dir hides the extensions already baked into the target,
# otherwise the CLI reports "already installed" and installs nothing when the
# marketplace version matches the baked-in one.
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/install_system_extensions.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
STAGE_DIR="$WORK_DIR/extensions"
mkdir -p "$STAGE_DIR" "$WORK_DIR/user-data" "$WORK_DIR/builtin"

echo "Installing ${#SPECS[@]} extension(s) into $STAGE_DIR"
INSTALL_ARGS=()
for spec in "${SPECS[@]}"; do
    INSTALL_ARGS+=(--install-extension "$spec")
done

# One CLI invocation for all ids; failures are reported per id below.
# do-not-include-pack-dependencies (a VS Code flag code-server does not model
# itself, hence --vscode-option) keeps the result equal to extensions.txt: pack
# members and dependencies must be listed explicitly to be baked in.
INSTALL_STATUS=0
"$CODE_SERVER" \
    --extensions-dir "$STAGE_DIR" \
    --user-data-dir "$WORK_DIR/user-data" \
    --builtin-extensions-dir "$WORK_DIR/builtin" \
    --config "$WORK_DIR/config.yaml" \
    --vscode-option do-not-include-pack-dependencies \
    "${INSTALL_ARGS[@]}" || INSTALL_STATUS=$?
echo "----------------------------------------"

# Map lowercase id -> "version<TAB>dir" from the throwaway profile's extensions.json
STAGE_JSON="$STAGE_DIR/extensions.json"
if [ ! -f "$STAGE_JSON" ]; then
    echo "Error: $STAGE_JSON was not written; code-server exited with status $INSTALL_STATUS"
    exit 1
fi
declare -A INSTALLED_ID=()
declare -A INSTALLED_VERSION=()
declare -A INSTALLED_DIR=()
while IFS=$'\t' read -r id version location; do
    INSTALLED_ID["${id,,}"]="$id"
    INSTALLED_VERSION["${id,,}"]="$version"
    INSTALLED_DIR["${id,,}"]="$location"
done < <(jq -r '.[] | [.identifier.id, .version, (.location.path // .location.fsPath)] | @tsv' "$STAGE_JSON")

# Every listed id must have installed
FAILED=()
for id in "${IDS[@]}"; do
    if [ -z "${INSTALLED_DIR[$id]:-}" ] || [ ! -f "${INSTALLED_DIR[$id]}/package.json" ]; then
        FAILED+=("$id")
    fi
done
if [ "${#FAILED[@]}" -ne 0 ]; then
    echo "Error: the following extension(s) did not install (code-server exit status $INSTALL_STATUS):"
    printf '  %s\n' "${FAILED[@]}"
    exit 1
fi
if [ "$INSTALL_STATUS" -ne 0 ]; then
    echo "Error: code-server --install-extension exited with status $INSTALL_STATUS"
    exit 1
fi

# Hard dependencies (extensionDependencies) must be listed too, since pack
# members and dependencies are not pulled in automatically.
MISSING_DEPS=0
for id in "${IDS[@]}"; do
    while IFS= read -r dep; do
        [ -z "$dep" ] && continue
        if [ -z "${INSTALLED_DIR[${dep,,}]:-}" ]; then
            echo "Error: $id depends on $dep, which is not listed in $EXTENSIONS_FILE"
            MISSING_DEPS=1
        fi
    done < <(jq -r '.extensionDependencies // [] | .[]' "${INSTALLED_DIR[$id]}/package.json")
done
if [ "$MISSING_DEPS" -ne 0 ]; then
    exit 1
fi

# Copy into the standalone directory, replacing any version already there
mkdir -p "$TARGET_DIR"
for id in "${IDS[@]}"; do
    src="${INSTALLED_DIR[$id]}"
    name="$(basename "$src")"
    # Remove stale "<id>-<version>[-<platform>]" dirs of this id. The digit after the
    # dash keeps e.g. ms-toolsai.jupyter from matching ms-toolsai.jupyter-keymap.
    while IFS= read -r stale; do
        echo "Removing stale $(basename "$stale")"
        rm -rf "$stale"
    done < <(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -iname "${id}-[0-9]*")
    echo "Copying $name"
    cp -R "$src" "$TARGET_DIR/$name"
done

# Marketplace extensions in the target that are not listed any more
# (VS Code's own built-ins have no "-<version>" suffix and are never touched).
UNLISTED=()
while IFS= read -r dir; do
    pkg="$dir/package.json"
    if [ -f "$pkg" ]; then
        dir_id="$(jq -r '"\(.publisher).\(.name)"' "$pkg")"
    else
        dir_id="$(basename "$dir" | sed -E 's/-[0-9].*$//')"   # leftover without a manifest
    fi
    listed=0
    for id in "${IDS[@]}"; do
        if [ "${dir_id,,}" = "$id" ]; then listed=1; break; fi
    done
    if [ "$listed" -eq 0 ]; then
        UNLISTED+=("$dir")
    fi
done < <(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type d -name "*-[0-9]*" | sort)

if [ "${#UNLISTED[@]}" -ne 0 ]; then
    echo "----------------------------------------"
    for dir in "${UNLISTED[@]}"; do
        if [ "$PRUNE" -eq 1 ]; then
            echo "Pruning $(basename "$dir") (not in $EXTENSIONS_FILE)"
            rm -rf "$dir"
        else
            echo "Warning: $(basename "$dir") is baked in but not in $EXTENSIONS_FILE (rerun with --prune to remove)"
        fi
    done
fi

echo "----------------------------------------"
echo "Installed extensions in $TARGET_DIR:"
for id in "${IDS[@]}"; do
    echo "${INSTALLED_ID[$id]} ${INSTALLED_VERSION[$id]}"
done
echo "All extensions processed"
