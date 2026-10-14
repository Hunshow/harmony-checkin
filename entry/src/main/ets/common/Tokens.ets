/**
 * 设计令牌（Design Tokens）
 * ------------------------------------------------------------------
 * 全应用统一的颜色 / 间距 / 圆角 / 字号，UI 里禁止硬编码色值。
 * 色板遵循「浅色 + 中低饱和蓝绿」的可访问性取向，正文对比度 >= 4.5:1。
 */

export class Tokens {
  // ---- 主色 ----
  static readonly PRIMARY: string = '#2563EB';
  static readonly PRIMARY_DARK: string = '#1D4ED8';
  static readonly PRIMARY_LIGHT: string = '#DBEAFE';
  static readonly PRIMARY_SOFT: string = '#EFF6FF';

  // ---- 语义色 ----
  static readonly SUCCESS: string = '#059669';
  static readonly SUCCESS_LIGHT: string = '#D1FAE5';
  static readonly WARNING: string = '#D97706';
  static readonly WARNING_LIGHT: string = '#FEF3C7';
  static readonly WARNING_SOFT: string = '#FFFBEB';
  static readonly DANGER: string = '#DC2626';
  static readonly DANGER_LIGHT: string = '#FEE2E2';
  static readonly DANGER_SOFT: string = '#FEF2F2';
  static readonly INFO: string = '#0891B2';
  static readonly INFO_LIGHT: string = '#CFFAFE';

  // ---- 中性色 ----
  static readonly TEXT_PRIMARY: string = '#111827';
  static readonly TEXT_SECONDARY: string = '#4B5563';
  static readonly TEXT_TERTIARY: string = '#6B7280';
  static readonly TEXT_DISABLED: string = '#9CA3AF';
  static readonly TEXT_ON_PRIMARY: string = '#FFFFFF';

  static readonly BG_PAGE: string = '#F3F4F6';
  static readonly BG_CARD: string = '#FFFFFF';
  static readonly BG_SUBTLE: string = '#F9FAFB';
  static readonly BG_HOVER: string = '#F3F4F6';

  static readonly BORDER: string = '#E5E7EB';
  static readonly BORDER_STRONG: string = '#D1D5DB';

  // ---- 间距 ----
  static readonly SPACE_XS: number = 4;
  static readonly SPACE_SM: number = 8;
  static readonly SPACE_MD: number = 16;
  static readonly SPACE_LG: number = 24;
  static readonly SPACE_XL: number = 32;

  // ---- 圆角 ----
  static readonly RADIUS_SM: number = 6;
  static readonly RADIUS_MD: number = 10;
  static readonly RADIUS_LG: number = 16;

  // ---- 字号 ----
  static readonly FONT_XS: number = 12;
  static readonly FONT_SM: number = 14;
  static readonly FONT_MD: number = 16;
  static readonly FONT_LG: number = 20;
  static readonly FONT_XL: number = 28;
  static readonly FONT_XXL: number = 36;

  // ---- 布局 ----
  /** 鸿蒙 PC 端内容最大宽度，避免超宽屏上行长过长 */
  static readonly CONTENT_MAX_WIDTH: number = 1280;
  /** 断点：窗口宽度小于此值时按「窄屏（手机）」布局 */
  static readonly BREAKPOINT_NARROW: number = 840;
  /** 卡片阴影 */
  static readonly SHADOW: ShadowOptions = {
    radius: 12,
    color: 'rgba(17, 24, 39, 0.06)',
    offsetX: 0,
    offsetY: 2,
  };
}
