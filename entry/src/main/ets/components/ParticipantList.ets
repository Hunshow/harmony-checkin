import { Tokens } from '../common/Tokens';
import { ParticipantStat } from '../model/Types';

/** 参与者参与情况列表（每人一行，展示跨活动出席次数） */
@Component
export struct ParticipantList {
  @Prop participants: ParticipantStat[] = [];
  @Prop maxHeight: number = 520;

  private readonly COL: number[] = [12, 12, 16, 12, 12, 12, 24];

  @Builder
  head(text: string, index: number) {
    Text(text)
      .fontSize(Tokens.FONT_XS)
      .fontWeight(FontWeight.Bold)
      .fontColor(Tokens.TEXT_SECONDARY)
      .layoutWeight(this.COL[index])
      .padding({ left: Tokens.SPACE_SM, right: Tokens.SPACE_SM })
  }

  @Builder
  cell(text: string, index: number, color: string, weight: FontWeight) {
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
      Row() {
        this.head('参与者ID', 0)
        this.head('姓名', 1)
        this.head('部门/分组', 2)
        this.head('有效签到', 3)
        this.head('原始条数', 4)
        this.head('重复条数', 5)
        this.head('签到时间区间', 6)
      }
      .width('100%')
      .height(40)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(Tokens.BG_SUBTLE)
      .border({ width: { bottom: 1 }, color: Tokens.BORDER })

      List() {
        ForEach(this.participants, (p: ParticipantStat) => {
          ListItem() {
            Row() {
              this.cell(p.participantId, 0, Tokens.TEXT_PRIMARY, FontWeight.Medium)
              this.cell(p.participantName, 1, Tokens.TEXT_PRIMARY, FontWeight.Normal)
              this.cell(p.group, 2, Tokens.TEXT_SECONDARY, FontWeight.Normal)
              this.cell(`${p.validCount}`, 3, Tokens.PRIMARY, FontWeight.Bold)
              this.cell(`${p.rawCount}`, 4, Tokens.TEXT_SECONDARY, FontWeight.Normal)
              this.cell(`${p.dupCount}`, 5, p.dupCount > 0 ? Tokens.WARNING : Tokens.TEXT_DISABLED, FontWeight.Normal)
              this.cell(
                p.firstTime === p.lastTime ? p.firstTime : `${p.firstTime} ~ ${p.lastTime}`,
                6, Tokens.TEXT_SECONDARY, FontWeight.Normal
              )
            }
            .width('100%')
            .height(44)
            .alignItems(VerticalAlign.Center)
            .backgroundColor(p.dupCount > 0 ? Tokens.WARNING_SOFT : Tokens.BG_CARD)
            .border({ width: { bottom: 1 }, color: Tokens.BORDER })
          }
        }, (p: ParticipantStat) => p.participantId)
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
