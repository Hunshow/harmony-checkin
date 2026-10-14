import { Tokens } from '../common/Tokens';

/**
 * 卡片容器：统一标题、副标题、内边距与阴影
 *
 * 注意：ArkTS 的尾随闭包写法 `SectionCard({...}) { ... }` 要求组件
 * 有且仅有一个 @BuilderParam，因此本组件只保留 content，
 * 不要再往里加第二个 @BuilderParam（如需右侧操作区，改用普通 @Prop 传开关）。
 */
@Component
export struct SectionCard {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  build() {
    Column() {
      if (this.title.length > 0 || this.subtitle.length > 0) {
        Column() {
          if (this.title.length > 0) {
            Text(this.title)
              .fontSize(Tokens.FONT_MD)
              .fontWeight(FontWeight.Bold)
              .fontColor(Tokens.TEXT_PRIMARY)
          }
          if (this.subtitle.length > 0) {
            Text(this.subtitle)
              .fontSize(Tokens.FONT_XS)
              .fontColor(Tokens.TEXT_TERTIARY)
              .margin({ top: 4 })
              .maxLines(2)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .margin({ bottom: Tokens.SPACE_MD })
      }

      this.content()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(Tokens.SPACE_LG)
    .backgroundColor(Tokens.BG_CARD)
    .borderRadius(Tokens.RADIUS_LG)
    .shadow(Tokens.SHADOW)
  }
}
