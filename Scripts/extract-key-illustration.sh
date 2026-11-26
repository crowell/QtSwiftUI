#!/bin/sh
set -eu
source_file=${1:?pass KeyTransparencyIllustration.swift}
output=${2:?pass the preview source path}
# The illustration and its AppKit-dependent hosting dialog share one file.
# Compile the production illustration declaration without the hosting dialog.
awk '
    /^struct KeyTransparencyIllustration: View \{$/ { print "import SwiftUI"; inside = 1 }
    inside { print }
    inside && /^}$/ { complete = 1; exit }
    END { if (!complete) exit 1 }
' "$source_file" > "$output"
