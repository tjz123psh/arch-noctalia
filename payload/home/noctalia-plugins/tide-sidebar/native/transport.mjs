// Pure framing protocol: never place a >64 KiB line on Noctalia runStream.
export function encodePackets(message, limit = 24000) {
    const text = JSON.stringify(message);
    const bytes = new TextEncoder().encode(text).length;
    if (bytes > 1048576) throw new Error('transport message too large');
    if (bytes <= limit) return [text];
    const chunks = [];
    let part = '', count = 0;
    for (const point of text) {
        part += point;
        if (++count >= 5000) { chunks.push(part); part = ''; count = 0; }
    }
    if (part) chunks.push(part);
    return chunks.map((piece, index) => JSON.stringify({protocol: 1, instance: message.instance,
        chunk: message.packetId, part: index + 1, parts: chunks.length, text: piece}));
}
