import { Tokens } from '../common/Tokens';
import { ActivityStat } from '../model/Types';

/**
 * 活动统计行
 * ------------------------------------------------------------------
 * 用进度条可视化出席率，配文字说明「实到/应到」，
 * 未提供名册时明确提示不可计算，而不是显示 0%。
 */
@Component
export struct ActivityRow {
  @Prop stat: ActivityStat = {
    activityId: '',
    expectedCount: 0,
    actualCount: 0,
    rawCount: 0,
    dupCount: 0,
    invalidCount: 0,
    attendanceRate: -1,
  };

  private rateColor(): string {
    if (this.stat.attendanceRate < 0) {
      return Tokens.TEXT_TERTIARY;
    }
    if (this.stat.attendanceRate >= 0.85) {
      return Tokens.SUCCESS;
    }
    if (this.stat.attendanceRate >= 0.6) {
      return Tokens.WARNING;
    }
    return Tokens.DANGER;
  }

  private rateText(): string {
    if (this.stat.attendanceRate < 0) {
      return '未提供名册';
    }
    return `${(this.stat.attendanceRate * 100).toFixed(1)}%`;
  }

  build() {
    Column() {
      Row() {
        Text(this.stat.activityId)
          .fontSize(Tokens.FONT_SM)
          .fontWeight(FontWeight.Medium)
          .fontColor(Tokens.TEXT_PRIMARY)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.rateText())
          .fontSize(Tokens.FONT_SM)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.rateColor())
      }
      .width('100%')

      // 出席率进度条
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(8)
          .backgroundColor(Tokens.BG_SUBTLE)
          .borderRadius(4)
        if (this.stat.attendanceRate >= 0) {
          Row()
            .width(`${Math.max(2, Math.round(this.stat.attendanceRate * 100))}%`)
            .height(8)
            .backgroundColor(this.rateColor())
            .borderRadius(4)
        }
      }
      .width('100%')
      .margin({ top: Tokens.SPACE_SM, bottom: Tokens.SPACE_SM })

      Row({ space: Tokens.SPACE_MD }) {
        Text(`实到 ${this.stat.actualCount} 人`)
          .fontSize(Tokens.FONT_XS)
          .fontColor(Tokens.TEXT_SECONDARY)
        if (this.stat.expectedCount > 0) {
          Text(`应到 ${this.stat.expectedCount} 人`)
            .fontSize(Tokens.FONT_XS)
            .fontColor(Tokens.TEXT_SECONDARY)
        }
        Text(`签到 ${this.stat.rawCount} 条`)
          .fontSize(Tokens.FONT_XS)
          .fontColor(Tokens.TEXT_SECONDARY)
        if (this.stat.dupCount > 0) {
          Text(`重复 ${this.stat.dupCount}`)
            .fontSize(Tokens.FONT_XS)
            .fontColor(Tokens.WARNING)
        }
        if (this.stat.invalidCount > 0) {
          Text(`异常 ${this.stat.invalidCount}`)
            .fontSize(Tokens.FONT_XS)
            .fontColor(Tokens.DANGER)
        }
        Blank()
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(Tokens.SPACE_MD)
    .backgroundColor(Tokens.BG_SUBTLE)
    .borderRadius(Tokens.RADIUS_MD)
    .border({ width: 1, color: Tokens.BORDER })
  }
}
