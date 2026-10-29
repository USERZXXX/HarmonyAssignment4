/**
 * 全局配置常量（集中管理，避免硬编码散落各处）。
 * 供 NetworkService / FileService / CryptoService 统一引用。
 */
export class AppConfig {
  /** 网络示例接口地址（HTTPS GET，请求不携带任何用户数据） */
  static readonly SAMPLE_URL: string = 'https://httpbin.org/get';
  /** 笔记沙箱文件名（固定文件名，用户输入绝不参与路径拼接） */
  static readonly NOTE_FILE_NAME: string = 'encrypted_note.json';
  /** PBKDF2 密钥派生迭代次数（业界常规安全值） */
  static readonly PBKDF2_ITERATIONS: number = 10000;
  /** 盐长度（字节，CSRNG 生成） */
  static readonly SALT_LEN: number = 16;
  /** AES-GCM 初始向量长度（字节，CSRNG 生成） */
  static readonly IV_LEN: number = 12;
  /** GCM 认证标签长度（字节） */
  static readonly TAG_LEN: number = 16;
  /** 派生密钥长度（字节，对应 AES-256） */
  static readonly KEY_SIZE: number = 32;
  /** HTTP 连接/读取超时（毫秒） */
  static readonly HTTP_TIMEOUT_MS: number = 10000;
}
