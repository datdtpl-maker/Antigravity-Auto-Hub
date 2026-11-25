const assert = require('assert');
const {
  convertQuotaSummary,
  convertAccountPlan,
  convertToModelDisplayName,
  getSelectedModelQuota,
  getFamilyRing
} = require('../src/core/quota');

function test(name, fn) {
  fn();
  console.log(`PASS: ${name}`);
}

test('Ultra shared Gemini Models group with Argon in description parses 5h and weekly properly', () => {
  const ultraResp = {
    groups: [
      {
        displayName: 'Gemini Models',
        description: 'Models within this group: Gemini 4 Neon, Gemini 4 Carbon, Gemini 4 Argon, Gemini 4 Hydrogen, Gemini 3.8 Flash',
        buckets: [
          { bucketId: 'gemini-weekly', window: 'weekly', remainingFraction: 0.97 },
          { bucketId: 'gemini-5h', window: '5h', remainingFraction: 0.96 }
        ]
      }
    ]
  };
  const q = convertQuotaSummary(ultraResp);
  assert.strictEqual(q.Gemini5H, 0.96);
  assert.strictEqual(q.GeminiWeekly, 0.97);
  assert.strictEqual(q.ArgonWeekly, -1.0);
});

test('Pro separate Gemini 4 Argon group tracks ArgonWeekly independently', () => {
  const proResp = {
    groups: [
      {
        displayName: 'Gemini Models',
        description: 'Models within this group: Gemini 3.8 Flash',
        buckets: [
          { bucketId: 'gemini-weekly', window: 'weekly', remainingFraction: 0.8 },
          { bucketId: 'gemini-5h', window: '5h', remainingFraction: 0.9 }
        ]
      },
      {
        displayName: 'Gemini 4 Argon',
        description: 'For paid Pro plans, Argon quota is separate.',
        buckets: [
          { bucketId: 'gemini-argon-weekly', window: 'weekly', remainingFraction: 0.25 }
        ]
      }
    ]
  };
  const q = convertQuotaSummary(proResp);
  assert.strictEqual(q.Gemini5H, 0.9);
  assert.strictEqual(q.GeminiWeekly, 0.8);
  assert.strictEqual(q.ArgonWeekly, 0.25);
});

test('convertAccountPlan recognizes Free, Pro, Ultra', () => {
  assert.strictEqual(convertAccountPlan({ paidTier: { id: 'g1-ultra-tier' }, currentTier: { id: 'free-tier' } }).Name, 'Ultra');
  assert.strictEqual(convertAccountPlan({ paidTier: { id: 'g1-pro-tier' } }).Name, 'Pro');
  assert.strictEqual(convertAccountPlan({ currentTier: { id: 'free-tier' } }).Name, 'Free');
});

test('convertToModelDisplayName maps raw transcript IDs accurately', () => {
  assert.strictEqual(convertToModelDisplayName('gemini-4-neon-medium'), 'Gemini 4 Neon (Medium)');
  assert.strictEqual(convertToModelDisplayName('gemini-4-neon-xhigh'), 'Gemini 4 Neon (XHigh)');
  assert.strictEqual(convertToModelDisplayName('gemini-3.8-flash-high'), 'Gemini 3.8 Flash (High)');
  assert.strictEqual(convertToModelDisplayName('claude-sonnet-4-6'), 'Claude Sonnet 4.6 (Thinking)');
});

test('getSelectedModelQuota and getFamilyRing compute minimum remaining', () => {
  const acc = {
    Success: true,
    Email: 'u@example.com',
    ModelsStatus: 'Available',
    QuotaGroups: [{ Name: 'Gemini Models', Window: '5h', Remaining: 0.5 }],
    ModelQuotas: [
      { Id: 'gemini-4-neon-medium', Name: 'Gemini 4 Neon (Medium)', Family: 'Neon', Status: 'Available', Remaining: 0.8 },
      { Id: 'gemini-4-neon-high', Name: 'Gemini 4 Neon (High)', Family: 'Neon', Status: 'Available', Remaining: 0.6 }
    ]
  };
  const sq = getSelectedModelQuota(acc, 'Gemini 4 Neon (Medium)');
  assert.strictEqual(sq.Known, true);
  assert.strictEqual(sq.Remaining, 0.5);

  const ring = getFamilyRing(acc, 'Neon');
  assert.strictEqual(ring.status, 'Available');
  assert.strictEqual(ring.remaining, 0.6);
});

console.log('ALL MACOS CORE TESTS PASSED');
