import { CheckinRecord, RosterEntry } from '../model/Types';
import { buildRecordKey, parseCheckinCsv } from './CsvParser';

/**
 * 演示数据生成器
 * ------------------------------------------------------------------
 * 目的：让 demo 一打开就有可信的假数据可玩，且刻意埋入三类脏数据
 * （完全重复 / 多次签到 / 字段缺失），用于演示「重复检查」能力。
 * 使用固定种子的伪随机数，保证每次运行结果一致，便于截图和写文档。
 */

/** ArkTS 严格模式要求所有对象字面量都有明确的接口类型，不能用匿名类型 */
interface Person {
  id: string;
  name: string;
  dept: string;
}

interface MockExpected {
  totalRows: number;
  exactDup: number;
  repeat: number;
  invalid: number;
}

export interface MockDataset {
  csvText: string;
  roster: RosterEntry[];
  expected: MockExpected;
}

/** 线性同余伪随机数发生器（固定种子 → 可复现） */
class SeededRandom {
  private seed: number;

  constructor(seed: number) {
    this.seed = seed;
  }

  next(): number {
    this.seed = (this.seed * 1664525 + 1013904223) % 4294967296;
    return this.seed / 4294967296;
  }

  int(min: number, max: number): number {
    return min + Math.floor(this.next() * (max - min + 1));
  }

  pick<T>(list: T[]): T {
    return list[this.int(0, list.length - 1)];
  }
}

const SURNAMES: string[] = [
  '王', '李', '张', '刘', '陈', '杨', '黄', '赵', '周', '吴',
  '徐', '孙', '马', '朱', '胡', '郭', '何', '林', '高', '罗',
];

const GIVEN_NAMES: string[] = [
  '伟', '芳', '娜', '敏', '静', '磊', '强', '洋', '艳', '勇',
  '军', '杰', '涛', '明', '超', '霞', '平', '刚', '桂英', '雪',
];

const DEPARTMENTS: string[] = [
  '产品部', '研发部', '设计部', '市场部', '运营部', '人力资源部', '财务部', '客户成功部',
];

const CHANNELS: string[] = ['扫码签到', '手工补录', '闸机刷卡', '小程序'];

const ACTIVITIES: string[] = ['ACT-2026-001', 'ACT-2026-002', 'ACT-2026-003'];

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

function formatTime(base: Date, offsetMinutes: number): string {
  const t: Date = new Date(base.getTime() + offsetMinutes * 60 * 1000);
  return `${t.getFullYear()}-${pad2(t.getMonth() + 1)}-${pad2(t.getDate())} ` +
    `${pad2(t.getHours())}:${pad2(t.getMinutes())}:${pad2(t.getSeconds())}`;
}

/**
 * 生成演示数据集。
 *
 * @param participantCount 参与人数（默认 120）
 * @param seed             随机种子（默认 20261014）
 */
export function generateMockDataset(participantCount: number = 120, seed: number = 20261014): MockDataset {
  const rnd: SeededRandom = new SeededRandom(seed);
  const baseDate: Date = new Date(2026, 9, 14, 9, 0, 0);

  const roster: RosterEntry[] = [];
  const people: Person[] = [];
  for (let i: number = 0; i < participantCount; i++) {
    const id: string = `E${1000 + i}`;
    const name: string = `${rnd.pick(SURNAMES)}${rnd.pick(GIVEN_NAMES)}`;
    const dept: string = rnd.pick(DEPARTMENTS);
    people.push({ id, name, dept });
  }

  const lines: string[] = ['活动ID,参与者ID,姓名,部门,签到时间,签到方式'];
  let totalRows: number = 0;
  let exactDup: number = 0;
  let repeat: number = 0;
  let invalid: number = 0;

  for (const activityId of ACTIVITIES) {
    const attendanceRatio: number = activityId === 'ACT-2026-001' ? 0.88
      : activityId === 'ACT-2026-002' ? 0.72 : 0.95;

    for (const person of people) {
      if (rnd.next() > attendanceRatio) {
        continue;
      }
      const dept: string = rnd.pick(DEPARTMENTS);
      const minute: number = rnd.int(0, 70);
      const time: string = formatTime(baseDate, minute);
      const channel: string = rnd.pick(CHANNELS);

      lines.push(`${activityId},${person.id},${person.name},${dept},${time},${channel}`);
      totalRows++;

      if (rnd.next() < 0.10) {
        lines.push(`${activityId},${person.id},${person.name},${dept},${time},${rnd.pick(CHANNELS)}`);
        totalRows++;
        exactDup++;
      }

      if (rnd.next() < 0.06) {
        lines.push(`${activityId},${person.id},${person.name},${dept},${formatTime(baseDate, minute + rnd.int(60, 300))},手工补录`);
        totalRows++;
        repeat++;
      }
    }

    for (let k: number = 0; k < 3; k++) {
      if (k === 0) {
        lines.push(`${activityId},,${rnd.pick(SURNAMES)}某,${rnd.pick(DEPARTMENTS)},${formatTime(baseDate, 30)},扫码签到`);
      } else if (k === 1) {
        lines.push(`${activityId},E${2000 + rnd.int(0, 99)},测试用户,${rnd.pick(DEPARTMENTS)},待补充,扫码签到`);
      } else {
        lines.push(`,E${3000 + rnd.int(0, 99)},匿名用户,${rnd.pick(DEPARTMENTS)},${formatTime(baseDate, 45)},闸机刷卡`);
      }
      totalRows++;
      invalid++;
    }
  }

  const expected: MockExpected = { totalRows, exactDup, repeat, invalid };
  return { csvText: lines.join('\r\n'), roster, expected };
}

export const MINI_DEMO_CSV: string = [
  '活动ID,参与者ID,姓名,部门,签到时间,签到方式',
  'ACT-2026-001,E1001,王伟,研发部,2026-10-14 09:05:12,扫码签到',
  'ACT-2026-001,E1002,李芳,产品部,2026-10-14 09:07:30,扫码签到',
  'ACT-2026-001,E1003,张娜,设计部,2026-10-14 09:12:44,小程序',
  'ACT-2026-001,E1001,王伟,研发部,2026-10-14 09:05:12,手工补录',
  'ACT-2026-001,E1002,李芳,产品部,2026-10-14 10:30:00,闸机刷卡',
  'ACT-2026-001,E1004,刘敏,市场部,待定,扫码签到',
  'ACT-2026-002,E1001,王伟,研发部,2026-10-14 14:02:08,扫码签到',
  'ACT-2026-002,,赵磊,运营部,2026-10-14 14:05:00,扫码签到',
  'ACT-2026-002,E1002,李芳,产品部,2026-10-14 14:06:19,小程序',
  'ACT-2026-003,E1003,张娜,设计部,2026-10-15 10:00:00,扫码签到',
  'ACT-2026-003,E1002,李芳,产品部,2026-10-15 10:01:33,扫码签到',
  'ACT-2026-003,E1002,李芳,产品部,2026-10-15 10:01:33,闸机刷卡',
].join('\r\n');

export function parseMockCsv(csv: string = MINI_DEMO_CSV): CheckinRecord[] {
  return parseCheckinCsv(csv);
}

export function recordToCsvLine(r: CheckinRecord): string {
  return [r.activityId, r.participantId, r.participantName, r.group, r.checkinTime, r.channel].join(',');
}

export { buildRecordKey };
