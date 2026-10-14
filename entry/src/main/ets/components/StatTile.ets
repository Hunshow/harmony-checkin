import { Tokens } from '../common/Tokens';

/** 指标卡：大数字 + 标签 + 可选趋势说明 */
@Component
export struct StatTile {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop hint: string = '';
  @Prop accent: string = Tokens.PRIMARY;
  @Prop accentBg: string = Tokens.PRIMARY_SOFT;
  @Prop emphasized: boolean = false;

  build() {
    Column() {
      Row() {
        Text(this.label)
          .fontSize(Tokens.FONT_XS)
          .fontColor(Tokens.TEXT_SECONDARY)
        Blank()
      }
      .width('100%')

      Text(this.value)
        .fontSize(this.emphasized ? Tokens.FONT_XL : Tokens.FONT_LG)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accent)
        .margin({ top: Tokens.SPACE_SM })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(Tokens.FONT_XS)
          .fontColor(Tokens.TEXT_TERTIARY)
          .margin({ top: Tokens.SPACE_XS })
          .maxLines(2)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(Tokens.SPACE_MD)
    .layoutWeight(1)
    .constraintSize({ minWidth: 130 })
    .backgroundColor(this.accentBg)
    .borderRadius(Tokens.RADIUS_MD)
    .border({ width: 1, color: Tokens.BORDER })
  }
}

/** 小标签（用于「完全重复」「多次签到」等状态标记） */
@Component
export struct Pill {
  @Prop text: string = '';
  @Prop color: string = Tokens.TEXT_SECONDARY;
  @Prop bg: string = Tokens.BG_SUBTLE;

  build() {
    Text(this.text)
      .fontSize(Tokens.FONT_XS)
      .fontColor(this.color)
      .backgroundColor(this.bg)
      .padding({ left: Tokens.SPACE_SM, right: Tokens.SPACE_SM, top: 2, bottom: 2 })
      .borderRadius(Tokens.RADIUS_SM)
  }
}

/** 空状态占位 */
@Component
export struct EmptyState {
  @Prop title: string = '暂无数据';
  @Prop description: string = '';

  build() {
    Column() {
      Text('📋')
        .fontSize(40)
        .margin({ bottom: Tokens.SPACE_MD })
      Text(this.title)
        .fontSize(Tokens.FONT_MD)
        .fontWeight(FontWeight.Medium)
        .fontColor(Tokens.TEXT_SECONDARY)
      if (this.description.length > 0) {
        Text(this.description)
          .fontSize(Tokens.FONT_SM)
          .fontColor(Tokens.TEXT_TERTIARY)
          .margin({ top: Tokens.SPACE_SM })
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .padding(Tokens.SPACE_XL)
    .justifyContent(FlexAlign.Center)
  }
}
