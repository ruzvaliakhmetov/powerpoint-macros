#!/bin/bash
# macOS PowerPoint: add a custom RibbonX tab and five bundled PNG icons
# to an already exported .ppam. The original .ppam is never overwritten.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && /bin/pwd)"
if (( $# > 0 )); then
    SOURCE="$1"
else
    SOURCE="$(/usr/bin/osascript -e 'POSIX path of (choose file with prompt "Select MyTools.ppam exported from PowerPoint")')"
fi

if [[ ! -f "$SOURCE" || "$SOURCE" != *.[pP][pP][aA][mM] ]]; then
    printf 'ERROR: Please choose an existing .ppam PowerPoint add-in.\n' >&2
    exit 1
fi

for f in "$SCRIPT_DIR/customUI14.xml" "$SCRIPT_DIR/customUI14.xml.rels" \
         "$SCRIPT_DIR/icons/corner_copy.png" "$SCRIPT_DIR/icons/corner_paste.png" \
         "$SCRIPT_DIR/icons/gallery.png" "$SCRIPT_DIR/icons/video_geometry_copy.png" \
         "$SCRIPT_DIR/icons/video_geometry_paste.png"; do
    if [[ ! -f "$f" ]]; then
        printf 'ERROR: Missing file: %s\nPlease keep the installer with its icons folder.\n' "$f" >&2
        exit 1
    fi
done

WORK="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp/}mytools-icons.XXXXXXXX")"
trap '/bin/rm -rf "$WORK"' EXIT
/usr/bin/unzip -qq "$SOURCE" -d "$WORK"

REL="$WORK/_rels/.rels"
TYPES="$WORK/[Content_Types].xml"
if [[ ! -f "$REL" || ! -f "$TYPES" || ! -f "$WORK/ppt/presentation.xml" ]]; then
    printf 'ERROR: This is not a PowerPoint Open XML add-in.\n' >&2
    exit 1
fi

if [[ ! -s "$WORK/ppt/vbaProject.bin" ]]; then
    printf 'ERROR: This .ppam contains no VBA project.\n' >&2
    printf 'Before export, run CopyCornerRadius from the macro dialog in the .pptm.\n' >&2
    exit 1
fi

if /usr/bin/grep -q '/relationships/ui/extensibility' "$REL"; then
    printf 'ERROR: The add-in already has a custom Ribbon.\n'
    printf 'Export a fresh .ppam from MyTools.pptm, then run the installer again.\n'
    exit 1
fi

# Register Ribbon XML in the package's root relationships.
/usr/bin/perl -0777 -pi -e 's#</Relationships>#<Relationship Id="myToolsRibbon2026" Type="http://schemas.microsoft.com/office/2007/relationships/ui/extensibility" Target="customUI/customUI14.xml"/></Relationships>#' "$REL"
if ! /usr/bin/grep -q 'myToolsRibbon2026' "$REL"; then
    printf 'ERROR: Could not add Ribbon relationship.\n' >&2
    exit 1
fi

# Register the new parts' content types.
if ! /usr/bin/grep -q 'PartName="/customUI/customUI14.xml"' "$TYPES"; then
    /usr/bin/perl -0777 -pi -e 's#</Types>#<Override PartName="/customUI/customUI14.xml" ContentType="application/xml"/></Types>#' "$TYPES"
fi
if ! /usr/bin/grep -Eq 'Extension[[:space:]]*=[[:space:]]*"png"' "$TYPES"; then
    /usr/bin/perl -0777 -pi -e 's#</Types>#<Default Extension="png" ContentType="image/png"/></Types>#' "$TYPES"
fi

/bin/mkdir -p "$WORK/customUI/_rels" "$WORK/customUI/images"
/bin/cp "$SCRIPT_DIR/customUI14.xml" "$WORK/customUI/customUI14.xml"
/bin/cp "$SCRIPT_DIR/customUI14.xml.rels" "$WORK/customUI/_rels/customUI14.xml.rels"
/bin/cp "$SCRIPT_DIR/icons/"*.png "$WORK/customUI/images/"

FOLDER="$(/usr/bin/dirname "$SOURCE")"
FILE="$(/usr/bin/basename "$SOURCE")"
STEM="${FILE%.*}"
TARGET="$FOLDER/${STEM}-Ribbon.ppam"
N=2
while [[ -e "$TARGET" ]]; do
    TARGET="$FOLDER/${STEM}-Ribbon-$N.ppam"
    N=$((N + 1))
done

( cd "$WORK" && /usr/bin/zip -q -X -r "$TARGET" . -x '*.DS_Store' '__MACOSX/*' )
/usr/bin/unzip -tq "$TARGET" >/dev/null

printf '\nCreated add-in with Ribbon and five icons:\n%s\n\n' "$TARGET"
printf 'In PowerPoint: Tools > PowerPoint Add-ins > + > select this file.\n'
