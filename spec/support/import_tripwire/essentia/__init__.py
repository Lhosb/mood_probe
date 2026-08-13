import os
from pathlib import Path

Path(os.environ["SONANCE_IMPORT_SENTINEL"]).open("a").write("imported\n")
raise SystemExit(99)
