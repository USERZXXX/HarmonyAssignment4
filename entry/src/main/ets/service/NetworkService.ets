import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConfig } from '../common/AppConfig';
import { Logger } from '../common/Logger';
import { NoteError, NoteErrorCode } from '../model/NoteModels';

/**
 * 网络服务：HTTPS GET 获取示例文本。
 * 安全基线：
 * - 仅向固定示例接口发起 GET 请求，请求中不携带任何用户数据（笔记/密码等绝不上传）；
 * - 设置连接/读取超时，超时或失败给出友好提示；
 * - 无论成败在 finally 中 destroy() 释放请求资源。
 */
export class NetworkService {
  /**
   * 获取网络示例文本。
   * @returns 响应体字符串（仅当 HTTP 200 时）
   * @throws NoteError NETWORK_FAIL（非 200 状态码 / 无网络 / 超时 / 响应格式异常）
   */
  static async fetchSampleText(): Promise<string> {
    // 每次请求新建 HttpRequest 实例，使用后在 finally 中销毁
    const httpRequest: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await httpRequest.request(AppConfig.SAMPLE_URL, {
        // GET 请求本身不携带用户数据
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: AppConfig.HTTP_TIMEOUT_MS,
        readTimeout: AppConfig.HTTP_TIMEOUT_MS,
        usingCache: false
      });
      // 仅 200 视为成功，非 200 提示失败及状态码
      if (response.responseCode !== 200) {
        Logger.error(`http request failed, status=${response.responseCode}`);
        throw new NoteError(NoteErrorCode.NETWORK_FAIL,
          `网络请求失败（状态码 ${response.responseCode}）`);
      }
      // 校验响应体确为字符串（expectDataType STRING 的正常结果）
      const body: string | Object | ArrayBuffer = response.result;
      if (typeof body !== 'string') {
        Logger.error('http response body is not a string');
        throw new NoteError(NoteErrorCode.NETWORK_FAIL, '网络响应格式异常');
      }
      Logger.info('http request ok');
      return body;
    } catch (error) {
      // 已分类的业务异常原样上抛，仅对底层异常（无网络/超时/DNS 等）做统一映射
      if (error instanceof NoteError) {
        throw error;
      }
      const err = error as BusinessError;
      Logger.error(`http request error, code=${err.code}`);
      throw new NoteError(NoteErrorCode.NETWORK_FAIL, '网络请求失败，请检查网络后重试');
    } finally {
      // 无论成败释放请求资源，避免内存泄漏
      httpRequest.destroy();
    }
  }
}
