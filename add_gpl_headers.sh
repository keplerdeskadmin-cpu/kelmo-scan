#!/usr/bin/env bash
# bash add_gpl_headers.sh "Kelmo"   – prepends the GPLv3 notice to .dart/.kt files that lack it
NAME="${1:-<YOUR NAME>}"
HDR="// Kelmo Scan - document scanner
// Copyright (C) 2026 ${NAME}
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 of the License.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
"
find lib android/app/src/main/kotlin \( -name '*.dart' -o -name '*.kt' \) -print0 |
while IFS= read -r -d '' f; do
  if ! grep -q "GNU General Public License" "$f"; then
    { printf '%s\n' "$HDR"; cat "$f"; } > "$f.tmp" && mv "$f.tmp" "$f"
    echo "header added: $f"
  fi
done
