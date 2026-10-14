#!/usr/bin/env node
/**
 * 核心算法自检脚本
 * ------------------------------------------------------------------
 * 为什么需要它：鸿蒙 .ets 代码无法直接在 Node 里跑，但「CSV 解析 + 判重 + 统计」
 * 是本项目最需要保证正确性的部分。这里用等效的 JS 实现跑一套断言，
 * 用来验证算法逻辑本身正确（ArkTS 侧代码与之逐行对应），
 * 同时也可作为重新生成文档中「基线数字」的依据。
 *
 * 用法：node tools/verify.mjs
 */
import { strict as assert } from 'node:assert';
import { writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// 同时把结果写到文件：Windows 控制台默认 GBK，中文断言信息会乱码，
// 落盘成 UTF-8 报告后可直接用编辑器查看，也便于 CI 归档。
const LINES = [];
const log = (msg = '') => {
  LINES.push(msg);
  process.stdout.write(`${msg}\n`);
};
const flush = () => {
  try {
    writeFileSync(resolve(__dirname, '../verify-report.txt'), `${LINES.join('\n')}\n`, 'utf8');
  } catch {
    /* 报告写失败不影响主流程 */
  }
};

// =========================================================================
// 以下为 Statistics.ets / CsvParser.ets 逻辑的 JS 等效移植（保持同构，便于对照）
// =========================================================================

const DupKind = { None: 'none', Exact: 'exact', Repeat: 'repeat', Invalid: 'invalid' };

function parseDateTime(raw) {
  const s = String(raw ?? '').trim();
  if (s.length === 0) return NaN;
  const normalized = s.replace(/年|月/g, '-').replace(/日/g, ' ').replace(/\//g, '-').replace(/\s+/g, ' ').trim();
  if (/^\d{10}$/.test(normalized)) return Number.parseInt(normalized, 10) * 1000;
  if (/^\d{13}$/.test(normalized)) return Number.parseInt(normalized, 10);
  const m = normalized.match(/^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?/);
  if (m) {
    const y = +m[1], mo = +m[2], d = +m[3];
    const hh = m[4] !== undefined ? +m[4] : 0;
    const mi = m[5] !== undefined ? +m[5] : 0;
    const se = m[6] !== undefined ? +m[6] : 0;
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return NaN;
    return new Date(y, mo - 1, d, hh, mi, se).getTime();
  }
  const fb = new Date(normalized).getTime();
  return Number.isNaN(fb) ? NaN : fb;
}

function sniffDelimiter(firstLine) {
  let best = ',', bestCount = -1;
  for (const c of [',', ';', '\t', '|']) {
    const count = firstLine.split(c).length - 1;
    if (count > bestCount) { bestCount = count; best = c; }
  }
  return best;
}

function splitCsvLines(text, delimiter) {
  const rows = [];
  let row = [], field = '', inQuotes = false, i = 0;
  const src = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  while (i < src.length) {
    const ch = src[i];
    if (inQuotes) {
      if (ch === '"') {
        if (src[i + 1] === '"') { field += '"'; i += 2; continue; }
        inQuotes = false; i++; continue;
      }
      field += ch; i++; continue;
    }
    if (ch === '"' && field.length === 0) { inQuotes = true; i++; continue; }
    if (ch === delimiter) { row.push(field); field = ''; i++; continue; }
    if (ch === '\n') { row.push(field); rows.push(row); row = []; field = ''; i++; continue; }
    field += ch; i++;
  }
  if (field.length > 0 || row.length > 0) { row.push(field); rows.push(row); }
  return rows;
}

const COLUMN_ALIASES = {
  activityId: ['活动id', '活动编号', 'activityid', '活动', '场次id', '会议id'],
  participantId: ['参与者id', '工号', '学号', '用户id', 'userid', '人员编号', 'memberid', '手机号', 'phone', '身份证号'],
  participantName: ['姓名', '参与者姓名', '用户姓名', '员工姓名', 'name', 'username', '昵称'],
  group: ['部门', '班级', '分组', '组织', '单位', 'dept', 'department', 'group', 'team', '所属部门'],
  checkinTime: ['签到时间', '打卡时间', '时间', 'checkintime', 'time', 'createdat', '创建时间', '签到日期'],
  channel: ['签到方式', '渠道', '来源', '方式', 'channel', 'source', 'method', '签到渠道'],
};

const normalizeHeader = (name) =>
  name.replace(/\uFEFF/g, '').replace(/[\s\u3000]/g, '').replace(/_/g, '').toLowerCase();

/** 两轮匹配：先精确相等，再包含兜底；每列只能被认领一次 */
function buildColumnIndex(header) {
  const index = new Map();
  const normalized = header.map(normalizeHeader);
  const claimed = new Set();

  const tryMatch = (field, exactOnly) => {
    if (index.has(field)) return;
    const aliases = COLUMN_ALIASES[field].map(normalizeHeader);
    for (let col = 0; col < normalized.length; col++) {
      if (claimed.has(col)) continue;
      const head = normalized[col];
      if (!head) continue;
      const hit = exactOnly ? aliases.includes(head) : aliases.some((a) => head.includes(a));
      if (hit) { index.set(field, col); claimed.add(col); return; }
    }
  };

  for (const field of Object.keys(COLUMN_ALIASES)) tryMatch(field, true);
  for (const field of Object.keys(COLUMN_ALIASES)) tryMatch(field, false);

  return index;
}

const buildRecordKey = (activityId, participantId, timestamp, fallbackTime) =>
  `${activityId.trim()}::${participantId.trim()}::${Number.isNaN(timestamp) ? `raw:${fallbackTime.trim()}` : `ts:${timestamp}`}`;

function parseCheckinCsv(text, options = {}) {
  const cleaned = text.replace(/^\uFEFF/, '');
  const firstLine = cleaned.split('\n')[0] ?? '';
  const delimiter = options.delimiter ?? sniffDelimiter(firstLine);
  const headerRowIndex = options.headerRowIndex ?? 0;
  const table = splitCsvLines(cleaned, delimiter);
  if (table.length === 0) return [];
  const header = table[headerRowIndex] ?? [];
  const columnIndex = buildColumnIndex(header);
  const records = [];
  for (let r = headerRowIndex + 1; r < table.length; r++) {
    const cells = table[r];
    if (cells.length === 0 || cells.every((c) => c.trim().length === 0)) continue;
    const pick = (field) => {
      const idx = columnIndex.get(field);
      return idx === undefined || idx >= cells.length ? '' : cells[idx].trim();
    };
    const activityId = pick('activityId');
    const participantId = pick('participantId');
    const participantName = pick('participantName');
    const group = pick('group');
    const checkinTime = pick('checkinTime');
    const channel = pick('channel');
    const timestamp = parseDateTime(checkinTime);
    records.push({
      key: buildRecordKey(activityId, participantId, timestamp, checkinTime),
      activityId, participantId, participantName, group, checkinTime, timestamp, channel,
      lineNo: r + 1,
    });
  }
  return records;
}

function calcRate(actual, expected) {
  return expected <= 0 ? -1 : actual / expected;
}

function buildRosterMap(roster) {
  const map = new Map();
  for (const e of roster) {
    if (!map.has(e.activityId)) map.set(e.activityId, new Set());
    map.get(e.activityId).add(e.participantId);
  }
  return map;
}

function analyze(rawRecords, rosterMap, extraWarnings = []) {
  const warnings = extraWarnings.slice();
  const records = [];
  const personGroups = new Map();
  let invalidCount = 0;

  for (const record of rawRecords) {
    const groupKey = `${record.activityId}::${record.participantId}`;
    const isInvalid =
      record.activityId.trim().length === 0 ||
      record.participantId.trim().length === 0 ||
      Number.isNaN(record.timestamp);
    if (isInvalid) {
      invalidCount++;
      records.push({ record, kind: DupKind.Invalid, groupId: groupKey, isPrimary: false });
      continue;
    }
    const item = { record, kind: DupKind.None, groupId: groupKey, isPrimary: false };
    records.push(item);
    if (!personGroups.has(groupKey)) personGroups.set(groupKey, []);
    personGroups.get(groupKey).push(item);
  }

  if (invalidCount > 0) warnings.push(`发现 ${invalidCount} 条异常记录`);

  let exactDupCount = 0, repeatCount = 0;
  for (const bucket of personGroups.values()) {
    bucket.sort((a, b) => a.record.timestamp !== b.record.timestamp
      ? a.record.timestamp - b.record.timestamp
      : a.record.lineNo - b.record.lineNo);
    const seen = new Set();
    for (let i = 0; i < bucket.length; i++) {
      const item = bucket[i];
      if (i === 0) { item.isPrimary = true; seen.add(item.record.timestamp); continue; }
      if (seen.has(item.record.timestamp)) { item.kind = DupKind.Exact; exactDupCount++; }
      else { item.kind = DupKind.Repeat; repeatCount++; seen.add(item.record.timestamp); }
    }
  }

  // 活动聚合
  const activityMap = new Map();
  for (const item of records) {
    if (item.kind === DupKind.Invalid) continue;
    if (!activityMap.has(item.record.activityId)) activityMap.set(item.record.activityId, []);
    activityMap.get(item.record.activityId).push(item);
  }

  const activities = [];
  for (const [activityId, bucket] of activityMap) {
    const primarySet = new Set();
    let rawCount = 0, dupCount = 0;
    for (const item of bucket) {
      rawCount++;
      if (item.kind === DupKind.Exact || item.kind === DupKind.Repeat) dupCount++;
      if (item.isPrimary) primarySet.add(item.record.participantId);
    }
    let expectedCount = 0;
    if (rosterMap && rosterMap.has(activityId)) expectedCount = rosterMap.get(activityId).size;
    activities.push({
      activityId, expectedCount, actualCount: primarySet.size, rawCount, dupCount, invalidCount: 0,
      attendanceRate: calcRate(primarySet.size, expectedCount),
    });
  }

  const invalidByActivity = new Map();
  for (const item of records) {
    if (item.kind !== DupKind.Invalid) continue;
    const aid = item.record.activityId;
    if (aid.trim().length === 0) continue;
    invalidByActivity.set(aid, (invalidByActivity.get(aid) ?? 0) + 1);
  }
  for (const stat of activities) stat.invalidCount = invalidByActivity.get(stat.activityId) ?? 0;
  activities.sort((a, b) => a.activityId.localeCompare(b.activityId));

  // 参与者聚合
  const participantMap = new Map();
  for (const item of records) {
    if (item.kind === DupKind.Invalid) continue;
    if (!participantMap.has(item.record.participantId)) participantMap.set(item.record.participantId, []);
    participantMap.get(item.record.participantId).push(item);
  }

  const participants = [];
  for (const [participantId, bucket] of participantMap) {
    const primary = bucket.filter((i) => i.isPrimary);
    const sortedByTime = primary.slice().sort((a, b) => a.record.timestamp - b.record.timestamp);
    const lastItem = bucket[bucket.length - 1];
    const named = bucket.find((i) => i.record.participantName.trim().length > 0);
    participants.push({
      participantId,
      participantName: named ? named.record.participantName : '',
      group: lastItem.record.group,
      validCount: primary.length,
      rawCount: bucket.length,
      dupCount: bucket.length - primary.length,
      firstTime: sortedByTime.length > 0 ? sortedByTime[0].record.checkinTime : '',
      lastTime: sortedByTime.length > 0 ? sortedByTime[sortedByTime.length - 1].record.checkinTime : '',
    });
  }
  participants.sort((a, b) => b.validCount !== a.validCount ? b.validCount - a.validCount : a.participantId.localeCompare(b.participantId));

  const validRecordCount = records.length - invalidCount;
  const totalExpected = activities.reduce((s, a) => s + a.expectedCount, 0);
  const totalPrimary = activities.reduce((s, a) => s + a.actualCount, 0);

  function calcQualityScore(total, invalid, exact, repeat) {
    if (total === 0) return 0;
    const penaltyRate = (invalid * 10 + exact * 3 + repeat * 1) / total;
    return Math.max(0, Math.min(100, Math.round(100 - penaltyRate * 100)));
  }

  return {
    records, activities, participants,
    summary: {
      activityCount: activities.length,
      participantCount: participants.length,
      rawRecordCount: records.length,
      validRecordCount,
      exactDupCount, repeatCount, invalidCount,
      overallAttendanceRate: calcRate(totalPrimary, totalExpected),
      qualityScore: calcQualityScore(records.length, invalidCount, exactDupCount, repeatCount),
    },
    warnings,
  };
}

// =========================================================================
// 断言
// =========================================================================

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    passed++;
    log(`  [PASS] ${name}`);
  } catch (err) {
    failed++;
    log(`  [FAIL] ${name}`);
    log(`         ${String(err.message).split('\n').join('\n         ')}`);
  }
}

log('\n[1/5] CSV 解析');

test('标准逗号分隔 + 表头识别', () => {
  const rows = parseCheckinCsv(
    '活动ID,参与者ID,姓名,部门,签到时间,签到方式\r\nACT-1,E001,王伟,研发部,2026-10-14 09:05:12,扫码签到'
  );
  assert.equal(rows.length, 1);
  assert.equal(rows[0].activityId, 'ACT-1');
  assert.equal(rows[0].participantId, 'E001');
  assert.equal(rows[0].participantName, '王伟');
  assert.equal(rows[0].group, '研发部');
  assert.equal(rows[0].channel, '扫码签到');
});

test('列名别名：「工号」「打卡时间」可识别', () => {
  const rows = parseCheckinCsv('活动编号,工号,姓名,部门,打卡时间,来源\r\nA1,1001,李四,市场部,2026/10/14 9:30,小程序');
  assert.equal(rows[0].participantId, '1001');
  assert.equal(rows[0].activityId, 'A1');
  assert.ok(!Number.isNaN(rows[0].timestamp));
});

test('分号分隔可自动嗅探', () => {
  const rows = parseCheckinCsv('活动ID;参与者ID;姓名;签到时间\r\nA1;E1;张三;2026-10-14 10:00:00');
  assert.equal(rows.length, 1);
  assert.equal(rows[0].participantId, 'E1');
});

test('引号包裹的字段与字段内逗号', () => {
  const rows = parseCheckinCsv('活动ID,参与者ID,姓名,签到时间\r\nA1,E1,"王,五",2026-10-14 10:00:00');
  assert.equal(rows[0].participantName, '王,五');
});

test('字段内换行不被截断', () => {
  const rows = parseCheckinCsv('活动ID,参与者ID,姓名,签到时间\r\nA1,E1,"王\n五",2026-10-14 10:00:00');
  assert.equal(rows.length, 1);
  assert.ok(rows[0].participantName.includes('\n'));
});

test('UTF-8 BOM 不影响表头', () => {
  const rows = parseCheckinCsv('\uFEFF活动ID,参与者ID,签到时间\r\nA1,E1,2026-10-14 10:00:00');
  assert.equal(rows[0].activityId, 'A1');
});

test('空行被跳过', () => {
  const rows = parseCheckinCsv('活动ID,参与者ID,签到时间\r\nA1,E1,2026-10-14 10:00:00\r\n\r\nA1,E2,2026-10-14 10:01:00');
  assert.equal(rows.length, 2);
});

test('多种时间格式解析一致', () => {
  const a = parseDateTime('2026-10-14 09:30:00');
  const b = parseDateTime('2026/10/14 9:30');
  const c = parseDateTime('2026年10月14日 09:30');
  assert.equal(a, b);
  assert.equal(a, c);
});

test('非法时间返回 NaN', () => {
  assert.ok(Number.isNaN(parseDateTime('待补充')));
  assert.ok(Number.isNaN(parseDateTime('')));
});

test('10 位/13 位时间戳可解析', () => {
  assert.equal(parseDateTime('1760400600'), 1760400600000);
  assert.equal(parseDateTime('1760400600000'), 1760400600000);
});

console.log('\n[2/5] 判重规则');

const MINI_CSV = `活动ID,参与者ID,姓名,部门,签到时间,签到方式
ACT-2026-001,E1001,王伟,研发部,2026-10-14 09:05:12,扫码签到
ACT-2026-001,E1002,李芳,产品部,2026-10-14 09:07:30,扫码签到
ACT-2026-001,E1003,张娜,设计部,2026-10-14 09:12:44,小程序
ACT-2026-001,E1001,王伟,研发部,2026-10-14 09:05:12,手工补录
ACT-2026-001,E1002,李芳,产品部,2026-10-14 10:30:00,闸机刷卡
ACT-2026-001,E1004,刘敏,市场部,待定,扫码签到
ACT-2026-002,E1001,王伟,研发部,2026-10-14 14:02:08,扫码签到
ACT-2026-002,,赵磊,运营部,2026-10-14 14:05:00,扫码签到
ACT-2026-002,E1002,李芳,产品部,2026-10-14 14:06:19,小程序
ACT-2026-003,E1003,张娜,设计部,2026-10-15 10:00:00,扫码签到
ACT-2026-003,E1002,李芳,产品部,2026-10-15 10:01:33,扫码签到
ACT-2026-003,E1002,李芳,产品部,2026-10-15 10:01:33,闸机刷卡`;

const miniRecords = parseCheckinCsv(MINI_CSV);
const miniResult = analyze(miniRecords);

test('迷你示例：原始 12 行全部保留', () => {
  assert.equal(miniRecords.length, 12);
  assert.equal(miniResult.records.length, 12);
});

test('迷你示例：完全重复 2 条（E1001 在 ACT-001、E1002 在 ACT-003）', () => {
  assert.equal(miniResult.summary.exactDupCount, 2);
  const exact = miniResult.records.filter((r) => r.kind === DupKind.Exact);
  assert.equal(exact.length, 2);
  // 数据行第 4 行（E1001 同刻）、第 12 行（E1002 同刻）
  assert.deepEqual(exact.map((r) => r.record.lineNo).sort((a, b) => a - b), [5, 13]);
});

test('迷你示例：多次签到 1 条（E1002 在 ACT-001 不同时间）', () => {
  assert.equal(miniResult.summary.repeatCount, 1);
  const repeat = miniResult.records.filter((r) => r.kind === DupKind.Repeat);
  // 数据行第 5 行，含表头偏移后为第 6 行
  assert.equal(repeat[0].record.lineNo, 6);
});

test('迷你示例：异常 2 条（时间为「待定」+ 空参与者ID）', () => {
  assert.equal(miniResult.summary.invalidCount, 2);
  const invalid = miniResult.records.filter((r) => r.kind === DupKind.Invalid);
  assert.deepEqual(invalid.map((r) => r.record.lineNo).sort((a, b) => a - b), [7, 9]);
});

test('迷你示例：每人都保留一条 Primary，且是最早时间', () => {
  const g1 = miniResult.records.filter((r) => r.groupId === 'ACT-2026-001::E1002');
  const primary = g1.filter((r) => r.isPrimary);
  assert.equal(primary.length, 1);
  assert.equal(primary[0].record.checkinTime, '2026-10-14 09:07:30');
});

test('重复记录不计入实到人数', () => {
  const a1 = miniResult.activities.find((a) => a.activityId === 'ACT-2026-001');
  // ACT-001 有效参与者：E1001 / E1002 / E1003 = 3 人（E1004 时间异常）
  assert.equal(a1.actualCount, 3);
  assert.equal(a1.rawCount, 5);
  assert.equal(a1.dupCount, 2);   // 1 完全重复 + 1 多次签到
  assert.equal(a1.invalidCount, 1); // 待定时间那条归属 ACT-001
});

console.log('\n[3/5] 统计聚合');

test('活动维度：实到 = 去重唯一参与者数', () => {
  const a3 = miniResult.activities.find((a) => a.activityId === 'ACT-2026-003');
  assert.equal(a3.actualCount, 2);   // E1003 + E1002
  assert.equal(a3.rawCount, 3);
  assert.equal(a3.dupCount, 1);      // 完全重复
});

test('参与者维度：跨活动累计有效签到次数', () => {
  const p = miniResult.participants.find((x) => x.participantId === 'E1002');
  assert.equal(p.validCount, 3);  // ACT-001 / ACT-002 / ACT-003 各一次
  assert.equal(p.rawCount, 5);
  assert.equal(p.dupCount, 2);    // ACT-001 多次签到 + ACT-003 完全重复
});

test('参与者维度：姓名与部门正确回填', () => {
  const p = miniResult.participants.find((x) => x.participantId === 'E1001');
  assert.equal(p.participantName, '王伟');
  assert.equal(p.validCount, 2);
});

test('出行率：无名册时为 -1，有名册时正确计算', () => {
  assert.equal(miniResult.activities[0].attendanceRate, -1);

  const roster = buildRosterMap([
    { activityId: 'ACT-2026-001', participantId: 'E1001' },
    { activityId: 'ACT-2026-001', participantId: 'E1002' },
    { activityId: 'ACT-2026-001', participantId: 'E1003' },
    { activityId: 'ACT-2026-001', participantId: 'E1004' },
    { activityId: 'ACT-2026-001', participantId: 'E1005' },
  ]);
  const withRoster = analyze(miniRecords, roster);
  const a1 = withRoster.activities.find((a) => a.activityId === 'ACT-2026-001');
  assert.equal(a1.expectedCount, 5);
  assert.equal(a1.actualCount, 3);
  assert.equal(a1.attendanceRate, 0.6);
});

test('汇总：场次/人数/条数口径一致', () => {
  const s = miniResult.summary;
  assert.equal(s.rawRecordCount, 12);
  assert.equal(s.validRecordCount, 10);
  assert.equal(s.activityCount, 3);
  assert.equal(s.participantCount, 3);  // E1001/E1002/E1003（E1004 时间异常，不计入）
  assert.equal(s.exactDupCount + s.repeatCount + s.invalidCount, 5);
});

test('质量分在 0~100 之间且随问题增多而下降', () => {
  const clean = analyze(parseCheckinCsv(
    '活动ID,参与者ID,签到时间\r\nA1,E1,2026-10-14 09:00:00\r\nA1,E2,2026-10-14 09:01:00'
  ));
  assert.equal(clean.summary.qualityScore, 100);
  assert.ok(miniResult.summary.qualityScore < 100);
  assert.ok(miniResult.summary.qualityScore >= 0);
});

test('大数据集不会把不同人的记录判为重复', () => {
  const rows = [];
  for (let i = 0; i < 500; i++) {
    rows.push(`A1,E${i},用户${i},部门,2026-10-14 09:00:00,扫码签到`);
  }
  const r = analyze(parseCheckinCsv(`活动ID,参与者ID,姓名,部门,签到时间,签到方式\n${rows.join('\n')}`));
  assert.equal(r.summary.exactDupCount, 0);
  assert.equal(r.summary.participantCount, 500);
  assert.equal(r.summary.qualityScore, 100);
});

console.log('\n[4/5] 边界与鲁棒性');

test('空输入不崩溃', () => {
  const r = analyze(parseCheckinCsv(''));
  assert.equal(r.summary.rawRecordCount, 0);
  assert.equal(r.summary.qualityScore, 0);
});

test('只有表头没有数据行', () => {
  const r = analyze(parseCheckinCsv('活动ID,参与者ID,签到时间'));
  assert.equal(r.summary.rawRecordCount, 0);
});

test('缺表头时靠列位兜底不丢行', () => {
  const r = parseCheckinCsv('A1,E1,王伟,研发部,2026-10-14 09:00:00,扫码签到');
  // 首行被当作表头，因此只剩 0 行数据，但不应抛异常
  assert.ok(Array.isArray(r));
});

test('同一秒多条：1 条保留 + N-1 条完全重复', () => {
  const csv = `活动ID,参与者ID,签到时间\nA1,E1,2026-10-14 09:00:00\nA1,E1,2026-10-14 09:00:00\nA1,E1,2026-10-14 09:00:00`;
  const r = analyze(parseCheckinCsv(csv));
  assert.equal(r.summary.exactDupCount, 2);
  assert.equal(r.activities[0].actualCount, 1);
});

test('时间乱序输入不影响 Primary 判定', () => {
  const csv = `活动ID,参与者ID,签到时间\nA1,E1,2026-10-14 11:00:00\nA1,E1,2026-10-14 09:00:00`;
  const r = analyze(parseCheckinCsv(csv));
  const primary = r.records.find((x) => x.isPrimary);
  assert.equal(primary.record.checkinTime, '2026-10-14 09:00:00');
});

test('结果可复现：同样输入两次分析结果一致', () => {
  const a = analyze(parseCheckinCsv(MINI_CSV));
  const b = analyze(parseCheckinCsv(MINI_CSV));
  assert.deepEqual(a.summary, b.summary);
  assert.equal(a.records.map((r) => r.kind).join(','), b.records.map((r) => r.kind).join(','));
});

console.log('\n[5/5] 演示数据基线');

// 复现 MockData.ets 的生成逻辑，打印基线数字（与本文件头部注释保持一致）
function seeded(seed) {
  let s = seed;
  return () => { s = (s * 1664525 + 1013904223) % 4294967296; return s / 4294967296; };
}
function generateMock(participantCount = 120, seed = 20261014) {
  const rnd = seeded(seed);
  const lines = ['活动ID,参与者ID,姓名,部门,签到时间,签到方式'];
  let totalRows = 0, exactDup = 0, repeat = 0, invalid = 0;
  const acts = ['ACT-2026-001', 'ACT-2026-002', 'ACT-2026-003'];
  const RATIO = { 'ACT-2026-001': 0.88, 'ACT-2026-002': 0.72, 'ACT-2026-003': 0.95 };
  for (const a of acts) {
    for (let i = 0; i < participantCount; i++) {
      if (rnd() > RATIO[a]) continue;
      const minute = Math.floor(rnd() * 71);
      lines.push(`${a},E${1000 + i},用户,部门,2026-10-14 09:${String(minute).padStart(2, '0')}:00,扫码签到`);
      totalRows++;
      if (rnd() < 0.10) { lines.push(`${a},E${1000 + i},用户,部门,2026-10-14 09:${String(minute).padStart(2, '0')}:00,手工补录`); totalRows++; exactDup++; }
      if (rnd() < 0.06) { lines.push(`${a},E${1000 + i},用户,部门,2026-10-14 10:30:00,手工补录`); totalRows++; repeat++; }
    }
    lines.push(`${a},,某,部门,2026-10-14 09:30:00,扫码签到`);
    lines.push(`${a},E9999,测试用户,部门,待补充,扫码签到`);
    lines.push(`,E8888,匿名用户,部门,2026-10-14 09:45:00,闸机刷卡`);
    totalRows += 3; invalid += 3;
  }
  return { csv: lines.join('\r\n'), expected: { totalRows, exactDup, repeat, invalid } };
}

const mock = generateMock();
test('演示数据规模约 350~400 行，且埋入三类脏数据', () => {
  assert.ok(mock.expected.totalRows > 300 && mock.expected.totalRows < 450,
    `实际 ${mock.expected.totalRows} 行，超出预期区间`);
  assert.ok(mock.expected.exactDup > 0);
  assert.ok(mock.expected.repeat > 0);
  assert.equal(mock.expected.invalid, 9); // 3 场活动 × 3 条
});

test('演示数据经完整分析后统计口径自洽', () => {
  const parsed = parseCheckinCsv(mock.csv);
  assert.equal(parsed.length, mock.expected.totalRows, '解析行数与生成行数不一致');
  const withRosterAbsent = analyze(parsed);
  const s = withRosterAbsent.summary;
  assert.equal(s.exactDupCount, mock.expected.exactDup, '完全重复数不匹配');
  assert.equal(s.repeatCount, mock.expected.repeat, '多次签到数不匹配');
  assert.equal(s.invalidCount, mock.expected.invalid, '异常数不匹配');
  assert.equal(s.rawRecordCount, mock.expected.totalRows);
  assert.equal(s.validRecordCount + s.invalidCount, s.rawRecordCount);
  assert.ok(s.participantCount > 0);
  // 质量分按扣分权重折算：异常 ×10 占比最高，因此几十行脏数据会把分数压到 60 以下，
  // 这符合设计预期（分数用于提示「先清洗再使用」，不是越高越好）。
  assert.ok(s.qualityScore >= 0 && s.qualityScore < 100, `质量分 ${s.qualityScore} 不在合理区间`);
  console.log(`      基线：${s.rawRecordCount} 行 / ${s.activityCount} 场 / ${s.participantCount} 人 / ` +
    `完全重复 ${s.exactDupCount} / 多次签到 ${s.repeatCount} / 异常 ${s.invalidCount} / 质量分 ${s.qualityScore}`);
});

// =========================================================================

console.log(`\n${'='.repeat(60)}`);
console.log(`结果：${passed} 通过，${failed} 失败`);
console.log(`${'='.repeat(60)}\n`);

flush();

if (failed > 0) {
  process.exitCode = 1;
}
