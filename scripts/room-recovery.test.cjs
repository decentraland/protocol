const { test } = require('node:test')
const assert = require('node:assert/strict')
const protobuf = require('protobufjs')
const {
  PeerClusterChange, RoomAdmissionState, RoomRecoveryPlan, RoomCleanupCompleted,
  RoomRecoveryBootstrapCompleted
} = require('../out-js/decentraland/pulse/pulse_clusters.gen')

// The released fields 1-5 are the compatibility boundary, independently parsed by an old reader.
const OldChange = protobuf.parse(`syntax = "proto3";
message PeerClusterChange {
  string cluster_id = 1; string realm = 2; string session = 3;
  string displaced_session = 4; string displaced_cluster_id = 5;
}`).root.lookupType('PeerClusterChange')
const legacy = { clusterId: 'c', realm: 'm', session: 's', displacedSession: 'old', displacedClusterId: 'r' }
const plan = {
  epoch: 'epoch-1', revision: '18446744073709551615', admission: RoomAdmissionState.PENDING,
  cleanupOnly: false, operations: [{ operationId: 'op-1', clusterId: 'room-a', minimumRevokeBefore: 1770000000 }],
  tokenNotBefore: 1770000001, bootstrapRequired: true
}

test('legacy golden bytes are unchanged and lack admission authority', () => {
  const bytes = PeerClusterChange.encode(PeerClusterChange.fromPartial(legacy)).finish()
  assert.equal(Buffer.from(bytes).toString('hex'), '0a016312016d1a017322036f6c642a0172')
  assert.deepEqual(PeerClusterChange.decode(bytes), { ...legacy, roomRecovery: undefined })
})

test('absent/default plans and unknown admission do not become READY', () => {
  assert.equal(RoomRecoveryPlan.decode(new Uint8Array()).admission, RoomAdmissionState.UNSPECIFIED)
  assert.equal(RoomRecoveryPlan.fromJSON({ admission: 'future-state' }).admission, RoomAdmissionState.UNRECOGNIZED)
  const unknown = RoomRecoveryPlan.decode(Uint8Array.from([24, 99]))
  assert.equal(unknown.admission, 99)
  assert.notEqual(unknown.admission, RoomAdmissionState.READY)
})

test('full authoritative plan and uint64 decimal revision round trip', () => {
  const input = PeerClusterChange.fromPartial({ ...legacy, roomRecovery: plan })
  assert.deepEqual(PeerClusterChange.decode(PeerClusterChange.encode(input).finish()), input)
  assert.deepEqual(PeerClusterChange.fromJSON(PeerClusterChange.toJSON(input)), input)
})

test('old readers skip the plan while preserving released assignment fields', () => {
  const bytes = PeerClusterChange.encode(PeerClusterChange.fromPartial({ ...legacy, roomRecovery: plan })).finish()
  assert.deepEqual(OldChange.toObject(OldChange.decode(bytes)), legacy)
  const relayed = OldChange.encode(OldChange.decode(bytes)).finish()
  assert.equal(PeerClusterChange.decode(relayed).roomRecovery, undefined)
})

test('future top-level fields are skipped by the generated reader', () => {
  const bytes = PeerClusterChange.encode(PeerClusterChange.fromPartial(legacy)).uint32(802).string('future').finish()
  assert.deepEqual(PeerClusterChange.decode(bytes), { ...legacy, roomRecovery: undefined })
})

test('cleanup-only and bootstrap-required flags survive with ready admission', () => {
  const input = RoomRecoveryPlan.fromPartial({ ...plan, admission: RoomAdmissionState.READY, cleanupOnly: true })
  assert.deepEqual(RoomRecoveryPlan.decode(RoomRecoveryPlan.encode(input).finish()), input)
})

test('completion and bootstrap messages round trip exact identities', () => {
  const completion = { epoch: plan.epoch, revision: plan.revision, operationId: 'op-1', clusterId: 'room-a', revokeBefore: 1770000001, observedReady: false }
  assert.deepEqual(RoomCleanupCompleted.decode(RoomCleanupCompleted.encode(completion).finish()), completion)
  const bootstrap = { epoch: plan.epoch }
  assert.deepEqual(RoomRecoveryBootstrapCompleted.decode(RoomRecoveryBootstrapCompleted.encode(bootstrap).finish()), bootstrap)
})

test('retirement observation is additive and defaults false on ordinary or old completions', () => {
  const observation = { epoch: plan.epoch, revision: plan.revision, operationId: '', clusterId: '', revokeBefore: 0, observedReady: true }
  assert.deepEqual(RoomCleanupCompleted.decode(RoomCleanupCompleted.encode(observation).finish()), observation)
  const oldCompletion = protobuf.Writer.create().uint32(10).string(plan.epoch).uint32(18).string(plan.revision)
    .uint32(26).string('op-1').uint32(34).string('room-a').uint32(40).uint64(1770000001).finish()
  assert.equal(RoomCleanupCompleted.decode(oldCompletion).observedReady, false)
})

test('cutoff safe-integer boundary works and unsafe uint64 decode rejects', () => {
  const input = RoomRecoveryPlan.fromPartial({ tokenNotBefore: Number.MAX_SAFE_INTEGER })
  assert.equal(RoomRecoveryPlan.decode(RoomRecoveryPlan.encode(input).finish()).tokenNotBefore, Number.MAX_SAFE_INTEGER)
  // Field 6 uint64, exactly 2^53: valid protobuf but unsafe for generated JS number consumers.
  const bytes = protobuf.Writer.create().uint32(48).uint64('9007199254740992').finish()
  assert.throws(() => RoomRecoveryPlan.decode(bytes), /larger than Number.MAX_SAFE_INTEGER/)
})
