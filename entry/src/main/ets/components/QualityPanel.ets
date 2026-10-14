import { Tokens } from '../common/Tokens';

/**
 * 数据质量与重复检查面板
 * ------------------------------------------------------------------
 * 刻意只用 @Prop 基础类型（数字/字符串数组）接收数据：
 * - @ObjectLink 要求数据源是 @Observed 类实例，而统计结果是普通对象，用它会崩
 * - 基础类型 @Prop 最稳：父组件整体替换 result 后，这里随之刷新
 */
@Component
export struct QualityPanel {
  @Prop score: number = 0;
  @Prop exactCount: number = 0;
  @Prop repeatCount: number = 0;
  @Prop invalidCount: number = 0;
  @Prop warnings: string[] = [];

  private scoreColor(): string {
    if (this.score >= 90) {
      return Tokens.SUCCESS;
    }
    if (this.score >= 70) {
      return Tokens.WARNING;
    }
    return Tokens.DANGER;
  }

  private scoreLabel(): string {
    if (this.score >= 95) {
      return '优秀，可直接使用';
    }
    if (this.score >= 85) {
      return '良好，建议清理重复';
    }
    if (this.score >= 60) {
      return '一般，存在较多需处理数据';
    }
    return '较差，请先清洗数据';
  }

  build() {
    Column() {
      // 质量分
      Row() {
        Column() {
          Text(`${this.score}`)
            .fontSize(Tokens.FONT_XXL)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.scoreColor())
          Text('数据质量分')
            .fontSize(Tokens.FONT_XS)
            .fontColor(Tokens.TEXT_TERTIARY)
            .margin({ top: Tokens.SPACE_XS })
        }
        .alignItems(HorizontalAlign.Start)
        .width(120)

        Column() {
          Text(this.scoreLabel())
            .fontSize(Tokens.FONT_SM)
            .fontWeight(FontWeight.Medium)
            .fontColor(Tokens.TEXT_PRIMARY)
          Text('扣分项：异常记录 ×10，完全重复 ×3，多次签到 ×1（按占比折算）')
            .fontSize(Tokens.FONT_XS)
            .fontColor(Tokens.TEXT_TERTIARY)
            .margin({ top: Tokens.SPACE_XS })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ bottom: Tokens.SPACE_MD })

      Divider().color(Tokens.BORDER)

      // 三类问题分项
      Row({ space: Tokens.SPACE_MD }) {
        this.issueBox('完全重复', this.exactCount, Tokens.DANGER, Tokens.DANGER_SOFT,
          '同一人 + 同一活动 + 同一时间，通常是重复导入导致')
        this.issueBox('多次签到', this.repeatCount, Tokens.WARNING, Tokens.WARNING_SOFT,
          '同一人在同一活动多次签到，需人工确认是否有效')
        this.issueBox('数据异常', this.invalidCount, '#7C2D12', '#FFF7ED',
          '关键字段缺失或时间无法解析，建议回表修正')
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .margin({ top: Tokens.SPACE_MD })

      // 处置建议
      if (this.warnings.length > 0) {
        Column() {
          ForEach(this.warnings, (w: string) => {
            Row({ space: Tokens.SPACE_SM }) {
              Text('•')
                .fontSize(Tokens.FONT_XS)
                .fontColor(Tokens.TEXT_TERTIARY)
              Text(w)
                .fontSize(Tokens.FONT_XS)
                .fontColor(Tokens.TEXT_SECONDARY)
                .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            .margin({ bottom: Tokens.SPACE_XS })
          }, (w: string) => w)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(Tokens.SPACE_MD)
        .backgroundColor(Tokens.BG_SUBTLE)
        .borderRadius(Tokens.RADIUS_MD)
        .margin({ top: Tokens.SPACE_MD })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  issueBox(label: string, count: number, color: string, bg: string, desc: string) {
    Column() {
      Row() {
        Text(label)
          .fontSize(Tokens.FONT_XS)
          .fontColor(Tokens.TEXT_SECONDARY)
        Blank()
        Text(`${count}`)
          .fontSize(Tokens.FONT_LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(count > 0 ? color : Tokens.TEXT_DISABLED)
      }
      .width('100%')

      Text(desc)
        .fontSize(10)
        .fontColor(Tokens.TEXT_TERTIARY)
        .margin({ top: Tokens.SPACE_XS })
        .maxLines(3)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(Tokens.SPACE_MD)
    .backgroundColor(bg)
    .borderRadius(Tokens.RADIUS_MD)
    .border({ width: 1, color: Tokens.BORDER })
  }
}
