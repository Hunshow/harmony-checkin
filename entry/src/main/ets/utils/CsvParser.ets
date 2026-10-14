import { CheckinRecord } from '../model/Types';
import { Logger } from './Logger';

/**
 * CSV 解析器
 * ------------------------------------------------------------------
 * 设计要点：
 * 1. 支持逗号 / 分号 / Tab 自动嗅探分隔符（Excel 导出常带分号）。
 * 2. 正确处理 RFC4180 引号转义（"" 表示一个引号字符）与字段内换行。
 * 3. 表头列名做「模糊别名映射」，兼容各家签到系统五花八门的列名。
 * 4. 解析失败的行不丢弃，标记为异常记录交给上层，保证「原始条数」可追溯。
 */

/** 解析选项 */
export interface CsvParseOptions {
  /** 强制指定分隔符；不传则自动嗅探 */
  delimiter?: string;
  /** 表头所在行号（0 起），默认 0；用于跳过系统导出的标题行 */
  headerRowIndex?: number;
}

/** 原始解析结果：二维字符串表 */
export interface RawTable {
  header: string[];
  rows: string[][];
  delimiter: string;
  warnings: string[];
}

/**
 * 列名别名表。
 * key 是内部字段，value 是可能出现在真实 CSV 里的各种叫法。
 * 新增签到系统时，只需要往这里补别名。
 *
 * 注意 1：别名里不要放「参与者」这类会与其他列名互相包含的短词——
 * 「参与者ID」归一化后是「参与者id」，用「参与者」做包含匹配会把它误判成姓名列。
 * 注意 2：ArkTS 严格模式不允许 Record 字面量裸 key，这里用 Map 构建。
 */
function buildColumnAliases(): Map<string, string[]> {
  const map: Map<string, string[]> = new Map<string, string[]>();
  map.set('activityId', ['活动id', '活动编号', 'activityid', '活动', '场次id', '会议id']);
  map.set('participantId', ['参与者id', '工号', '学号', '用户id', 'userid', '人员编号', 'memberid', '手机号', 'phone', '身份证号']);
  map.set('participantName', ['姓名', '参与者姓名', '用户姓名', '员工姓名', 'name', 'username', '昵称']);
  map.set('group', ['部门', '班级', '分组', '组织', '单位', 'dept', 'department', 'group', 'team', '所属部门']);
  map.set('checkinTime', ['签到时间', '打卡时间', '时间', 'checkintime', 'time', 'createdat', '创建时间', '签到日期']);
  map.set('channel', ['签到方式', '渠道', '来源', '方式', 'channel', 'source', 'method', '签到渠道']);
  return map;
}

const COLUMN_ALIASES: Map<string, string[]> = buildColumnAliases();

/** 必填字段：缺一不可，否则整列无法使用 */
const REQUIRED_FIELDS: string[] = ['activityId', 'participantId'];

/**
 * 嗅探分隔符：在首行里统计候选字符出现次数，取最多的那个。
 * 优先保证「列数最多」而不是「出现次数最多」，避免把时间里的冒号误判。
 */
function sniffDelimiter(firstLine: string): string {
  const candidates: string[] = [',', ';', '\t', '|'];
  let best: string = ',';
  let bestCount: number = -1;
  for (const c of candidates) {
    const count: number = firstLine.split(c).length - 1;
    if (count > bestCount) {
      bestCount = count;
      best = c;
    }
  }
  return best;
}

/**
 * 把整段文本切成 CSV 记录（处理引号与字段内换行）。
 * 不用 split 的原因：引号内的分隔符与换行都不应断开字段。
 */
function splitCsvLines(text: string, delimiter: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field: string = '';
  let inQuotes: boolean = false;
  let i: number = 0;

  // 统一换行符，避免 \r 残留污染最后一个字段
  const src: string = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');

  while (i < src.length) {
    const ch: string = src[i];

    if (inQuotes) {
      if (ch === '"') {
        if (src[i + 1] === '"') {
          // 转义的双引号
          field += '"';
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      field += ch;
      i++;
      continue;
    }

    if (ch === '"' && field.length === 0) {
      inQuotes = true;
      i++;
      continue;
    }

    if (ch === delimiter) {
      row.push(field);
      field = '';
      i++;
      continue;
    }

    if (ch === '\n') {
      row.push(field);
      rows.push(row);
      row = [];
      field = '';
      i++;
      continue;
    }

    field += ch;
    i++;
  }

  // 收尾：最后一行可能没有换行符
  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }

  return rows;
}

/** 归一化列名：去空格、去全角空格、转小写、去下划线 */
function normalizeHeader(name: string): string {
  return name
    .replace(/\uFEFF/g, '')   // 去掉 UTF-8 BOM，Excel 导出常见
    .replace(/[\s\u3000]/g, '') // 去半角/全角空格
    .replace(/_/g, '')
    .toLowerCase();
}

/**
 * 把表头行映射为「内部字段 -> 列下标」。
 *
 * 分两轮匹配，避免短别名抢走别的列：
 *   第 1 轮：只认完全相等的列名（最可靠，优先占位）
 *   第 2 轮：再用「包含」做兜底，处理「活动ID(必填)」这类带前后缀的列名
 * 每列只能被认领一次，防止一列同时被两个字段占用。
 */
function buildColumnIndex(header: string[]): Map<string, number> {
  const index: Map<string, number> = new Map<string, number>();
  const normalized: string[] = header.map((h: string) => normalizeHeader(h));
  const claimed: Set<number> = new Set<number>();

  const tryMatch = (field: string, exactOnly: boolean): void => {
    if (index.has(field)) {
      return;
    }
    const rawAliases: string[] | undefined = COLUMN_ALIASES.get(field);
    if (rawAliases === undefined) {
      return;
    }
    const aliases: string[] = rawAliases.map((a: string) => normalizeHeader(a));
    for (let col: number = 0; col < normalized.length; col++) {
      if (claimed.has(col)) {
        continue;
      }
      const head: string = normalized[col];
      if (head.length === 0) {
        continue;
      }
      const hit: boolean = exactOnly
        ? aliases.indexOf(head) >= 0
        : aliases.some((a: string) => head.indexOf(a) >= 0);
      if (hit) {
        index.set(field, col);
        claimed.add(col);
        return;
      }
    }
  };

  for (const field of COLUMN_ALIASES.keys()) {
    tryMatch(field, true);
  }
  for (const field of COLUMN_ALIASES.keys()) {
    tryMatch(field, false);
  }

  return index;
}

/**
 * 解析日期时间字符串为时间戳。
 * 覆盖常见格式：
 *  2026-10-14 09:30:00 / 2026/10/14 9:30 / 2026-10-14T09:30:00+08:00 / 2026年10月14日 09:30
 * 返回 NaN 表示无法解析。
 */
export function parseDateTime(raw: string): number {
  const s: string = raw.trim();
  if (s.length === 0) {
    return NaN;
  }

  // 归一化中文日期分隔符与斜杠
  const normalized: string = s
    .replace(/年|月/g, '-')
    .replace(/日/g, ' ')
    .replace(/\//g, '-')
    .replace(/\s+/g, ' ')
    .trim();

  // 纯时间戳（10 位秒 / 13 位毫秒）
  if (/^\d{10}$/.test(normalized)) {
    return Number.parseInt(normalized, 10) * 1000;
  }
  if (/^\d{13}$/.test(normalized)) {
    return Number.parseInt(normalized, 10);
  }

  // 形如 2026-10-14 09:30(:ss)?  —— 手工解析，避免不同引擎对 Date 字符串解析的差异
  const m: RegExpMatchArray | null = normalized.match(
    /^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?/
  );
  if (m !== null) {
    const year: number = Number.parseInt(m[1], 10);
    const month: number = Number.parseInt(m[2], 10);
    const day: number = Number.parseInt(m[3], 10);
    const hour: number = m[4] !== undefined ? Number.parseInt(m[4], 10) : 0;
    const minute: number = m[5] !== undefined ? Number.parseInt(m[5], 10) : 0;
    const second: number = m[6] !== undefined ? Number.parseInt(m[6], 10) : 0;
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return NaN;
    }
    return new Date(year, month - 1, day, hour, minute, second).getTime();
  }

  // 最后兜底交给引擎
  const fallback: number = new Date(normalized).getTime();
  return Number.isNaN(fallback) ? NaN : fallback;
}

/** 生成记录的唯一键 */
export function buildRecordKey(activityId: string, participantId: string, timestamp: number, fallbackTime: string): string {
  const timePart: string = Number.isNaN(timestamp) ? `raw:${fallbackTime.trim()}` : `ts:${timestamp}`;
  return `${activityId.trim()}::${participantId.trim()}::${timePart}`;
}

/**
 * 将 CSV 文本解析为签到记录列表。
 * 解析不出关键字段的行不会抛异常，而是生成一条「异常记录」，
 * 由统计引擎统一归类，保证 UI 能提示用户「第 N 行有问题」。
 */
export function parseCheckinCsv(text: string, options?: CsvParseOptions): CheckinRecord[] {
  const warnings: string[] = [];
  const cleaned: string = text.replace(/^\uFEFF/, '');
  const firstLine: string = cleaned.split('\n')[0] ?? '';
  const delimiter: string = options?.delimiter ?? sniffDelimiter(firstLine);
  const headerRowIndex: number = options?.headerRowIndex ?? 0;

  const table: string[][] = splitCsvLines(cleaned, delimiter);
  if (table.length === 0) {
    Logger.warn('CSV 内容为空');
    return [];
  }

  const header: string[] = table[headerRowIndex] ?? [];
  const columnIndex: Map<string, number> = buildColumnIndex(header);

  const missing: string[] = REQUIRED_FIELDS.filter((f: string) => !columnIndex.has(f));
  if (missing.length > 0) {
    const message: string = `表头缺少必要列：${missing.join('、')}，解析结果可能不准确`;
    warnings.push(message);
    Logger.warn(message);
  }

  const records: CheckinRecord[] = [];

  for (let r: number = headerRowIndex + 1; r < table.length; r++) {
    const cells: string[] = table[r];
    // 跳过完全空行
    if (cells.length === 0 || cells.every((c: string) => c.trim().length === 0)) {
      continue;
    }

    const pick = (field: string): string => {
      const idx: number | undefined = columnIndex.get(field);
      if (idx === undefined || idx >= cells.length) {
        return '';
      }
      return cells[idx].trim();
    };

    const activityId: string = pick('activityId');
    const participantId: string = pick('participantId');
    const participantName: string = pick('participantName');
    const group: string = pick('group');
    const checkinTime: string = pick('checkinTime');
    const channel: string = pick('channel');
    const timestamp: number = parseDateTime(checkinTime);

    records.push({
      key: buildRecordKey(activityId, participantId, timestamp, checkinTime),
      activityId,
      participantId,
      participantName,
      group,
      checkinTime,
      timestamp,
      channel,
      lineNo: r + 1, // 转为 1 起，与用户在表格里看到的行号一致
    });
  }

  Logger.info(`CSV 解析完成：分隔符「${delimiter}」，有效行 ${records.length} 条`);
  return records;
}

/** 把二维表还原成 CSV 文本（导出用，含 RFC4180 转义） */
export function toCsv(header: string[], rows: string[][]): string {
  const escape = (value: string): string => {
    const v: string = value ?? '';
    const needQuote: boolean = v.indexOf(',') >= 0 || v.indexOf('"') >= 0 || v.indexOf('\n') >= 0 || v.indexOf('\r') >= 0;
    if (!needQuote) {
      return v;
    }
    return `"${v.replace(/"/g, '""')}"`;
  };

  const lines: string[] = [];
  lines.push(header.map(escape).join(','));
  for (const row of rows) {
    lines.push(row.map(escape).join(','));
  }
  // 加 BOM，保证 Excel 直接双击打开不乱码
  return `\uFEFF${lines.join('\r\n')}`;
}
