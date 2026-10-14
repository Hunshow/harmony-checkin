/**
 * 领域模型定义
 * ------------------------------------------------------------------
 * 全部使用 interface + 纯数据，方便序列化（持久化 / 导出 / 单元测试）。
 */

/** 一条签到记录（CSV 一行） */
export interface CheckinRecord {
  /** 稳定唯一键：由「活动ID + 参与者ID + 签到时间」计算，用于精确判重 */
  key: string;
  /** 活动 ID（同一份数据里应唯一标识一场活动） */
  activityId: string;
  /** 参与者 ID（工号 / 学号 / 手机号等稳定标识） */
  participantId: string;
  /** 参与者姓名 */
  participantName: string;
  /** 部门 / 班级 / 分组，可为空 */
  group: string;
  /** 签到时间，原始字符串（保留用于展示，避免时区二次加工） */
  checkinTime: string;
  /** 解析后的时间戳（毫秒）。无法解析时为 NaN，会被标记为「时间异常」 */
  timestamp: number;
  /** 签到渠道：扫码 / 手工 / 闸机 等 */
  channel: string;
  /** 原始行号（含表头偏移），便于用户回表核对 */
  lineNo: number;
}

/** 判重结果分类 */
export enum DupKind {
  /** 非重复 */
  None = 'none',
  /** 完全重复：同一人 + 同一活动 + 同一签到时间 */
  Exact = 'exact',
  /** 同人同活动多次签到（不同时间），属于多次签到需人工确认 */
  Repeat = 'repeat',
  /** 关键字段缺失或时间无法解析 */
  Invalid = 'invalid',
}

/** 带判重标注的记录（唯一事实来源，UI 直接消费） */
export interface AnalyzedRecord {
  record: CheckinRecord;
  kind: DupKind;
  /**
   * 重复组 ID。同一个人在同一活动下的所有记录共享一个组 ID，
   * 便于 UI 折叠展示「该人签到了 N 次」。
   */
  groupId: string;
  /** 是否为该「人 + 活动」组合下保留的唯一有效记录（首次签到） */
  isPrimary: boolean;
}

/** 单个参与者的参与情况 */
export interface ParticipantStat {
  participantId: string;
  participantName: string;
  group: string;
  /** 有效签到次数（去重后） */
  validCount: number;
  /** 原始签到次数（含重复） */
  rawCount: number;
  /** 重复条数 */
  dupCount: number;
  /** 首次签到时间 */
  firstTime: string;
  /** 末次签到时间 */
  lastTime: string;
}

/** 单场活动的统计 */
export interface ActivityStat {
  activityId: string;
  /** 应到人数（来自名册，未提供时为 0，表示未导入名册） */
  expectedCount: number;
  /** 实到人数（去重后的唯一参与者数） */
  actualCount: number;
  /** 签到总条数（原始） */
  rawCount: number;
  /** 重复条数 */
  dupCount: number;
  /** 异常条数 */
  invalidCount: number;
  /** 出席率，0~1；无名册时为 -1 表示不可计算 */
  attendanceRate: number;
}

/** 全局汇总 */
export interface SummaryStat {
  activityCount: number;
  participantCount: number;
  rawRecordCount: number;
  validRecordCount: number;
  exactDupCount: number;
  repeatCount: number;
  invalidCount: number;
  /** 整体出席率，无名册时为 -1 */
  overallAttendanceRate: number;
  /** 数据质量分 0~100，用于一眼判断数据是否可直接使用 */
  qualityScore: number;
}

/** 完整分析结果 */
export interface AnalysisResult {
  records: AnalyzedRecord[];
  activities: ActivityStat[];
  participants: ParticipantStat[];
  summary: SummaryStat;
  /** 解析阶段产生的告警（表头缺失、行格式错误等） */
  warnings: string[];
  /** 生成时间，ISO 字符串 */
  generatedAt: string;
}

/** 活动名册（用于计算出席率） */
export interface RosterEntry {
  activityId: string;
  participantId: string;
  participantName: string;
  group: string;
}

/** 名册查询表：activityId -> Set<participantId> */
export type RosterMap = Map<string, Set<string>>;
