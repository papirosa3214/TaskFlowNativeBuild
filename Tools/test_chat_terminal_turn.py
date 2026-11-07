"""Replay the actual terminal-turn Set mutations on the host, without UI tests."""
from pathlib import Path
import re
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[1] / 'Sources/Features/Roles/RoleChatRoomScreen.swift').read_text()
# Execute exactly the mutations performed at playback cleanup and at the
# already-visible completion path; stale snapshots use this same Set guard.
paths = [source.split('private func completeLiveTurn(')[1].split('private func parkedTurn(')[0],
         source.split('onPlaybackComplete: {')[1].split('stoppedTurnIDs')[0]]
with tempfile.TemporaryDirectory() as directory:
    main = Path(directory) / 'main.swift'
    statements = []
    for index, path in enumerate(paths):
        mutation = re.search(r'endedTurnIDs\.(?:remove|insert)\(turn.playbackID\)', path)
        assert mutation, 'terminal cleanup must explicitly retain the turn tombstone'
        statements += ['endedTurnIDs = [turn.playbackID]', mutation.group(),
                       f'precondition(endedTurnIDs.contains(turn.playbackID), "late snapshot resurrected turn at path {index}")']
    main.write_text('struct Turn { let playbackID = "role:turn" }\nlet turn = Turn()\nvar endedTurnIDs: Set<String> = []\n' + '\n'.join(statements))
    subprocess.run(['swiftc', str(main), '-o', directory + '/test'], check=True)
    subprocess.run([directory + '/test'], check=True, capture_output=True)
print('PASS: both completion paths reject late snapshots')
