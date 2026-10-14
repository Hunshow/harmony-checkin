import { Tokens } from '../common/Tokens';
import { CheckinRecord } from '../model/Types';
import { parseDateTime } from '../utils/CsvParser';
import { toCsv } from '../utils/CsvParser';

/**
 * 签到时间分布图
 * ------------------------------------------------------------------
 * 纯 ArkUI 手绘柱状图，不引入任何图表库：按小时聚合签到条数，
 * 让用户一眼看到「签到高峰」，也顺带暴露集中在同一秒的异常批量导入。
 *
 * 性能要点：聚合结果在 aboutToAppear 中预计算并缓存，
 * 避免在 ForEach 的每个子项里重复遍历全部记录（否则 24 个小时柱 × N 条记录 = 24N 次迭代）。
 */
@Component
export struct TimeDistributionChart {
  @Prop records: CheckinRecord[] = [];
  /** 预计算：每小时 -> 条数 */
  @State hourBuckets: HourBucket[] = [];
  /** 预计算：每活动 -> 条数 */
  @State activityBuckets: ActivityBucket[] = [];
  /** 预计算：最大小时条数，用于算柱高比例 */
  @State hourMax: number = 1;
  /** 预计算：最大活动条数 */
  @State activityMax: number = 1;

  aboutToAppear(): void {
    this.precompute();
  }

  /** records 变化后重新预计算 */
  aboutToUpdate(): void {
    this.precompute();
  }

  private precompute(): void {
    const hours: number[] = new Array<number>(24).fill(0);
    for (const r of this.records) {
      const ts: number = Number.isNaN(r.timestamp) ? parseDateTime(r.checkinTime) : r.timestamp;
      if (Number.isNaN(ts)) {
        continue;
      }
      const h: number = new Date(ts).getHours();
      if (h >= 0 && h < 24) {
        hours[h]++;
      }
    }

    const buckets: HourBucket[] = [];
    let hMax: number = 1;
    for (let i: number = 0; i < 24; i++) {
      buckets.push({ hour: i, count: hours[i] });
      if (hours[i] > hMax) {
        hMax = hours[i];
      }
    }
    this.hourBuckets = buckets;
    this.hourMax = hMax;

    const actMap: Map<string, number> = new Map<string, number>();
    for (const r of this.records) {
      if (r.activityId.trim().length === 0) {
        continue;
      }
      actMap.set(r.activityId, (actMap.get(r.activityId) ?? 0) + 1);
    }
    const acts: ActivityBucket[] = [];
    let aMax: number = 1;
    actMap.forEach((count: number, activityId: string) => {
      acts.push({ activityId, count });
      if (count > aMax) {
        aMax = count;
      }
    });
    acts.sort((a: ActivityBucket, b: ActivityBucket) => a.activityId.localeCompare(b.activityId));
    this.activityBuckets = acts;
    this.activityMax = aMax;
  }

  private barHeight(count: number): number {
    return Math.round((count / this.hourMax) * 90);
  }

  private actBarHeight(count: number): number {
    return Math.round((count / this.activityMax) * 80);
  }

  build() {
    Column() {
      if (this.records.length === 0) {
        Text('暂无数据')
          .fontSize(Tokens.FONT_SM)
          .fontColor(Tokens.TEXT_TERTIARY)
          .padding(Tokens.SPACE_LG)
      } else {
        this.renderCharts()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  renderCharts() {
    Column() {
      Text('按小时签到分布')
        .fontSize(Tokens.FONT_XS)
        .fontColor(Tokens.TEXT_SECONDARY)
        .margin({ bottom: Tokens.SPACE_SM })

      Row() {
        ForEach(this.hourBuckets, (b: HourBucket) => {
          Column() {
            Text(`${b.count}`)
              .fontSize(9)
              .fontColor(Tokens.TEXT_DISABLED)
              .maxLines(1)
            Column()
              .width('100%')
              .height(Math.max(2, this.barHeight(b.count)))
              .backgroundColor(b.count > 0 ? Tokens.PRIMARY : Tokens.BORDER)
              .borderRadius(3)
            Text(`${b.hour}`)
              .fontSize(9)
              .fontColor(Tokens.TEXT_DISABLED)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.End)
        }, (b: HourBucket) => `h${b.hour}`)
      }
      .width('100%')
      .height(140)
      .alignItems(VerticalAlign.Bottom)

      Text('按活动签到条数')
        .fontSize(Tokens.FONT_XS)
        .fontColor(Tokens.TEXT_SECONDARY)
        .margin({ top: Tokens.SPACE_LG, bottom: Tokens.SPACE_SM })

      Row({ space: Tokens.SPACE_MD }) {
        ForEach(this.activityBuckets, (item: ActivityBucket) => {
          Column() {
            Text(`${item.count}`)
              .fontSize(Tokens.FONT_XS)
              .fontColor(Tokens.TEXT_SECONDARY)
            Column()
              .width('100%')
              .height(Math.max(4, this.actBarHeight(item.count)))
              .backgroundColor(Tokens.INFO)
              .borderRadius(4)
            Text(item.activityId)
              .fontSize(10)
              .fontColor(Tokens.TEXT_TERTIARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.End)
        }, (item: ActivityBucket) => item.activityId)
      }
      .width('100%')
      .height(130)
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

interface HourBucket {
  hour: number;
  count: number;
}

interface ActivityBucket {
  activityId: string;
  count: number;
}

/** 把明细导出为 CSV 文本（供「复制到剪贴板」等功能复用） */
export function recordsToCsv(records: CheckinRecord[]): string {
  return toCsv(
    ['活动ID', '参与者ID', '姓名', '部门/分组', '签到时间', '签到方式'],
    records.map((r: CheckinRecord) => [
      r.activityId, r.participantId, r.participantName, r.group, r.checkinTime, r.channel,
    ])
  );
}
