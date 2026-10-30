#!/usr/bin/env python3
"""Compile the Composio screen model and its host XCTest on macOS; no simulator."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
sources = [
    'Sources/Core/Models/RoleComposio.swift',
    'Sources/Core/Networking/ResponseCache.swift',
    'Sources/Core/Networking/ComposioCatalogCache.swift',
    'Sources/Features/Settings/ComposioIntegrationsViewModel.swift',
]
for path in sources:
    if not (root / path).exists():
        raise SystemExit(f'RED: {path} is absent')
with tempfile.TemporaryDirectory(prefix='composio-screen-cache-') as tmp:
    binary = Path(tmp) / 'tests'
    subprocess.run(['swiftc', '-parse-as-library', '-D', 'COMPOSIO_HOST_TEST',
                    *[str(root / path) for path in sources],
                    str(root / 'Tests/ComposioScreenCacheTests.swift'), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
