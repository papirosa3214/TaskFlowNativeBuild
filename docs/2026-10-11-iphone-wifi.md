# iPhone wireless installation diagnosis

2026-10-11: device paired, Developer Mode enabled, DDI compatible. Wired installation succeeded, databaseSequence4444. iPhone unlocked/passcodeRequiredfalse. Mac en0 connected192.168.1.102, IPv6 automatic and link-local address present.

Failed wireless attempt around10:49:50: remotepairingd connection on en0 IPv6 failed with Network is unreachable after10s, followed by CoreDevice4016 (no assertable device service states). This is developer transport failure, not a TaskFlow API response. Root cause of peer reachability is not proven.

Successful10:35 session teardown says No active usage assertions after transfer; this is normal teardown and must not be misdiagnosed as a wireless failure. utun6 is created by RemotePairing for device tunneling; its presence alone does not prove VPN interference.

Controlled check after owner disconnected cable: device info reported connected, paired, transport localNetwork, TCP tunnel. Reinstallation of the previously built app over wireless succeeded (databaseSequenceNumber4452). This verifies discovery, developer services and app transfer without USB in this session. The earlier peer-route failure is intermittent; its underlying trigger is not proven. No pairing reset or network settings changes performed.
