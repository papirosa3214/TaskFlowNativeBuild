#!/usr/bin/env python3
"""Exercise production routines loading on macOS with a gated API double; no simulator."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='routines-loading-') as tmp:
    binary = Path(tmp) / 'tests'
    subprocess.run(['swiftc', '-parse-as-library', '-D', 'ROUTINES_HOST_TEST',
                    str(root / 'Sources/Core/Models/Schedule.swift'),
                    str(root / 'Sources/Features/Routines/RoutinesViewModel.swift'),
                    str(root / 'Tests/RoutinesLoadingTests.swift'), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
