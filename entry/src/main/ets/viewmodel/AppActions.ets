import { common } from '@kit.AbilityKit';
import {
  ACTIVITY_CSV_HEADER,
  DUPLICATE_CSV_HEADER,
  PARTICIPANT_CSV_HEADER,
  analyze,
  buildActivityCsvRows,
  buildDuplicateCsvRows,
  buildParticipantCsvRows,
  buildRosterMap,
} from '../utils/Statistics';
import { CheckinRecord, RosterEntry } from '../model/Types';
import { parseCheckinCsv } from '../utils/CsvParser';
import { exportCsv, ExportResult, timestampedName } from '../utils/Exporter';
import { generateMockDataset, MINI_DEMO_CSV } from '../utils/MockData';
import { Logger } from '../utils/Logger';
import { AppData } from './AppData';

/**
 * 应用业务动作（Action 层）
 * ------------------------------------------------------------------
 * 把「解析 → 分析 → 更新状态 → 导出」编排成方法，页面只负责触发与展示。
 * 这样 UI 层不掺杂业务逻辑，也方便将来替换为真正的数据源。
 */
export class AppActions {
  private data: AppData;

  constructor(data: AppData) {
    this.data = data;
  }

  /** 载入演示数据（大规模，用于展示统计能力） */
  loadLargeDemo(): void {
    const dataset = generateMockDataset();
    this.importFromText(dataset.csvText, `内置演示数据（约 ${dataset.expected.totalRows} 行）`, dataset.roster);
  }

  /** 载入迷你示例（约 12 行，可人工逐行核对） */
  loadMiniDemo(): void {
    const dataset = generateMockDataset(20);
    this.importFromText(MINI_DEMO_CSV, '迷你示例（12 行，含重复与异常）', dataset.roster);
  }

  /**
   * 从 CSV 文本导入。
   * @param text     CSV 内容
   * @param label    来源描述，显示在界面上
   * @param roster   可选名册，用于算出席率
   */
  importFromText(text: string, label: string, roster?: RosterEntry[]): boolean {
    const trimmed: string = text.trim();
    if (trimmed.length === 0) {
      this.data.errorText = '导入内容为空，请粘贴 CSV 文本或加载示例数据';
      return false;
    }

    this.data.analyzing = true;
    this.data.errorText = '';

    try {
      const records: CheckinRecord[] = parseCheckinCsv(trimmed);
      if (records.length === 0) {
        this.data.errorText = '未解析出任何数据行，请检查是否包含表头（活动ID/参与者ID/签到时间）';
        this.data.analyzing = false;
        return false;
      }

      const rosterMap = roster !== undefined && this.data.useRoster ? buildRosterMap(roster) : undefined;
      const result = analyze(records, rosterMap);

      this.data.rawRecords = records;
      this.data.result = result;
      this.data.sourceLabel = label;
      this.data.analyzing = false;
      this.data.activeTab = 'overview';

      const parts: string[] = [`已导入 ${records.length} 条记录`];
      if (result.summary.exactDupCount > 0) {
        parts.push(`完全重复 ${result.summary.exactDupCount} 条`);
      }
      if (result.summary.repeatCount > 0) {
        parts.push(`多次签到 ${result.summary.repeatCount} 条`);
      }
      this.data.toast = `${parts.join('，')}，数据质量分 ${result.summary.qualityScore}`;
      return true;
    } catch (err) {
      Logger.error(`导入失败：${(err as Error).message}`);
      this.data.errorText = `导入失败：${(err as Error).message}`;
      this.data.analyzing = false;
      return false;
    }
  }

  /** 重新分析（切换名册开关后调用） */
  reanalyze(roster?: RosterEntry[]): void {
    if (this.data.rawRecords.length === 0) {
      return;
    }
    const rosterMap = roster !== undefined && this.data.useRoster ? buildRosterMap(roster) : undefined;
    this.data.result = analyze(this.data.rawRecords, rosterMap);
  }

  /**
   * 导出三类 CSV。
   * @param which 'participants' | 'activities' | 'duplicates' | 'all'
   */
  async exportData(context: common.UIAbilityContext, which: string): Promise<ExportResult[]> {
    const result = this.data.result;
    if (result === null) {
      this.data.errorText = '暂无可导出的数据，请先导入签到记录';
      return [];
    }

    const outputs: ExportResult[] = [];

    if (which === 'participants' || which === 'all') {
      outputs.push(await exportCsv(
        context,
        timestampedName('参与明细'),
        PARTICIPANT_CSV_HEADER,
        buildParticipantCsvRows(result.participants)
      ));
    }

    if (which === 'activities' || which === 'all') {
      outputs.push(await exportCsv(
        context,
        timestampedName('活动汇总'),
        ACTIVITY_CSV_HEADER,
        buildActivityCsvRows(result.activities)
      ));
    }

    if (which === 'duplicates' || which === 'all') {
      const dupRows = buildDuplicateCsvRows(result.records);
      if (dupRows.length === 0) {
        this.data.toast = '当前数据没有重复记录，无需导出重复清单';
        return outputs;
      }
      outputs.push(await exportCsv(
        context,
        timestampedName('重复记录清单'),
        DUPLICATE_CSV_HEADER,
        dupRows
      ));
    }

    if (outputs.length > 0) {
      this.data.lastExport = outputs[outputs.length - 1];
      const okCount: number = outputs.filter((o: ExportResult) => o.success).length;
      this.data.toast = okCount === outputs.length
        ? `已导出 ${okCount} 个文件`
        : `导出完成，但有 ${outputs.length - okCount} 个文件失败`;
      if (okCount < outputs.length) {
        this.data.errorText = outputs.find((o: ExportResult) => !o.success)?.message ?? '';
      }
    }

    return outputs;
  }

  /** 顶层统计口径说明，放在 UI 上帮助用户理解「实到人数」是怎么来的 */
  static readonly METHOD_NOTE: string =
    '统计口径：实到人数 = 同一活动下去重后的唯一参与者数（每人只计一次）；' +
    '同一人同一时间的多条记录计为「完全重复」，同一人多时间的记录计为「多次签到」，' +
    '两者都会保留最早一条作为有效出席。出席率 = 实到人数 / 名册人数。';
}
