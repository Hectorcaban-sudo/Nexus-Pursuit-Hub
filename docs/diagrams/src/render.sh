#!/usr/bin/env bash
# Renders every docs/diagrams/src/*.dot to docs/diagrams/<name>.jpg (anti-aliased via Cairo).
# Requires Graphviz and Python 3 with Pillow.
set -euo pipefail
cd "$(dirname "$0")"
for f in *.dot; do
  name="${f%.dot}"
  dot -Tpng:cairo -Gdpi=150 "$f" -o "/tmp/$name.png"
  python3 -c "from PIL import Image; Image.open('/tmp/$name.png').convert('RGB').save('../$name.jpg', 'JPEG', quality=92, optimize=True)"
  echo "rendered $name.jpg"
done
