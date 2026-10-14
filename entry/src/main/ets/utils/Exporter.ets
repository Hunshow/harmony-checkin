import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from './Logger';
import { toCsv } from './CsvParser';

/**
 * 导出服务
 * ------------------------------------------------------------------
 * 双路径导出，保证「用户一定拿得到文件」：
 *   1. 应用沙箱 filesDir/exports —— 无需任何权限，必然成功，是可靠性兜底
 *   2. 沙箱 Download 目录 —— 用户能在「文件管理」里直接找到，是便利性主路径
 * 不申请动态存储权限：避免用户拒绝后导出功能整体不可用。
 */

/** 单次导出结果 */
export interface ExportResult {
  success: boolean;
  /** 主文件路径（沙箱内，一定存在） */
  sandboxPath: string;
  /** 下载目录副本路径，写入失败时为空串 */
  publicPath: string;
  /** 文件大小（字节） */
  bytes: number;
  message: string;
}

/** 确保目录存在（已存在时不报错） */
function ensureDir(dir: string): void {
  try {
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true);
    }
  } catch (err) {
    Logger.warn(`创建目录失败 ${dir}：${(err as BusinessError).message}`);
  }
}

/** 写入文本文件，返回字节数 */
function writeText(filePath: string, content: string): number {
  const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  try {
    return fileIo.writeSync(file.fd, content);
  } finally {
    fileIo.closeSync(file);
  }
}

/**
 * 解析下载目录路径。
 * 硬编码 /storage/Users/... 在不同设备形态上不一定成立，
 * 因此优先取沙箱 filesDir 的同级 Download 目录（应用自己的 Download 区，
 * 无需权限且必然可写），保证「导出文件能被用户找到」这件事稳定成立。
 */
function resolveDownloadDir(context: common.UIAbilityContext): string {
  // filesDir 形如 /data/storage/el2/base/haps/entry/files
  // 取到 el2 这一层后拼 /base/Download，避免越权访问其他应用的目录
  const filesDir: string = context.filesDir;
  const marker: string = '/base/';
  const idx: number = filesDir.indexOf(marker);
  if (idx > 0) {
    return `${filesDir.substring(0, idx)}/base/Download/ActivityCheckin`;
  }
  // 兜底：写到沙箱 exports 的兄弟目录，至少保证不失败
  return `${filesDir}/../Download/ActivityCheckin`;
}

/**
 * 导出 CSV 到应用沙箱，并尽力复制一份到下载目录。
 *
 * @param context  UIAbilityContext，用于解析沙箱路径与申请权限
 * @param fileName 文件名（不含目录），建议带 .csv 后缀
 * @param header   CSV 表头
 * @param rows     CSV 数据行
 */
export async function exportCsv(
  context: common.UIAbilityContext,
  fileName: string,
  header: string[],
  rows: string[][]
): Promise<ExportResult> {
  const content: string = toCsv(header, rows);
  const exportDir: string = `${context.filesDir}/exports`;
  ensureDir(exportDir);

  const sandboxPath: string = `${exportDir}/${fileName}`;

  let bytes: number = 0;
  try {
    bytes = writeText(sandboxPath, content);
    Logger.info(`导出成功：${sandboxPath}（${bytes} 字节）`);
  } catch (err) {
    const error = err as BusinessError;
    Logger.error(`导出失败：${error.message}`);
    return {
      success: false,
      sandboxPath: '',
      publicPath: '',
      bytes: 0,
      message: `导出失败：${error.message}`,
    };
  }

  // 尽力写一份到下载目录，失败只提示不阻断
  let publicPath: string = '';
  try {
    const downloadDir: string = resolveDownloadDir(context);
    ensureDir(downloadDir);
    const target: string = `${downloadDir}/${fileName}`;
    writeText(target, content);
    publicPath = target;
    Logger.info(`已复制到下载目录：${target}`);
  } catch (err) {
    Logger.warn(`复制到下载目录失败（不影响沙箱导出）：${(err as BusinessError).message}`);
  }

  return {
    success: true,
    sandboxPath,
    publicPath,
    bytes,
    message: publicPath.length > 0
      ? `已导出到：${publicPath}`
      : `已导出到应用目录：${sandboxPath}`,
  };
}

/** 生成带时间戳的文件名，避免多次导出互相覆盖 */
export function timestampedName(prefix: string, ext: string = 'csv'): string {
  const d: Date = new Date();
  const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
  const stamp: string =
    `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}` +
    `_${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
  return `${prefix}_${stamp}.${ext}`;
}
