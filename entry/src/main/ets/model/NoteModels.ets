/**
 * 数据模型与业务错误定义。
 * 持久化记录（EncryptedNoteRecord）中绝不包含：明文密码、派生密钥、明文正文。
 */

/** 记录版本号（前向兼容标识，≠1 视为损坏） */
export const NOTE_RECORD_VERSION: number = 1;
/** 密钥派生算法标识（审计与解密前置校验用） */
export const KDF_ALG_NAME: string = 'PBKDF2-SHA256';
/** 认证加密算法标识 */
export const CIPHER_ALG_NAME: string = 'AES256-GCM';
/** PBKDF2 迭代次数上限（防篡改文件构造超大迭代次数导致长时间计算） */
export const MAX_PBKDF2_ITERATIONS: number = 1000000;

/** 业务错误码（供 UI 分类给出可区分的友好提示） */
export enum NoteErrorCode {
  /** 密码为空 */
  EMPTY_PASSWORD = 'EMPTY_PASSWORD',
  /** 笔记正文为空（保存前校验） */
  EMPTY_CONTENT = 'EMPTY_CONTENT',
  /** 文件缺失以外的记录损坏（JSON/字段/base64/长度校验失败） */
  FILE_CORRUPT = 'FILE_CORRUPT',
  /** GCM 认证失败：密码错误或密文被篡改（不可区分，统一提示） */
  WRONG_PASSWORD_OR_CORRUPT = 'WRONG_PASSWORD_OR_CORRUPT',
  /** 网络请求失败（无网络/超时/DNS 等） */
  NETWORK_FAIL = 'NETWORK_FAIL',
  /** 未找到保存的笔记（文件不存在） */
  NOT_FOUND = 'NOT_FOUND'
}

/** 业务异常：携带分类错误码，便于上层映射为用户提示（继承 Error 以满足 ArkTS throw 类型限制） */
export class NoteError extends Error {
  readonly code: NoteErrorCode;

  constructor(code: NoteErrorCode, message: string) {
    super(message);
    this.code = code;
  }
}

/**
 * JSON.parse 的目标类型（未校验的原始结构）。
 * 字段在运行时可能缺失/类型不符，必须先经 buildNoteRecord 校验后才能使用。
 */
export interface RawNoteRecord {
  version: number;
  kdfAlg: string;
  cipherAlg: string;
  iterations: number;
  saltB64: string;
  ivB64: string;
  tagB64: string;
  cipherB64: string;
  title: string;
}

/** 已校验的持久化记录（结构上保证字段齐全且取值合法） */
export interface EncryptedNoteRecord {
  version: number;
  kdfAlg: string;
  cipherAlg: string;
  iterations: number;
  /** base64(salt)，解码后须为 AppConfig.SALT_LEN 字节 */
  saltB64: string;
  /** base64(iv)，解码后须为 AppConfig.IV_LEN 字节 */
  ivB64: string;
  /** base64(GCM authTag)，解码后须为 AppConfig.TAG_LEN 字节 */
  tagB64: string;
  /** base64(密文，不含 authTag)，非空 */
  cipherB64: string;
  /** 明文标题（需求仅要求正文加密；标题不含敏感信息时允许明文保存） */
  title: string;
}

/** 加密结果（内存二进制，仅在 service 层内部流转，不持久化、不落日志） */
export class CryptoEnvelope {
  readonly salt: Uint8Array;
  readonly iv: Uint8Array;
  readonly tag: Uint8Array;
  readonly cipher: Uint8Array;

  constructor(salt: Uint8Array, iv: Uint8Array, tag: Uint8Array, cipher: Uint8Array) {
    this.salt = salt;
    this.iv = iv;
    this.tag = tag;
    this.cipher = cipher;
  }
}

/** 操作结果（UI 反馈载体；message 为面向用户的中文提示，不含密钥/密文等技术细节） */
export interface OpResult {
  success: boolean;
  message: string;
}

/** 笔记草稿（运行时内存中的当前笔记明文：标题 + 正文；不持久化） */
export interface NoteDraft {
  title: string;
  content: string;
}

/** 读取并解密操作的返回：操作结果 + 解密成功时的笔记草稿（失败时为 null） */
export interface LoadNoteOutcome {
  result: OpResult;
  draft: NoteDraft | null;
}

/** 获取网络示例操作的返回：操作结果 + 成功时的示例文本（失败时为空字符串） */
export interface FetchSampleOutcome {
  result: OpResult;
  sampleText: string;
}

/** 详情页 Want params 的 JSON 结构（仅标题与正文，绝不含密码/密钥） */
export interface NoteDetailParams {
  title: string;
  content: string;
}

/**
 * 记录字段校验：将未校验的原始 JSON 对象转换为严格记录。
 * 校验内容：version 固定、算法标识匹配、iterations 为正整数、
 * 各 base64 字段为非空字符串、title 为字符串。
 * （base64 解码与字节长度校验由 CryptoService 负责。）
 * 任何一项不满足即返回 null（调用方归类为 FILE_CORRUPT）。
 */
export function buildNoteRecord(raw: RawNoteRecord | null): EncryptedNoteRecord | null {
  if (raw === null || typeof raw !== 'object') {
    return null;
  }
  if (typeof raw.version !== 'number' || raw.version !== NOTE_RECORD_VERSION) {
    return null;
  }
  if (raw.kdfAlg !== KDF_ALG_NAME || raw.cipherAlg !== CIPHER_ALG_NAME) {
    return null;
  }
  if (typeof raw.iterations !== 'number' || !Number.isInteger(raw.iterations)
    || raw.iterations <= 0 || raw.iterations > MAX_PBKDF2_ITERATIONS) {
    return null;
  }
  if (typeof raw.saltB64 !== 'string' || raw.saltB64.length === 0) {
    return null;
  }
  if (typeof raw.ivB64 !== 'string' || raw.ivB64.length === 0) {
    return null;
  }
  if (typeof raw.tagB64 !== 'string' || raw.tagB64.length === 0) {
    return null;
  }
  if (typeof raw.cipherB64 !== 'string' || raw.cipherB64.length === 0) {
    return null;
  }
  if (typeof raw.title !== 'string') {
    return null;
  }
  const record: EncryptedNoteRecord = {
    version: raw.version,
    kdfAlg: raw.kdfAlg,
    cipherAlg: raw.cipherAlg,
    iterations: raw.iterations,
    saltB64: raw.saltB64,
    ivB64: raw.ivB64,
    tagB64: raw.tagB64,
    cipherB64: raw.cipherB64,
    title: raw.title
  };
  return record;
}
