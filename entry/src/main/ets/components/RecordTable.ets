import { Tokens } from '../common/Tokens';
import { AnalyzedRecord, DupKind } from '../model/Types';
import { Pill } from './StatTile';

/**
 * 签到明细表
 * ------------------------------------------------------------------
 * PC 场景用「横向表格」呈现，重复记录用整行底色 + 标签双重标识，
 * 保证色盲用户也能通过文字标签识别。
 */
@Component
export struct RecordTable {
  @Prop records: AnalyzedRecord[] = [];
  /** 表头吸顶高度（外层 List 里用 Sticky 时传入） */
  @Prop maxHeight: number = 520;

  private kindMeta(kind: DupKind): [string, string, string] {
    // [标签文本, 文字色, 背景色]
    if (kind === DupKind.Exact) {
      return ['完全重复', Tokens.DANGER, Tokens.DANGER_LIGHT];
    }
    if (kind === DupKind.Repeat) {
      return ['多次签到', Tokens.WARNING, Tokens.WARNING_LIGHT];
    }
    if (kind === DupKind.Invalid) {
      return ['数据异常', '#7C2D12', Tokens.WARNING_LIGHT];
    }
    return ['正常', Tokens.SUCCESS, Tokens.SUCCESS_LIGHT];
  }

  private rowBg(kind: DupKind): string {
    if (kind === DupKind.Exact) {
      return Tokens.DANGER_SOFT;
    }
    if (kind === DupKind.Repeat) {
      return Tokens.WARNING_SOFT;
    }
    if (kind === DupKind.Invalid) {
      return '#FFFBEB';
    }
    return Tokens.BG_CARD;
  }

  /** 列宽比例：行号 / 活动 / 参与者 / 姓名 / 部门 / 时间 / 方式 / 状态 */
  private readonly COL: number[] = [8, 18, 12, 12, 14, 22, 14, 16];

  @Builder
  headerCell(text: string, index: number) {
    Text(text)
      .fontSize(Tokens.FONT_XS)
      .fontWeight(FontWeight.Bold)
      .fontColor(Tokens.TEXT_SECONDARY)
      .layoutWeight(this.COL[index])
      .padding({ left: Tokens.SPACE_SM, right: Tokens.SPACE_SM })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  bodyCell(text: string, index: number, color: string, weight: FontWeight) {
    Text(text.length > 0 ? text : '—')
      .fontSize(Tokens.FONT_XS)
      .fontColor(color)
      .fontWeight(weight)
      .layoutWeight(this.COL[index])
      .padding({ left: Tokens.SPACE_SM, right: Tokens.SPACE_SM })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  build() {
    Column() {
      // 表头
      Row() {
        this.headerCell('行号', 0)
        this.headerCell('活动ID', 1)
        this.headerCell('参与者ID', 2)
        this.headerCell('姓名', 3)
        this.headerCell('部门/分组', 4)
        this.headerCell('签到时间', 5)
        this.headerCell('签到方式', 6)
        this.headerCell('状态', 7)
      }
      .width('100%')
      .height(40)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(Tokens.BG_SUBTLE)
      .border({ width: { bottom: 1 }, color: Tokens.BORDER })

      // 数据行
      List() {
        ForEach(this.records, (item: AnalyzedRecord) => {
          ListItem() {
            Row() {
              this.bodyCell(`${item.record.lineNo}`, 0, Tokens.TEXT_DISABLED, FontWeight.Normal)
              this.bodyCell(item.record.activityId, 1, Tokens.TEXT_PRIMARY, FontWeight.Normal)
              this.bodyCell(item.record.participantId, 2, Tokens.TEXT_PRIMARY, FontWeight.Medium)
              this.bodyCell(item.record.participantName, 3, Tokens.TEXT_PRIMARY, FontWeight.Normal)
              this.bodyCell(item.record.group, 4, Tokens.TEXT_SECONDARY, FontWeight.Normal)
              this.bodyCell(item.record.checkinTime, 5, Tokens.TEXT_SECONDARY, FontWeight.Normal)
              this.bodyCell(item.record.channel, 6, Tokens.TEXT_SECONDARY, FontWeight.Normal)
              Row() {
                Pill({
                  text: this.kindMeta(item.kind)[0],
                  color: this.kindMeta(item.kind)[1],
                  bg: this.kindMeta(item.kind)[2],
                })
                if (item.isPrimary && item.kind !== DupKind.Invalid) {
                  Pill({ text: '计入实到', color: Tokens.PRIMARY, bg: Tokens.PRIMARY_LIGHT })
                    .margin({ left: Tokens.SPACE_XS })
                }
              }
              .layoutWeight(this.COL[7])
              .padding({ left: Tokens.SPACE_SM, right: Tokens.SPACE_SM })
            }
            .width('100%')
            .height(44)
            .alignItems(VerticalAlign.Center)
            .backgroundColor(this.rowBg(item.kind))
            .border({ width: { bottom: 1 }, color: Tokens.BORDER })
          }
        }, (item: AnalyzedRecord) => `${item.record.key}-${item.kind}`)
      }
      .width('100%')
      .height(this.maxHeight)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .borderRadius(Tokens.RADIUS_MD)
    .border({ width: 1, color: Tokens.BORDER })
    .clip(true)
  }
}
