"""Container HEALTHCHECK used by Docker and the ECS task definition (no curl needed)."""

import os
import sys
import urllib.request

URL = f"http://127.0.0.1:{os.environ.get('PORT', '8000')}/healthz"

try:
    with urllib.request.urlopen(URL, timeout=3) as response:
        sys.exit(0 if response.status == 200 else 1)
except OSError:
    sys.exit(1)
