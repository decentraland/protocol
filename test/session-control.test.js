const assert = require('node:assert/strict')
const { ServerPacket, KickedMessage, SessionStatusMessage, SessionStatus, KickedReason } = require('../out-js/decentraland/kernel/comms/v3/archipelago.gen')
const fixtures = require('./fixtures/session-control.json')
for (const fixture of fixtures) {
  const type = { ServerPacket, KickedMessage, SessionStatusMessage }[fixture.type]
  assert.ok(type, fixture.type + ' must be generated')
  const bytes = Buffer.from(fixture.hex, 'hex')
  const expected = type.fromJSON(fixture.json)
  assert.deepEqual(type.decode(bytes), expected, fixture.name + ': decode')
  assert.deepEqual(Buffer.from(type.encode(expected).finish()), bytes, fixture.name + ': encode')
}
assert.equal(KickedReason.KR_NEW_SESSION, 0)
assert.equal(KickedReason.KR_BANNED, 1)
assert.equal(SessionStatus.UNSPECIFIED, 0)
assert.equal(SessionStatusMessage.decode(Buffer.alloc(0)).state, SessionStatus.UNSPECIFIED)
assert.equal(KickedMessage.decode(Buffer.alloc(0)).reason, KickedReason.KR_NEW_SESSION)
// Unknown binary enums must not be interpreted as confirmed supersession.
assert.equal(KickedMessage.decode(Buffer.from('0863', 'hex')).reason, 99)
assert.equal(SessionStatusMessage.decode(Buffer.from('0863', 'hex')).state, 99)
// A pre-amendment reader ignores the new oneof tag rather than interpreting it as an assignment.
const protobuf = require('protobufjs')
const oldPacket = protobuf.parse('syntax="proto3"; message Kicked { int32 reason=1; } message OldPacket { oneof message { Kicked kicked=6; } }').root.lookupType('OldPacket')
assert.equal(oldPacket.decode(Buffer.from('3a05080110dc0b', 'hex')).message, undefined)
assert.equal(oldPacket.decode(Buffer.from('3200', 'hex')).kicked.reason, 0)
console.log('PASS: ' + fixtures.length + ' wire goldens, defaults and unknown enums')
