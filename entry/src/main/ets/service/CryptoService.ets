import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConfig } from '../common/AppConfig';
import { Logger } from '../common/Logger';
import {
  CIPHER_ALG_NAME,
  CryptoEnvelope,
  EncryptedNoteRecord,
  KDF_ALG_NAME,
  NOTE_RECORD_VERSION,
  NoteError,
  NoteErrorCode
} from '../model/NoteModels';

/**
 * 加密服务（官方 cryptoFramework 实现）：
 * - 密钥派生：PBKDF2|SHA256（盐为 CSRNG 生成的 16 字节，迭代 10000 次，派生 32 字节密钥）；
 * - 认证加密：AES-256-GCM（IV 为 CSRNG 生成的 12 字节）；
 * - 安全基线：密码/派生密钥/明文正文绝不写入日志或持久化记录。
 */
export class CryptoService {
  private static readonly textEncoder: util.TextEncoder = new util.TextEncoder();
  private static readonly base64Helper: util.Base64Helper = new util.Base64Helper();

  /**
   * 使用密码对正文进行认证加密。
   * @param password 用户输入的加密密码（仅用于派生密钥，不做任何持久化/日志）
   * @param plainText 笔记正文明文
   * @returns 加密信封（盐/IV/认证标签/密文，均为内存二进制）
   * @throws NoteError 密码为空（EMPTY_PASSWORD）或正文为空（EMPTY_CONTENT）
   */
  static async encryptContent(password: string, plainText: string): Promise<CryptoEnvelope> {
    // 前置校验（页面已校验，此处为服务层防御性兜底）
    if (password.length === 0) {
      throw new NoteError(NoteErrorCode.EMPTY_PASSWORD, '请输入密码');
    }
    if (plainText.length === 0) {
      throw new NoteError(NoteErrorCode.EMPTY_CONTENT, '请输入笔记正文');
    }
    // 1. 密码学安全随机数生成盐与 IV（每次保存均全新生成）
    const salt: Uint8Array = CryptoService.randomBytes(AppConfig.SALT_LEN);
    const iv: Uint8Array = CryptoService.randomBytes(AppConfig.IV_LEN);
    // 2. PBKDF2|SHA256 派生 32 字节密钥
    const derivedKey: Uint8Array =
      await CryptoService.deriveKey(password, salt, AppConfig.PBKDF2_ITERATIONS);
    // 3. AES-256-GCM 加密（GCM 认证加密，附带认证标签）
    const symKey: cryptoFramework.SymKey = await CryptoService.convertToSymKey(derivedKey);
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
    const encryptParams: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: { data: iv },
      aad: { data: new Uint8Array() }, // 不使用附加认证数据
      // 加密时 authTag 字段不参与运算：标签从 doFinal 输出末尾 16 字节提取，此处仅传入占位值
      authTag: { data: new Uint8Array(AppConfig.TAG_LEN) }
    };
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, encryptParams);
    const plainBytes: Uint8Array = CryptoService.textEncoder.encodeInto(plainText);
    const output: cryptoFramework.DataBlob = await cipher.doFinal({ data: plainBytes });
    const outLen: number = output.data.length;
    if (outLen <= AppConfig.TAG_LEN) {
      // 正文非空时密文至少 1 字节 + 标签 16 字节；走到此处说明内部状态异常
      throw new NoteError(NoteErrorCode.EMPTY_CONTENT, '加密输出异常，请重试');
    }
    // 4. doFinal 输出末尾 16 字节为 GCM 认证标签，与密文分离保存
    const cipherBytes: Uint8Array = output.data.slice(0, outLen - AppConfig.TAG_LEN);
    const tag: Uint8Array = output.data.slice(outLen - AppConfig.TAG_LEN);
    return new CryptoEnvelope(salt, iv, tag, cipherBytes);
  }

  /**
   * 使用密码与持久化记录解密正文。
   * 步骤：记录字段校验（version/base64 解码/字节长度）→ 用持久化盐与迭代次数重派生密钥
   * → GcmParamsSpec 传入保存的 authTag → doFinal 解密（认证失败即抛错）→ 严格 UTF-8 解码。
   * @throws NoteError FILE_CORRUPT（记录字段/长度/解码损坏）、
   * WRONG_PASSWORD_OR_CORRUPT（GCM 认证失败：密码错误或密文被篡改）、EMPTY_PASSWORD
   */
  static async decryptContent(password: string, record: EncryptedNoteRecord): Promise<string> {
    if (password.length === 0) {
      throw new NoteError(NoteErrorCode.EMPTY_PASSWORD, '请输入密码');
    }
    if (record.version !== NOTE_RECORD_VERSION) {
      throw new NoteError(NoteErrorCode.FILE_CORRUPT, '笔记数据损坏');
    }
    // base64 解码持久化的盐/IV/认证标签/密文，任何解码失败均视为数据损坏
    let salt: Uint8Array;
    let iv: Uint8Array;
    let tag: Uint8Array;
    let cipherBytes: Uint8Array;
    try {
      salt = CryptoService.base64Helper.decodeSync(record.saltB64);
      iv = CryptoService.base64Helper.decodeSync(record.ivB64);
      tag = CryptoService.base64Helper.decodeSync(record.tagB64);
      cipherBytes = CryptoService.base64Helper.decodeSync(record.cipherB64);
    } catch (error) {
      Logger.error('decode base64 fields of note record failed');
      throw new NoteError(NoteErrorCode.FILE_CORRUPT, '笔记数据损坏');
    }
    // 字节长度校验：盐 16B / IV 12B / 标签 16B，密文非空
    if (salt.length !== AppConfig.SALT_LEN || iv.length !== AppConfig.IV_LEN
      || tag.length !== AppConfig.TAG_LEN || cipherBytes.length === 0) {
      Logger.error('note record field length check failed');
      throw new NoteError(NoteErrorCode.FILE_CORRUPT, '笔记数据损坏');
    }
    // 用持久化的盐与迭代次数重新派生密钥（与加密时一致）
    const derivedKey: Uint8Array =
      await CryptoService.deriveKey(password, salt, record.iterations);
    const symKey: cryptoFramework.SymKey = await CryptoService.convertToSymKey(derivedKey);
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
    // 解密参数：authTag 传入保存的认证标签，doFinal 时做完整性校验
    const decryptParams: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: { data: iv },
      aad: { data: new Uint8Array() },
      authTag: { data: tag }
    };
    let plainBytes: Uint8Array;
    try {
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, decryptParams);
      const output: cryptoFramework.DataBlob = await cipher.doFinal({ data: cipherBytes });
      plainBytes = output.data;
    } catch (error) {
      // GCM 认证失败：密码错误或密文/标签被篡改，二者不可区分，统一提示且绝不输出猜测性明文
      const err = error as BusinessError;
      Logger.error(`gcm decrypt failed, code=${err.code}`);
      throw new NoteError(NoteErrorCode.WRONG_PASSWORD_OR_CORRUPT, '密码错误或数据损坏');
    }
    if (plainBytes.length === 0) {
      throw new NoteError(NoteErrorCode.FILE_CORRUPT, '笔记数据损坏');
    }
    // 严格 UTF-8 解码（fatal）：解密结果非法 UTF-8 时归入数据损坏，不输出乱码
    try {
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8', { fatal: true });
      return decoder.decodeToString(plainBytes);
    } catch (error) {
      Logger.error('decode decrypted bytes as utf-8 failed');
      throw new NoteError(NoteErrorCode.FILE_CORRUPT, '笔记数据损坏');
    }
  }

  /** 生成指定长度的密码学安全随机字节 */
  private static randomBytes(len: number): Uint8Array {
    const rand: cryptoFramework.Random = cryptoFramework.createRandom();
    const blob: cryptoFramework.DataBlob = rand.generateRandomSync(len);
    return blob.data;
  }

  /** PBKDF2|SHA256 密钥派生：password + salt 经 iterations 次迭代派生 keySize 字节密钥 */
  private static async deriveKey(password: string, salt: Uint8Array, iterations: number):
    Promise<Uint8Array> {
    const kdf: cryptoFramework.Kdf = cryptoFramework.createKdf('PBKDF2|SHA256');
    const spec: cryptoFramework.PBKDF2Spec = {
      algName: 'PBKDF2',
      password: password,
      salt: salt,
      iterations: iterations,
      keySize: AppConfig.KEY_SIZE
    };
    const derived: cryptoFramework.DataBlob = await kdf.generateSecret(spec);
    return derived.data;
  }

  /** 将派生密钥字节转换为 AES-256 对称密钥对象 */
  private static async convertToSymKey(derivedKey: Uint8Array): Promise<cryptoFramework.SymKey> {
    const keyGen: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
    return keyGen.convertKey({ data: derivedKey });
  }

  /**
   * 将加密信封组装为可持久化的记录（二进制字段 base64 编码）。
   * 记录中不含明文密码、派生密钥与明文正文。
   */
  static toRecord(envelope: CryptoEnvelope, title: string): EncryptedNoteRecord {
    return {
      version: NOTE_RECORD_VERSION,
      kdfAlg: KDF_ALG_NAME,
      cipherAlg: CIPHER_ALG_NAME,
      iterations: AppConfig.PBKDF2_ITERATIONS,
      saltB64: CryptoService.base64Helper.encodeToStringSync(envelope.salt),
      ivB64: CryptoService.base64Helper.encodeToStringSync(envelope.iv),
      tagB64: CryptoService.base64Helper.encodeToStringSync(envelope.tag),
      cipherB64: CryptoService.base64Helper.encodeToStringSync(envelope.cipher),
      title: title
    };
  }
}
