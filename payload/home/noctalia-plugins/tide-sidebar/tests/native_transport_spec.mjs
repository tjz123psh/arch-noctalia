import assert from 'node:assert/strict';
import {encodePackets} from '../native/transport.mjs';
let tests = 0;
const bodies = ['small', 'x'.repeat(65536), '中'.repeat(21845), '😀'.repeat(16384), String.fromCharCode(1).repeat(65536), '"\\\n'.repeat(21845)];
for (const body of bodies) {
    const message = {protocol: 1, instance: 'test-instance', action: 'note-edit', packetId: String(tests), id: 'note-1', body};
    const lines = encodePackets(message);
    for (const line of lines) assert.ok(Buffer.byteLength(line) < 65536, 'every actual stream line must be below 64KiB');
    const packets = lines.map(JSON.parse);
    const restored = packets[0].chunk ? JSON.parse(packets.map(packet => packet.text).join('')) : packets[0];
    assert.deepEqual(restored, message);
    tests++;
}
assert.throws(() => encodePackets({body: 'x'.repeat(1048577)})); tests++;
console.log('native_transport_spec: ' + tests + ' large/Unicode framing cases passed');
