import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { Tokens } from '../common/Tokens';
import { appStore } from '../common/AppStore';
import { AppData, TabKey } from '../viewmodel/AppData';
import { AppActions } from '../viewmodel/AppActions';
import { SectionCard } from '../components/SectionCard';
import { EmptyState, Pill, StatTile } from '../components/StatTile';
import { ActivityRow } from '../components/ActivityRow';
import { RecordTable } from '../components/RecordTable';
import { ParticipantList } from '../components/ParticipantList';
import { QualityPanel } from '../components/QualityPanel';
import { TimeDistributionChart } from '../components/TimeDistributionChart';
import { AnalyzedRecord, ActivityStat, DupKind, ParticipantStat } from '../model/Types';
import { MINI_DEMO_CSV, generateMockDataset } from '../utils/MockData';
import { Logger } from '../utils/Logger';

/**
 * 主页面
 * ------------------------------------------------------------------
 * 结构：顶部工具栏 → 导入区 → 页签导航 → 对应内容区
 * 布局：PC（宽度 >= 840）用双列/表格式排布；窄屏自动切单列堆叠。
 */
@Entry
@Component
struct Index {
  /**
   * 直接把 AppData 挂成 @State：
   * @State 观察它所包对象的第一层属性（result / activeTab / toast 等），
   * 导入数据时对 result 的整体赋值就能触发界面刷新。
   * 注意 AppActions 必须持有这个被代理的实例（见 aboutToAppear），写入才会被观察到。
   */
  @State data: AppData = appStore.data;
  /** 是否宽屏（PC / 平板横屏） */
  @State isWide: boolean = true;
  /** 导入对话框可见性 */
  @State showImportDialog: boolean = false;
  /** 导入对话框内的临时文本 */
  @State draftText: string = '';
  /** 明细搜索框内容 */
  @State keyword: string = '';

  private actions: AppActions | null = null;

  aboutToAppear(): void {
    // 传 this.data（@State 代理后的实例）而不是原始对象，否则状态变更不会触发刷新
    this.actions = new AppActions(this.data);
    Logger.info('页面加载完成，等待导入签到数据');
  }

  /** 计算表格可用高度：宽屏给固定高度，窄屏给小一点 */
  private tableHeight(): number {
    return this.isWide ? 520 : 380;
  }

  // ================= 数据操作 =================

  private doImport(text: string, label: string, withRoster: boolean): void {
    if (this.actions === null) {
      return;
    }
    const dataset = generateMockDataset();
    const roster = withRoster ? dataset.roster : undefined;
    const ok: boolean = this.actions.importFromText(text, label, roster);
    this.showImportDialog = false;
    this.draftText = '';
    if (ok) {
      this.toast(this.data.toast);
    } else {
      this.toast(this.data.errorText);
    }
  }

  private toast(message: string): void {
    if (message.length === 0) {
      return;
    }
    promptAction.showToast({ message, duration: 2600 });
  }

  private resetAll(): void {
    this.data.reset();
    this.keyword = '';
    this.toast('已清空全部数据');
  }

  private openImportDialog(): void {
    this.draftText = this.data.inputText;
    this.showImportDialog = true;
  }

  // ================= 过滤逻辑 =================

  /** 明细页数据：按关键字与「仅看重复」筛选 */
  private filteredRecords(): AnalyzedRecord[] {
    const result = this.data.result;
    if (result === null) {
      return [];
    }
    const kw: string = this.keyword.trim().toLowerCase();
    return result.records.filter((item: AnalyzedRecord) => {
      if (this.data.filterDupOnly && item.kind === DupKind.None) {
        return false;
      }
      if (kw.length === 0) {
        return true;
      }
      const r = item.record;
      return (
        r.participantId.toLowerCase().indexOf(kw) >= 0 ||
        r.participantName.toLowerCase().indexOf(kw) >= 0 ||
        r.activityId.toLowerCase().indexOf(kw) >= 0 ||
        r.group.toLowerCase().indexOf(kw) >= 0
      );
    });
  }

  /** 参与者列表过滤 */
  private filteredParticipants(): ParticipantStat[] {
    const result = this.data.result;
    if (result === null) {
      return [];
    }
    const kw: string = this.keyword.trim().toLowerCase();
    if (kw.length === 0) {
      return result.participants;
    }
    return result.participants.filter((p: ParticipantStat) =>
      p.participantId.toLowerCase().indexOf(kw) >= 0 ||
      p.participantName.toLowerCase().indexOf(kw) >= 0 ||
      p.group.toLowerCase().indexOf(kw) >= 0
    );
  }

  // ================= 构建 =================

  build() {
    Column() {
      this.topBar()

      Scroll() {
        Column({ space: Tokens.SPACE_MD }) {
          this.importSection()

          if (this.data.result !== null) {
            this.tabBar()
            this.tabContent()
          } else {
            SectionCard({ title: '开始使用' }) {
              EmptyState({
                title: '还没有导入签到数据',
                description: '点击右上角「导入签到结果」粘贴 CSV 文本，或直接加载内置演示数据体验完整流程。\n支持列名：活动ID / 参与者ID / 姓名 / 部门 / 签到时间 / 签到方式',
              })
            }
          }

          this.footerNote()
        }
        .width('100%')
        .constraintSize({ maxWidth: Tokens.CONTENT_MAX_WIDTH })
        .padding({ left: Tokens.SPACE_LG, right: Tokens.SPACE_LG, bottom: Tokens.SPACE_XL })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Tokens.BG_PAGE)
    .onAreaChange((_: Area, newArea: Area) => {
      const w: number = Number.parseFloat(`${newArea.width}`);
      this.isWide = w >= Tokens.BREAKPOINT_NARROW;
    })
    .bindSheet($$this.showImportDialog, this.importSheet(), {
      height: this.isWide ? 520 : 560,
      dragBar: true,
      showClose: true,
    })
  }

  // ================= 顶部工具栏 =================

  @Builder
  topBar() {
    Row() {
      Column() {
        Row({ space: Tokens.SPACE_SM }) {
          Text('活动签到与参与统计')
            .fontSize(this.isWide ? 22 : 18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Tokens.TEXT_PRIMARY)
        }
        Text('导入签到结果 · 自动查重 · 参与情况汇总 · 一键导出')
          .fontSize(Tokens.FONT_XS)
          .fontColor(Tokens.TEXT_TERTIARY)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row({ space: Tokens.SPACE_SM }) {
        Button('加载演示数据')
          .fontSize(Tokens.FONT_SM)
          .fontColor(Tokens.PRIMARY)
          .backgroundColor(Tokens.PRIMARY_LIGHT)
          .onClick(() => {
            const dataset = generateMockDataset();
            this.doImport(dataset.csvText, `内置演示数据（约 ${dataset.expected.totalRows} 行）`, true);
          })

        Button('导入签到结果')
          .fontSize(Tokens.FONT_SM)
          .fontColor(Tokens.TEXT_ON_PRIMARY)
          .backgroundColor(Tokens.PRIMARY)
          .onClick(() => this.openImportDialog())
      }
    }
    .width('100%')
    .padding({ left: Tokens.SPACE_LG, right: Tokens.SPACE_LG, top: Tokens.SPACE_MD, bottom: Tokens.SPACE_MD })
    .backgroundColor(Tokens.BG_CARD)
    .border({ width: { bottom: 1 }, color: Tokens.BORDER })
  }

  // ================= 导入区 =================

  @Builder
  importSection() {
    SectionCard({
      title: '数据源',
      subtitle: this.data.sourceLabel.length > 0
        ? `当前数据来源：${this.data.sourceLabel}`
        : '支持从签到系统 / 扫码工具导出的 CSV 文本，表头列名可自动识别',
    }) {
      Column({ space: Tokens.SPACE_MD }) {
        if (this.data.result !== null) {
          Row({ space: Tokens.SPACE_SM }) {
            Pill({
              text: `${this.data.rawRecords.length} 条原始记录`,
              color: Tokens.PRIMARY,
              bg: Tokens.PRIMARY_LIGHT,
            })
            Pill({
              text: `${this.data.result.summary.activityCount} 场活动`,
              color: Tokens.INFO,
              bg: Tokens.INFO_LIGHT,
            })
            Pill({
              text: `${this.data.result.summary.participantCount} 位参与者`,
              color: Tokens.SUCCESS,
              bg: Tokens.SUCCESS_LIGHT,
            })
            if (this.data.result.summary.exactDupCount + this.data.result.summary.repeatCount > 0) {
              Pill({
                text: `待处理 ${this.data.result.summary.exactDupCount + this.data.result.summary.repeatCount} 条`,
                color: Tokens.WARNING,
                bg: Tokens.WARNING_LIGHT,
              })
            }
            Blank()
            Button('清空数据')
              .fontSize(Tokens.FONT_XS)
              .fontColor(Tokens.TEXT_TERTIARY)
              .backgroundColor(Tokens.BG_SUBTLE)
              .onClick(() => this.resetAll())
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        } else {
          Row({ space: Tokens.SPACE_SM }) {
            Button('加载迷你示例（12 行）')
              .fontSize(Tokens.FONT_SM)
              .fontColor(Tokens.PRIMARY)
              .backgroundColor(Tokens.PRIMARY_SOFT)
              .onClick(() => {
                this.doImport(MINI_DEMO_CSV, '迷你示例（12 行，含重复与异常）', true);
              })
            Button('加载 120 人演示数据')
              .fontSize(Tokens.FONT_SM)
              .fontColor(Tokens.INFO)
              .backgroundColor(Tokens.INFO_LIGHT)
              .onClick(() => {
                const dataset = generateMockDataset();
                this.doImport(dataset.csvText, `内置演示数据（约 ${dataset.expected.totalRows} 行）`, true);
              })
            Blank()
            Text('或粘贴自己的 CSV →')
              .fontSize(Tokens.FONT_XS)
              .fontColor(Tokens.TEXT_TERTIARY)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }

        if (this.data.errorText.length > 0) {
          Row({ space: Tokens.SPACE_SM }) {
            Text('⚠')
              .fontSize(Tokens.FONT_SM)
              .fontColor(Tokens.DANGER)
            Text(this.data.errorText)
              .fontSize(Tokens.FONT_XS)
              .fontColor(Tokens.DANGER)
              .layoutWeight(1)
          }
          .width('100%')
          .padding(Tokens.SPACE_SM)
          .backgroundColor(Tokens.DANGER_SOFT)
          .borderRadius(Tokens.RADIUS_SM)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  // ================= 导入对话框内容 =================

  @Builder
  importSheet() {
    Column({ space: Tokens.SPACE_MD }) {
      Text('把签到系统导出的 CSV 内容粘贴到下方（首行需为表头）')
        .fontSize(Tokens.FONT_SM)
        .fontColor(Tokens.TEXT_SECONDARY)

      TextArea({ text: this.draftText, placeholder: '活动ID,参与者ID,姓名,部门,签到时间,签到方式\nACT-2026-001,E1001,王伟,研发部,2026-10-14 09:05:12,扫码签到' })
        .width('100%')
        .height(200)
        .fontSize(Tokens.FONT_SM)
        .backgroundColor(Tokens.BG_SUBTLE)
        .borderRadius(Tokens.RADIUS_MD)
        .onChange((v: string) => {
          this.draftText = v;
        })

      Row({ space: Tokens.SPACE_SM }) {
        Text('列名支持别名，如「工号」「学号」可识别为参与者ID；时间支持 2026-10-14 09:30:00 / 2026/10/14 9:30 等格式')
          .fontSize(Tokens.FONT_XS)
          .fontColor(Tokens.TEXT_TERTIARY)
          .layoutWeight(1)
      }
      .width('100%')

      Row({ space: Tokens.SPACE_MD }) {
        Button('填入迷你示例')
          .fontSize(Tokens.FONT_SM)
          .fontColor(Tokens.PRIMARY)
          .backgroundColor(Tokens.PRIMARY_SOFT)
          .layoutWeight(1)
          .onClick(() => {
            this.draftText = MINI_DEMO_CSV;
          })
        Button('取消')
          .fontSize(Tokens.FONT_SM)
          .fontColor(Tokens.TEXT_SECONDARY)
          .backgroundColor(Tokens.BG_SUBTLE)
          .layoutWeight(1)
          .onClick(() => {
            this.showImportDialog = false;
          })
        Button('开始统计')
          .fontSize(Tokens.FONT_SM)
          .fontColor(Tokens.TEXT_ON_PRIMARY)
          .backgroundColor(Tokens.PRIMARY)
          .layoutWeight(1)
          .onClick(() => {
            this.doImport(this.draftText, '手动粘贴导入', true);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(Tokens.SPACE_LG)
    .alignItems(HorizontalAlign.Start)
  }

  // ================= 页签 =================

  @Builder
  tabBar() {
    Row({ space: Tokens.SPACE_XS }) {
      this.tabItem(TabKey.Overview, '总览', this.data.result !== null ? this.data.result.summary.activityCount : 0)
      this.tabItem(TabKey.Records, '签到明细',
        this.data.result !== null ? this.data.result.summary.rawRecordCount : 0)
      this.tabItem(TabKey.Duplicates, '重复检查',
        this.data.result !== null
          ? this.data.result.summary.exactDupCount + this.data.result.summary.repeatCount + this.data.result.summary.invalidCount
          : 0)
      this.tabItem(TabKey.Participants, '参与情况',
        this.data.result !== null ? this.data.result.summary.participantCount : 0)
      this.tabItem(TabKey.Export, '导出汇总', 0)
    }
    .width('100%')
    .padding(Tokens.SPACE_XS)
    .backgroundColor(Tokens.BG_CARD)
    .borderRadius(Tokens.RADIUS_LG)
    .shadow(Tokens.SHADOW)
  }

  @Builder
  tabItem(key: string, label: string, count: number) {
    Row({ space: Tokens.SPACE_XS }) {
      Text(label)
        .fontSize(Tokens.FONT_SM)
        .fontWeight(this.data.activeTab === key ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.data.activeTab === key ? Tokens.TEXT_ON_PRIMARY : Tokens.TEXT_SECONDARY)
      if (count > 0) {
        Text(`${count}`)
          .fontSize(10)
          .fontColor(this.data.activeTab === key ? Tokens.TEXT_ON_PRIMARY : Tokens.TEXT_TERTIARY)
          .backgroundColor(this.data.activeTab === key ? 'rgba(255,255,255,0.28)' : Tokens.BG_SUBTLE)
          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          .borderRadius(8)
      }
    }
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .height(38)
    .backgroundColor(this.data.activeTab === key ? Tokens.PRIMARY : Color.Transparent)
    .borderRadius(Tokens.RADIUS_MD)
    .onClick(() => {
      this.data.activeTab = key;
      this.keyword = '';
    })
  }

  // ================= 内容分发 =================

  @Builder
  tabContent() {
    if (this.data.activeTab === TabKey.Overview) {
      this.overviewTab()
    } else if (this.data.activeTab === TabKey.Records) {
      this.recordsTab()
    } else if (this.data.activeTab === TabKey.Duplicates) {
      this.duplicatesTab()
    } else if (this.data.activeTab === TabKey.Participants) {
      this.participantsTab()
    } else {
      this.exportTab()
    }
  }

  // ---- 总览 ----
  @Builder
  overviewTab() {
    Column({ space: Tokens.SPACE_MD }) {
      // 指标行
      if (this.isWide) {
        Row({ space: Tokens.SPACE_MD }) {
          StatTile({
            label: '签到总条数', value: `${this.data.result!.summary.rawRecordCount}`,
            hint: `有效 ${this.data.result!.summary.validRecordCount} 条`,
            accent: Tokens.PRIMARY, accentBg: Tokens.PRIMARY_SOFT, emphasized: true,
          })
          StatTile({
            label: '参与人数', value: `${this.data.result!.summary.participantCount}`,
            hint: '去重后的唯一参与者',
            accent: Tokens.SUCCESS, accentBg: Tokens.SUCCESS_LIGHT, emphasized: true,
          })
          StatTile({
            label: '场次', value: `${this.data.result!.summary.activityCount}`,
            hint: '数据中出现的活动数',
            accent: Tokens.INFO, accentBg: Tokens.INFO_LIGHT, emphasized: true,
          })
          StatTile({
            label: '整体出席率',
            value: this.data.result!.summary.overallAttendanceRate < 0
              ? '—'
              : `${(this.data.result!.summary.overallAttendanceRate * 100).toFixed(1)}%`,
            hint: this.data.result!.summary.overallAttendanceRate < 0 ? '未提供名册' : '实到 / 应到',
            accent: Tokens.WARNING, accentBg: Tokens.WARNING_SOFT, emphasized: true,
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      } else {
        Row({ space: Tokens.SPACE_MD }) {
          StatTile({
            label: '签到总条数', value: `${this.data.result!.summary.rawRecordCount}`,
            hint: `有效 ${this.data.result!.summary.validRecordCount} 条`,
            accent: Tokens.PRIMARY, accentBg: Tokens.PRIMARY_SOFT, emphasized: true,
          })
          StatTile({
            label: '参与人数', value: `${this.data.result!.summary.participantCount}`,
            hint: '去重后唯一参与者',
            accent: Tokens.SUCCESS, accentBg: Tokens.SUCCESS_LIGHT, emphasized: true,
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Row({ space: Tokens.SPACE_MD }) {
          StatTile({
            label: '场次', value: `${this.data.result!.summary.activityCount}`,
            hint: '数据中出现的活动数',
            accent: Tokens.INFO, accentBg: Tokens.INFO_LIGHT, emphasized: true,
          })
          StatTile({
            label: '整体出席率',
            value: this.data.result!.summary.overallAttendanceRate < 0
              ? '—'
              : `${(this.data.result!.summary.overallAttendanceRate * 100).toFixed(1)}%`,
            hint: '实到 / 应到',
            accent: Tokens.WARNING, accentBg: Tokens.WARNING_SOFT, emphasized: true,
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }

      // 质量 + 活动明细
      if (this.isWide) {
        Row({ space: Tokens.SPACE_MD }) {
          Column() {
            SectionCard({ title: '数据质量检查', subtitle: '导入后自动执行，无需人工排查' }) {
              QualityPanel({
                score: this.data.result!.summary.qualityScore,
                exactCount: this.data.result!.summary.exactDupCount,
                repeatCount: this.data.result!.summary.repeatCount,
                invalidCount: this.data.result!.summary.invalidCount,
                warnings: this.data.result!.warnings,
              })
            }
          }
          .layoutWeight(4)

          Column() {
            SectionCard({ title: '活动出席情况', subtitle: '按活动聚合，进度条为出席率' }) {
              Column({ space: Tokens.SPACE_SM }) {
                ForEach(this.data.result!.activities, (stat: ActivityStat) => {
                  ActivityRow({ stat })
                }, (stat: ActivityStat) => stat.activityId)
              }
              .width('100%')
            }
          }
          .layoutWeight(6)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      } else {
        SectionCard({ title: '数据质量检查' }) {
          QualityPanel({
            score: this.data.result!.summary.qualityScore,
            exactCount: this.data.result!.summary.exactDupCount,
            repeatCount: this.data.result!.summary.repeatCount,
            invalidCount: this.data.result!.summary.invalidCount,
            warnings: this.data.result!.warnings,
          })
        }
        SectionCard({ title: '活动出席情况' }) {
          Column({ space: Tokens.SPACE_SM }) {
            ForEach(this.data.result!.activities, (stat: ActivityStat) => {
              ActivityRow({ stat })
            }, (stat: ActivityStat) => stat.activityId)
          }
          .width('100%')
        }
      }

      // 时间分布
      SectionCard({ title: '签到时间分布', subtitle: '用于发现签到高峰与异常集中的批量导入' }) {
        TimeDistributionChart({ records: this.data.rawRecords })
      }
    }
    .width('100%')
  }

  // ---- 签到明细 ----
  @Builder
  recordsTab() {
    SectionCard({
      title: '签到明细',
      subtitle: '重复与异常记录已用底色和标签标注，可搜索参与者 / 活动 / 部门',
    }) {
      Column({ space: Tokens.SPACE_MD }) {
        Row({ space: Tokens.SPACE_MD }) {
          Search({ value: this.keyword, placeholder: '搜索参与者ID / 姓名 / 活动ID / 部门' })
            .layoutWeight(1)
            .height(36)
            .backgroundColor(Tokens.BG_SUBTLE)
            .onChange((v: string) => {
              this.keyword = v;
            })

          Row({ space: Tokens.SPACE_SM }) {
            Text('仅看重复/异常')
              .fontSize(Tokens.FONT_XS)
              .fontColor(Tokens.TEXT_SECONDARY)
            Toggle({ type: ToggleType.Switch, isOn: this.data.filterDupOnly })
              .onChange((isOn: boolean) => {
                this.data.filterDupOnly = isOn;
              })
          }
          .alignItems(VerticalAlign.Center)

          Text(`共 ${this.filteredRecords().length} 条`)
            .fontSize(Tokens.FONT_XS)
            .fontColor(Tokens.TEXT_TERTIARY)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.filteredRecords().length === 0) {
          EmptyState({ title: '没有符合条件的记录', description: '试试调整搜索关键字或关闭筛选' })
        } else {
          RecordTable({ records: this.filteredRecords(), maxHeight: this.tableHeight() })
        }
      }
      .width('100%')
    }
  }

  // ---- 重复检查 ----
  @Builder
  duplicatesTab() {
    Column({ space: Tokens.SPACE_MD }) {
      SectionCard({ title: '重复记录检查', subtitle: '导出前请先确认这些记录的处置方式' }) {
        QualityPanel({
          score: this.data.result!.summary.qualityScore,
          exactCount: this.data.result!.summary.exactDupCount,
          repeatCount: this.data.result!.summary.repeatCount,
          invalidCount: this.data.result!.summary.invalidCount,
          warnings: this.data.result!.warnings,
        })
      }

      SectionCard({
        title: '待处理记录清单',
        subtitle: '「完全重复」建议直接清理；「多次签到」需确认是否为有效出席',
      }) {
        Column({ space: Tokens.SPACE_MD }) {
          if (this.dupRecords().length === 0) {
            EmptyState({
              title: '数据干净，没有重复或异常记录',
              description: '可以直接进入「导出汇总」生成统计结果',
            })
          } else {
            RecordTable({ records: this.dupRecords(), maxHeight: this.tableHeight() })

            Button('导出重复记录清单（CSV）')
              .fontSize(Tokens.FONT_SM)
              .fontColor(Tokens.TEXT_ON_PRIMARY)
              .backgroundColor(Tokens.PRIMARY)
              .onClick(() => {
                this.handleExport('duplicates');
              })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
  }

  private dupRecords(): AnalyzedRecord[] {
    const result = this.data.result;
    if (result === null) {
      return [];
    }
    return result.records.filter((i: AnalyzedRecord) => i.kind !== DupKind.None);
  }

  // ---- 参与情况 ----
  @Builder
  participantsTab() {
    SectionCard({
      title: '参与者参与情况',
      subtitle: '按参与者聚合，展示跨活动的有效签到次数与时间区间',
    }) {
      Column({ space: Tokens.SPACE_MD }) {
        Row({ space: Tokens.SPACE_MD }) {
          Search({ value: this.keyword, placeholder: '搜索参与者ID / 姓名 / 部门' })
            .layoutWeight(1)
            .height(36)
            .backgroundColor(Tokens.BG_SUBTLE)
            .onChange((v: string) => {
              this.keyword = v;
            })
          Text(`共 ${this.filteredParticipants().length} 人`)
            .fontSize(Tokens.FONT_XS)
            .fontColor(Tokens.TEXT_TERTIARY)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        ParticipantList({ participants: this.filteredParticipants(), maxHeight: this.tableHeight() })
      }
      .width('100%')
    }
  }

  // ---- 导出 ----
  @Builder
  exportTab() {
    Column({ space: Tokens.SPACE_MD }) {
      SectionCard({
        title: '导出汇总',
        subtitle: '导出为 CSV（带 BOM，Excel 直接可打开），写入应用沙箱 Download 目录，无需任何权限',
      }) {
        Column({ space: Tokens.SPACE_MD }) {
          if (this.isWide) {
            Row({ space: Tokens.SPACE_MD }) {
              this.exportCard('参与明细', '每位参与者的有效签到次数、重复条数、时间区间', 'participants', Tokens.PRIMARY, Tokens.PRIMARY_SOFT)
              this.exportCard('活动汇总', '每场活动的实到/应到人数与出席率', 'activities', Tokens.SUCCESS, Tokens.SUCCESS_LIGHT)
              this.exportCard('重复记录清单', '完全重复 / 多次签到的逐条明细与处置建议', 'duplicates', Tokens.WARNING, Tokens.WARNING_SOFT)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          } else {
            Column({ space: Tokens.SPACE_MD }) {
              this.exportCard('参与明细', '每位参与者的有效签到次数、重复条数、时间区间', 'participants', Tokens.PRIMARY, Tokens.PRIMARY_SOFT)
              this.exportCard('活动汇总', '每场活动的实到/应到人数与出席率', 'activities', Tokens.SUCCESS, Tokens.SUCCESS_LIGHT)
              this.exportCard('重复记录清单', '完全重复 / 多次签到的逐条明细与处置建议', 'duplicates', Tokens.WARNING, Tokens.WARNING_SOFT)
            }
            .width('100%')
          }

          Button('一键导出全部 CSV')
            .width('100%')
            .height(44)
            .fontSize(Tokens.FONT_MD)
            .fontColor(Tokens.TEXT_ON_PRIMARY)
            .backgroundColor(Tokens.PRIMARY_DARK)
            .onClick(() => {
              this.handleExport('all');
            })

          if (this.data.lastExport !== null) {
            Column({ space: Tokens.SPACE_XS }) {
              Text('最近一次导出')
                .fontSize(Tokens.FONT_XS)
                .fontWeight(FontWeight.Bold)
                .fontColor(Tokens.TEXT_SECONDARY)
              Text(this.data.lastExport.sandboxPath.length > 0
                ? this.data.lastExport.sandboxPath
                : this.data.lastExport.message)
                .fontSize(Tokens.FONT_XS)
                .fontColor(Tokens.TEXT_TERTIARY)
                .copyOption(CopyOptions.LocalDevice)
              if (this.data.lastExport.publicPath.length > 0) {
                Text(`下载目录：${this.data.lastExport.publicPath}`)
                  .fontSize(Tokens.FONT_XS)
                  .fontColor(Tokens.SUCCESS)
                  .copyOption(CopyOptions.LocalDevice)
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(Tokens.SPACE_MD)
            .backgroundColor(Tokens.BG_SUBTLE)
            .borderRadius(Tokens.RADIUS_MD)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      SectionCard({ title: '统计口径说明' }) {
        Text(AppActions.METHOD_NOTE)
          .fontSize(Tokens.FONT_XS)
          .fontColor(Tokens.TEXT_SECONDARY)
          .lineHeight(20)
      }
    }
    .width('100%')
  }

  @Builder
  exportCard(title: string, desc: string, which: string, accent: string, bg: string) {
    Column({ space: Tokens.SPACE_SM }) {
      Text(title)
        .fontSize(Tokens.FONT_SM)
        .fontWeight(FontWeight.Bold)
        .fontColor(accent)
      Text(desc)
        .fontSize(Tokens.FONT_XS)
        .fontColor(Tokens.TEXT_SECONDARY)
        .layoutWeight(1)
      Button('导出')
        .fontSize(Tokens.FONT_XS)
        .fontColor(accent)
        .backgroundColor(bg)
        .onClick(() => {
          this.handleExport(which);
        })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(Tokens.SPACE_MD)
    .backgroundColor(bg)
    .borderRadius(Tokens.RADIUS_MD)
    .border({ width: 1, color: Tokens.BORDER })
  }

  private handleExport(which: string): void {
    if (this.actions === null) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.actions.exportData(context, which).then(() => {
      this.toast(this.data.toast.length > 0 ? this.data.toast : '导出完成');
    }).catch((err: Error) => {
      Logger.error(`导出异常：${err.message}`);
      this.toast(`导出失败：${err.message}`);
    });
  }

  // ---- 页脚 ----
  @Builder
  footerNote() {
    Column({ space: Tokens.SPACE_XS }) {
      Text('统计口径：实到人数按「同一活动 + 同一参与者」去重后计数；完全重复与多次签到都会保留最早一条作为有效出席。')
        .fontSize(Tokens.FONT_XS)
        .fontColor(Tokens.TEXT_DISABLED)
      Text('本 demo 全程本地处理，数据不上传任何服务器。')
        .fontSize(Tokens.FONT_XS)
        .fontColor(Tokens.TEXT_DISABLED)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: Tokens.SPACE_MD })
  }
}
