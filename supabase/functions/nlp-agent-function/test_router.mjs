import assert from 'node:assert'

// Re-implement the pure logic functions from index.ts to verify algorithm correctness under Node
const COMPLEXITY_THRESHOLD = 40
const QUALITY_SCORE_THRESHOLD = 0.75

function evaluateComplexity(text, chatHistory, eventCount = 0) {
  let score = 0
  const reasons = []

  const koKeywords = /(조율|겹치|비는|언제|변경|옮겨|바꿔|취소|삭제|미뤄|당겨|시간표|스케줄|가능한|확인해)/i
  const enKeywords = /(reschedule|conflict|find time|overlap|cancel|change|postpone|free time|available)/i
  if (koKeywords.test(text) || enKeywords.test(text)) {
    score += 40
    reasons.push('scheduling_negotiation_keyword')
  }

  const personMatches = text.match(/\[PERSON_\d+\]/g)
  if (personMatches && personMatches.length >= 2) {
    score += 30
    reasons.push(`multi_person_tokens(${personMatches.length})`)
  }

  if (eventCount >= 5) {
    score += 30
    reasons.push(`dense_calendar_context(${eventCount}_events)`)
  } else if (eventCount >= 2) {
    score += 15
    reasons.push(`moderate_calendar_context(${eventCount}_events)`)
  }

  if (Array.isArray(chatHistory) && chatHistory.length >= 2) {
    score += 25
    reasons.push(`multi_turn_history(${chatHistory.length}_turns)`)
  }

  if (text.length > 60) {
    score += 15
    reasons.push('long_prompt')
  }

  return {
    isComplex: score >= COMPLEXITY_THRESHOLD,
    score,
    reasons,
  }
}

function scoreResponseQuality(response) {
  if (!response || typeof response !== 'object') {
    return { score: 0, passed: false, reason: 'invalid_json_object' }
  }

  let score = 0
  const reasons = []

  const hasCoreFields =
    typeof response.intent === 'string' &&
    typeof response.aiReplyMessage === 'string' &&
    Array.isArray(response.conflicts)

  if (hasCoreFields) {
    score += 0.35
  } else {
    reasons.push('missing_core_fields')
  }

  const validIntents = ['CREATE_EVENT', 'RESCHEDULE', 'CANCEL', 'QUERY']
  if (validIntents.includes(response.intent)) {
    score += 0.25
  } else {
    reasons.push(`invalid_intent(${response.intent})`)
  }

  if (response.intent === 'CREATE_EVENT' || response.intent === 'RESCHEDULE') {
    let scheduleValid = true
    
    if (!response.eventTitleTokenized || response.eventTitleTokenized.trim() === '') {
      scheduleValid = false
      reasons.push('missing_title')
    }

    const start = response.startTime ? new Date(response.startTime).getTime() : NaN
    const end = response.endTime ? new Date(response.endTime).getTime() : NaN

    if (isNaN(start) || isNaN(end) || end <= start) {
      scheduleValid = false
      reasons.push('invalid_time_range')
    }

    if (scheduleValid) {
      score += 0.40
    }
  } else if (response.intent === 'CANCEL') {
    if (response.aiReplyMessage && response.aiReplyMessage.trim().length >= 2) {
      score += 0.40
    } else {
      reasons.push('empty_cancel_reply')
    }
  } else if (response.intent === 'QUERY') {
    if (response.aiReplyMessage && response.aiReplyMessage.trim().length >= 2) {
      score += 0.40
    } else {
      reasons.push('empty_query_reply')
    }
  }

  return {
    score,
    passed: score >= QUALITY_SCORE_THRESHOLD,
    reason: reasons.length > 0 ? reasons.join(', ') : 'all_checks_passed',
  }
}

console.log('--- Testing Complexity Evaluation ---')

// Test 1: Simple utterance (Low complexity -> Flash-Lite)
const simpleResult = evaluateComplexity('내일 2시 미팅', [], 0)
console.log('Simple Result:', simpleResult)
assert.strictEqual(simpleResult.isComplex, false, 'Simple prompt should not be complex')

// Test 2: Korean scheduling negotiation keyword (High complexity -> Flash Bypass)
const keywordResult = evaluateComplexity('민지랑 시간 겹치는지 확인해줘', [], 0)
console.log('Keyword Result:', keywordResult)
assert.strictEqual(keywordResult.isComplex, true, 'Negotiation prompt should trigger bypass')

// Test 3: Multi-person tokens
const multiPersonResult = evaluateComplexity('[PERSON_1]와 [PERSON_2]와 저녁', [], 0)
console.log('Multi-person Result:', multiPersonResult)
assert.strictEqual(multiPersonResult.score >= 30, true)

// Test 4: Dense calendar context (RAG 5+ events)
const denseCalResult = evaluateComplexity('내일 점심 먹자', [], 6)
console.log('Dense Cal Result:', denseCalResult)
assert.strictEqual(denseCalResult.score >= 30, true)

console.log('\n--- Testing Response Quality Scoring ---')

// Test 5: Perfect CREATE_EVENT response
const validCreate = {
  intent: 'CREATE_EVENT',
  eventTitleTokenized: '팀 회의',
  startTime: '2026-09-10T14:00:00Z',
  endTime: '2026-09-10T15:00:00Z',
  participantsTokenized: ['[PERSON_1]'],
  aiReplyMessage: '내일 오후 2시에 일정을 잡았습니다.',
  conflicts: []
}
const quality1 = scoreResponseQuality(validCreate)
console.log('Valid CREATE Quality:', quality1)
assert.strictEqual(quality1.passed, true)
assert.strictEqual(quality1.score, 1.0)

// Test 6: Malformed response (End time before start time)
const invalidTime = {
  intent: 'CREATE_EVENT',
  eventTitleTokenized: '잘못된 시간',
  startTime: '2026-09-10T15:00:00Z',
  endTime: '2026-09-10T14:00:00Z', // invalid!
  participantsTokenized: [],
  aiReplyMessage: '일정 생성',
  conflicts: []
}
const quality2 = scoreResponseQuality(invalidTime)
console.log('Invalid Time Quality:', quality2)
assert.strictEqual(quality2.passed, false, 'EndTime < StartTime must fail quality score')

// Test 7: Missing core fields
const missingFields = {
  intent: 'CREATE_EVENT',
  eventTitleTokenized: '누락'
}
const quality3 = scoreResponseQuality(missingFields)
console.log('Missing Fields Quality:', quality3)
assert.strictEqual(quality3.passed, false)

// Test 8: Valid QUERY response
const validQuery = {
  intent: 'QUERY',
  participantsTokenized: [],
  aiReplyMessage: '해당 시간에 다른 일정이 있습니다. 변경하시겠습니까?',
  conflicts: [{ existingEventTitle: '기존 미팅' }]
}
const quality4 = scoreResponseQuality(validQuery)
console.log('Valid QUERY Quality:', quality4)
assert.strictEqual(quality4.passed, true)
assert.strictEqual(quality4.score, 1.0)

// Test 9: Valid RESCHEDULE response
const validReschedule = {
  intent: 'RESCHEDULE',
  targetEventId: 'evt_12345',
  eventTitleTokenized: '팀 미팅',
  startTime: '2026-09-10T16:00:00Z',
  endTime: '2026-09-10T17:00:00Z',
  participantsTokenized: [],
  aiReplyMessage: '팀 미팅을 오후 4시로 변경합니다.',
  conflicts: []
}
const quality5 = scoreResponseQuality(validReschedule)
console.log('Valid RESCHEDULE Quality:', quality5)
assert.strictEqual(quality5.passed, true)
assert.strictEqual(quality5.score, 1.0)

// Test 10: Valid CANCEL response
const validCancel = {
  intent: 'CANCEL',
  targetEventId: 'evt_12345',
  participantsTokenized: [],
  aiReplyMessage: '내일 팀 미팅 일정을 취소할까요?',
  conflicts: []
}
const quality6 = scoreResponseQuality(validCancel)
console.log('Valid CANCEL Quality:', quality6)
assert.strictEqual(quality6.passed, true)
assert.strictEqual(quality6.score, 1.0)

console.log('\n✅ ALL 10 ALGORITHM TEST CASES PASSED!')
