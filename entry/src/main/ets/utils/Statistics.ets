import {
  ActivityStat,
  AnalyzedRecord,
  AnalysisResult,
  CheckinRecord,
  DupKind,
  ParticipantStat,
  RosterEntry,
  RosterMap,
  SummaryStat,
} from '../model/Types';
import { Logger } from './Logger';

/**
 * 统计分析引擎
 * ------------------------------------------------------------------
 * 纯函数设计：输入原始记录 + 可选名册，输出不可变的 AnalysisResult。
 * 不依赖任何 UI / 系统能力，因此可以在单元测试里直接跑（见 tools/verify.mjs 的对照实现）。
 *
 * 判重规则（三档）：
 *   Invalid —— 活动 ID 或参与者 ID 为空、或签到时间无法解析
 *   Exact   —— 同一人 + 同一活动 + 同一时间戳（重复提交 / 重复导入）
 *   Repeat  —— 同一人 + 同一活动，但时间不同（多次签到，需人工确认）
 * 每个「人 + 活动」组合保留时间最早的一条为 isPrimary，用于计算实到人数。
 */

/** 计算出席率，无名册时返回 -1 表示不可计算 */
function calcRate(actual: number, expected: number): number {
  if (expected <= 0) {
    return -1;
  }
  return actual / expected;
}

/** 名册列表转查询表 */
export function buildRosterMap(roster: RosterEntry[]): RosterMap {
  const map: RosterMap = new Map<string, Set<string>>();
  for (const entry of roster) {
    let set: Set<string> | undefined = map.get(entry.activityId);
    if (set === undefined) {
      set = new Set<string>();
      map.set(entry.activityId, set);
    }
    set.add(entry.participantId);
  }
  return map;
}

/**
 * 主分析入口。
 *
 * @param rawRecords CSV 解析出的原始记录（含重复）
 * @param rosterMap  可选名册，用于计算出席率；未提供时出席率为 -1
 * @param extraWarnings 解析阶段的告警，会透传到结果里
 */
export function analyze(
  rawRecords: CheckinRecord[],
  rosterMap?: RosterMap,
  extraWarnings?: string[]
): AnalysisResult {
  const warnings: string[] = extraWarnings !== undefined ? extraWarnings.slice() : [];
  const records: AnalyzedRecord[] = [];

  // ---- 第一趟：按「人 + 活动」分组，同时标记 Invalid ----
  const personGroups: Map<string, AnalyzedRecord[]> = new Map<string, AnalyzedRecord[]>();
  const invalidKeys: Set<string> = new Set<string>();
  let invalidCount: number = 0;

  for (const record of rawRecords) {
    const groupKey: string = `${record.activityId}::${record.participantId}`;

    const isInvalid: boolean =
      record.activityId.trim().length === 0 ||
      record.participantId.trim().length === 0 ||
      Number.isNaN(record.timestamp);

    if (isInvalid) {
      invalidCount++;
      invalidKeys.add(record.key);
      records.push({
        record,
        kind: DupKind.Invalid,
        groupId: groupKey,
        isPrimary: false,
      });
      continue;
    }

    const item: AnalyzedRecord = {
      record,
      kind: DupKind.None,
      groupId: groupKey,
      isPrimary: false,
    };
    records.push(item);

    let bucket: AnalyzedRecord[] | undefined = personGroups.get(groupKey);
    if (bucket === undefined) {
      bucket = [];
      personGroups.set(groupKey, bucket);
    }
    bucket.push(item);
  }

  if (invalidCount > 0) {
    warnings.push(`发现 ${invalidCount} 条异常记录（关键字段缺失或签到时间无法解析），已单独列出`);
  }

  // ---- 第二趟：组内按时间排序，标记 Exact / Repeat 与 Primary ----
  let exactDupCount: number = 0;
  let repeatCount: number = 0;

  personGroups.forEach((bucket: AnalyzedRecord[]) => {
    // 时间升序；时间相同按原始行号，保证结果稳定可复现
    bucket.sort((a: AnalyzedRecord, b: AnalyzedRecord) => {
      if (a.record.timestamp !== b.record.timestamp) {
        return a.record.timestamp - b.record.timestamp;
      }
      return a.record.lineNo - b.record.lineNo;
    });

    const seenTimestamps: Set<number> = new Set<number>();
    for (let i: number = 0; i < bucket.length; i++) {
      const item: AnalyzedRecord = bucket[i];
      if (i === 0) {
        item.isPrimary = true;
        seenTimestamps.add(item.record.timestamp);
        continue;
      }
      if (seenTimestamps.has(item.record.timestamp)) {
        // 完全重复：同人同活动同时间
        item.kind = DupKind.Exact;
        exactDupCount++;
      } else {
        // 同人同活动不同时间：多次签到
        item.kind = DupKind.Repeat;
        repeatCount++;
        seenTimestamps.add(item.record.timestamp);
      }
    }
  });

  if (exactDupCount > 0) {
    warnings.push(`发现 ${exactDupCount} 条完全重复记录（同一人同一活动同一时间），建议清理后使用`);
  }
  if (repeatCount > 0) {
    warnings.push(`发现 ${repeatCount} 条多次签到记录（同一人多次签到），请人工确认是否为有效出席`);
  }

  // ---- 第三趟：按活动聚合 ----
  const activityMap: Map<string, AnalyzedRecord[]> = new Map<string, AnalyzedRecord[]>();
  for (const item of records) {
    if (item.kind === DupKind.Invalid) {
      continue;
    }
    let bucket: AnalyzedRecord[] | undefined = activityMap.get(item.record.activityId);
    if (bucket === undefined) {
      bucket = [];
      activityMap.set(item.record.activityId, bucket);
    }
    bucket.push(item);
  }

  const activities: ActivityStat[] = [];
  activityMap.forEach((bucket: AnalyzedRecord[], activityId: string) => {
    // 实到人数：只数 Primary（每人一次），这是去重后的真实出席人数
    const primarySet: Set<string> = new Set<string>();
    let rawCount: number = 0;
    let dupCount: number = 0;

    for (const item of bucket) {
      rawCount++;
      if (item.kind === DupKind.Exact || item.kind === DupKind.Repeat) {
        dupCount++;
      }
      if (item.isPrimary) {
        primarySet.add(item.record.participantId);
      }
    }

    let expectedCount: number = 0;
    if (rosterMap !== undefined) {
      const roster: Set<string> | undefined = rosterMap.get(activityId);
      expectedCount = roster !== undefined ? roster.size : 0;
    }

    activities.push({
      activityId,
      expectedCount,
      actualCount: primarySet.size,
      rawCount,
      dupCount,
      invalidCount: 0,
      attendanceRate: calcRate(primarySet.size, expectedCount),
    });
  });

  // 把异常记录按活动归属到对应活动（异常记录也可能带活动 ID）
  const invalidByActivity: Map<string, number> = new Map<string, number>();
  for (const item of records) {
    if (item.kind !== DupKind.Invalid) {
      continue;
    }
    const aid: string = item.record.activityId;
    if (aid.trim().length === 0) {
      continue;
    }
    invalidByActivity.set(aid, (invalidByActivity.get(aid) ?? 0) + 1);
  }
  for (const stat of activities) {
    stat.invalidCount = invalidByActivity.get(stat.activityId) ?? 0;
  }

  // 活动按 ID 排序，保证 UI 顺序稳定
  activities.sort((a: ActivityStat, b: ActivityStat) => a.activityId.localeCompare(b.activityId));

  // ---- 第四趟：按参与者聚合（跨活动） ----
  const participantMap: Map<string, AnalyzedRecord[]> = new Map<string, AnalyzedRecord[]>();
  for (const item of records) {
    if (item.kind === DupKind.Invalid) {
      continue;
    }
    let bucket: AnalyzedRecord[] | undefined = participantMap.get(item.record.participantId);
    if (bucket === undefined) {
      bucket = [];
      participantMap.set(item.record.participantId, bucket);
    }
    bucket.push(item);
  }

  const participants: ParticipantStat[] = [];
  participantMap.forEach((bucket: AnalyzedRecord[], participantId: string) => {
    const primary: AnalyzedRecord[] = bucket.filter((i: AnalyzedRecord) => i.isPrimary);
    const sortedByTime: AnalyzedRecord[] = primary
      .slice()
      .sort((a: AnalyzedRecord, b: AnalyzedRecord) => a.record.timestamp - b.record.timestamp);

    // 取最近一次出现的姓名/部门，避免早期脏数据覆盖正确信息
    const lastItem: AnalyzedRecord = bucket[bucket.length - 1];
    const name: string = bucket.find((i: AnalyzedRecord) => i.record.participantName.trim().length > 0)
      ?.record.participantName ?? '';
    const group: string = lastItem.record.group;

    participants.push({
      participantId,
      participantName: name,
      group,
      validCount: primary.length,
      rawCount: bucket.length,
      dupCount: bucket.length - primary.length,
      firstTime: sortedByTime.length > 0 ? sortedByTime[0].record.checkinTime : '',
      lastTime: sortedByTime.length > 0 ? sortedByTime[sortedByTime.length - 1].record.checkinTime : '',
    });
  });

  participants.sort((a: ParticipantStat, b: ParticipantStat) => {
    if (b.validCount !== a.validCount) {
      return b.validCount - a.validCount;
    }
    return a.participantId.localeCompare(b.participantId);
  });

  // ---- 汇总 ----
  const validRecordCount: number = records.length - invalidCount;
  const totalExpected: number = activities.reduce((sum: number, a: ActivityStat) => sum + a.expectedCount, 0);
  const totalPrimary: number = activities.reduce((sum: number, a: ActivityStat) => sum + a.actualCount, 0);

  const summary: SummaryStat = {
    activityCount: activities.length,
    participantCount: participants.length,
    rawRecordCount: records.length,
    validRecordCount,
    exactDupCount,
    repeatCount,
    invalidCount,
    overallAttendanceRate: calcRate(totalPrimary, totalExpected),
    qualityScore: calcQualityScore(records.length, invalidCount, exactDupCount, repeatCount),
  };

  Logger.info(
    `分析完成：${summary.activityCount} 场活动 / ${summary.participantCount} 人 / ` +
    `有效 ${validRecordCount} 条 / 完全重复 ${exactDupCount} 条 / 多次签到 ${repeatCount} 条 / 异常 ${invalidCount} 条`
  );

  return {
    records,
    activities,
    participants,
    summary,
    warnings,
    generatedAt: new Date().toISOString(),
  };
}

/**
 * 数据质量分 0~100。
 * 扣分权重：异常记录 -10/条，完全重复 -3/条，多次签到 -1/条。
 * 用「每 N 条记录扣 1 分」的方式换算，避免数据量大时分数直接归零。
 */
function calcQualityScore(total: number, invalid: number, exact: number, repeat: number): number {
  if (total === 0) {
    return 0;
  }
  const penaltyRate: number = (invalid * 10 + exact * 3 + repeat * 1) / total;
  const score: number = 100 - penaltyRate * 100;
  return Math.max(0, Math.min(100, Math.round(score)));
}

/** 导出「参与者参与明细」为 CSV 行 */
export function buildParticipantCsvRows(participants: ParticipantStat[]): string[][] {
  return participants.map((p: ParticipantStat) => [
    p.participantId,
    p.participantName,
    p.group,
    `${p.validCount}`,
    `${p.rawCount}`,
    `${p.dupCount}`,
    p.firstTime,
    p.lastTime,
  ]);
}

export const PARTICIPANT_CSV_HEADER: string[] = [
  '参与者ID', '姓名', '部门/分组', '有效签到次数', '原始签到次数', '重复条数', '首次签到时间', '末次签到时间',
];

/** 导出「活动汇总」为 CSV 行 */
export function buildActivityCsvRows(activities: ActivityStat[]): string[][] {
  return activities.map((a: ActivityStat) => [
    a.activityId,
    `${a.expectedCount}`,
    `${a.actualCount}`,
    `${a.rawCount}`,
    `${a.dupCount}`,
    `${a.invalidCount}`,
    a.attendanceRate < 0 ? '未提供名册' : `${(a.attendanceRate * 100).toFixed(1)}%`,
  ]);
}

export const ACTIVITY_CSV_HEADER: string[] = [
  '活动ID', '应到人数', '实到人数', '签到总条数', '重复条数', '异常条数', '出席率',
];

/** 导出「重复记录清单」为 CSV 行，满足「检查重复记录并导出」的核心诉求 */
export function buildDuplicateCsvRows(records: AnalyzedRecord[]): string[][] {
  return records
    .filter((i: AnalyzedRecord) => i.kind === DupKind.Exact || i.kind === DupKind.Repeat)
    .map((i: AnalyzedRecord) => [
      i.kind === DupKind.Exact ? '完全重复' : '多次签到',
      i.record.activityId,
      i.record.participantId,
      i.record.participantName,
      i.record.group,
      i.record.checkinTime,
      i.record.channel,
      `${i.record.lineNo}`,
      i.isPrimary ? '保留' : '可清理',
    ]);
}

export const DUPLICATE_CSV_HEADER: string[] = [
  '重复类型', '活动ID', '参与者ID', '姓名', '部门/分组', '签到时间', '签到方式', '原始行号', '处置建议',
];
