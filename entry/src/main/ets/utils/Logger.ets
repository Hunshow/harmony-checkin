/**
 * 结构化日志工具
 * ------------------------------------------------------------------
 * ArkTS 严格模式不允许 `const Logger = {...}` 这种无类型的对象字面量，
 * 必须用 class 承载方法。
 */

const TAG: string = 'ActivityCheckin';
const DEBUG_ENABLED: boolean = true;

export class Logger {
  static debug(message: string): void {
    if (DEBUG_ENABLED) {
      console.debug(`[${TAG}] ${message}`);
    }
  }

  static info(message: string): void {
    console.info(`[${TAG}] ${message}`);
  }

  static warn(message: string): void {
    console.warn(`[${TAG}] ${message}`);
  }

  static error(message: string): void {
    console.error(`[${TAG}] ${message}`);
  }

  /** 带耗时的操作日志，便于定位导入大文件时的性能瓶颈 */
  static time<T>(label: string, fn: () => T): T {
    const start: number = Date.now();
    const result: T = fn();
    Logger.debug(`${label} 耗时 ${Date.now() - start}ms`);
    return result;
  }
}
