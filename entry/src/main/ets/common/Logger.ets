import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 日志封装（基于官方 hilog）。
 *
 * 安全契约（调用方必须遵守）：
 * - 只允许记录事件与结果描述，例如 "save note ok" / "http request failed, code=502"；
 * - 严禁向本封装传入：密码、派生密钥、盐/IV 之外的密钥材料、笔记正文内容、笔记标题内容；
 * - 统一 domain 与格式串，便于静态审计集中核查。
 */
export class Logger {
  private static readonly DOMAIN: number = 0x0000;
  private static readonly TAG: string = 'EncryptedNote';

  static info(message: string): void {
    hilog.info(Logger.DOMAIN, Logger.TAG, '%{public}s', message);
  }

  static error(message: string): void {
    hilog.error(Logger.DOMAIN, Logger.TAG, '%{public}s', message);
  }
}
