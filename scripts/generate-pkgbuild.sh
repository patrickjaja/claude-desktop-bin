#!/bin/bash
set -e

VERSION="$1"
MAINTAINER_NAME="${AUR_USERNAME:-Patrick Jaja}"
MAINTAINER_EMAIL="${AUR_EMAIL:-patrickjajaa@gmail.com}"
SHA256SUM="$2"
DOWNLOAD_URL="$3"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version> [sha256sum] [download_url]" >&2
    exit 1
fi

if [ -z "$SHA256SUM" ]; then
    SHA256SUM="SKIP"
fi

if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL="https://claude.ai/api/desktop/win32/x64/exe/latest/redirect"
fi

# Find the PKGBUILD.template and patches
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE_FILE="$PROJECT_DIR/PKGBUILD.template"
PATCHES_DIR="$PROJECT_DIR/patches"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: PKGBUILD.template not found at $TEMPLATE_FILE" >&2
    exit 1
fi

# Generate patch application code for all patches
generate_patches() {
    local patches_code=""

    for patch_file in "$PATCHES_DIR"/*; do
        [ -f "$patch_file" ] || continue

        local filename=$(basename "$patch_file")
        local patch_target=$(grep -m1 '@patch-target:' "$patch_file" | sed 's/.*@patch-target:[[:space:]]*//' | tr -d '\r')
        local patch_type=$(grep -m1 '@patch-type:' "$patch_file" | sed 's/.*@patch-type:[[:space:]]*//' | tr -d '\r')

        if [ -z "$patch_target" ] || [ -z "$patch_type" ]; then
            echo "Warning: Skipping $filename - missing @patch-target or @patch-type" >&2
            continue
        fi

        local patch_content=$(cat "$patch_file")
        local heredoc_marker="${filename//[^a-zA-Z0-9]/_}_EOF"

        patches_code+="    # Applying patch: $filename
    echo \"Applying patch: $filename...\"
"

        case "$patch_type" in
            replace)
                # For replace type, create parent dir and write file directly
                local parent_dir=$(dirname "$patch_target")
                patches_code+="    mkdir -p \"$parent_dir\"
    cat > \"$patch_target\" << '$heredoc_marker'
$patch_content
$heredoc_marker
"
                ;;
            python)
                # For python patches, handle glob patterns in target
                # Exit codes are now captured - patch failure stops the build
                if [[ "$patch_target" == *"*"* ]]; then
                    # Has glob pattern - use find
                    local dir_part=$(dirname "$patch_target")
                    local file_pattern=$(basename "$patch_target")
                    patches_code+="    local target_file=\$(find $dir_part -name \"$file_pattern\" 2>/dev/null | head -1)
    if [ -n \"\$target_file\" ]; then
        if ! python3 - \"\$target_file\" << '$heredoc_marker'
$patch_content
$heredoc_marker
        then
            echo \"ERROR: Patch $filename FAILED - patterns did not match\"
            echo \"Please check if upstream changed the target file structure\"
            exit 1
        fi
    else
        echo \"ERROR: Target not found for pattern: $patch_target\"
        exit 1
    fi
"
                else
                    # Direct path
                    patches_code+="    if ! python3 - \"$patch_target\" << '$heredoc_marker'
$patch_content
$heredoc_marker
    then
        echo \"ERROR: Patch $filename FAILED - patterns did not match\"
        echo \"Please check if upstream changed the target file structure\"
        exit 1
    fi
"
                fi
                ;;
            *)
                echo "Warning: Unknown patch type '$patch_type' for $filename" >&2
                ;;
        esac

        patches_code+="
"
    done

    echo "$patches_code"
}

# Generate patches code to a temp file (avoids bash/awk & interpretation issues)
PATCHES_FILE=$(mktemp)
generate_patches > "$PATCHES_FILE"

# Create output using simple text processing
# 1. Copy template
# 2. Replace simple placeholders with sed
# 3. Replace {{PATCHES}} by reading from file

OUTPUT_FILE=$(mktemp)
trap "rm -f $PATCHES_FILE $OUTPUT_FILE" EXIT

cp "$TEMPLATE_FILE" "$OUTPUT_FILE"

# Replace simple placeholders
sed -i \
    -e "s/{{VERSION}}/$VERSION/g" \
    -e "s/{{SHA256SUM}}/$SHA256SUM/g" \
    -e "s|{{DOWNLOAD_URL}}|$DOWNLOAD_URL|g" \
    -e "s/{{MAINTAINER_NAME}}/$MAINTAINER_NAME/g" \
    -e "s/{{MAINTAINER_EMAIL}}/$MAINTAINER_EMAIL/g" \
    "$OUTPUT_FILE"

# Replace {{PATCHES}} with content from patches file
# Use python for reliable text replacement (no special char issues)
python3 - "$OUTPUT_FILE" "$PATCHES_FILE" << 'PYTHON_EOF'
import sys
output_file = sys.argv[1]
patches_file = sys.argv[2]

with open(output_file, 'r') as f:
    content = f.read()

with open(patches_file, 'r') as f:
    patches = f.read()

content = content.replace('{{PATCHES}}', patches)

with open(output_file, 'w') as f:
    f.write(content)
PYTHON_EOF

cat "$OUTPUT_FILE"
