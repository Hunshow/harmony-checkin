import { AnalysisResult, CheckinRecord } from '../model/Types';
import { ExportResult } from '../utils/Exporter';

/** 页面页签 */
export enum TabKey {
  Overview = 'overview',
  Records = 'records',
  Duplicates = 'duplicates',
  Participants = 'participants',
  Export = 'export',
}

/**
 * 应用数据聚合
 * ------------------------------------------------------------------
 * 所有 @Observed 字段都是「UI 直接绑定」的，其余（rawRecords/result）作为派生源。
 * 注意：ArkTS 下 @Observed 类里放复杂对象，赋值需整体替换才能触发刷新，
 * 因此分析结果统一用整体赋值而不是就地修改。
 */
@Observed
export class AppData {
  /** 当前页签 */
  activeTab: string = TabKey.Overview;

  /** 原始记录（解析后、去重前） */
  rawRecords: CheckinRecord[] = [];

  /** 分析结果，null 表示尚未导入 */
  result: AnalysisResult | null = null;

  /** 导入框文本 */
  inputText: string = '';

  /** 是否正在分析（大文件时显示 loading） */
  analyzing: boolean = false;

  /** 上次导入的文件名/来源描述 */
  sourceLabel: string = '';

  /** 是否使用名册计算出席率 */
  useRoster: boolean = true;

  /** Toast 提示文本，空串表示不显示 */
  toast: string = '';

  /** 错误提示 */
  errorText: string = '';

  /** 最近一次导出结果 */
  lastExport: ExportResult | null = null;

  /** 明细页筛选：只看重复记录 */
  filterDupOnly: boolean = false;

  /** 明细页搜索关键字 */
  searchKeyword: string = '';

  /** 是否已导入数据 */
  get hasData(): boolean {
    return this.result !== null && this.rawRecords.length > 0;
  }

  /** 清空全部数据 */
  reset(): void {
    this.rawRecords = [];
    this.result = null;
    this.inputText = '';
    this.sourceLabel = '';
    this.toast = '';
    this.errorText = '';
    this.lastExport = null;
    this.filterDupOnly = false;
    this.searchKeyword = '';
    this.activeTab = TabKey.Overview;
  }
}
