import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConfig } from '../common/AppConfig';
import { Logger } from '../common/Logger';
import {
  buildNoteRecord,
  EncryptedNoteRecord,
  NoteError,
  NoteErrorCode,
  RawNoteRecord
} from '../model/NoteModels';

/**
 * 文件服务：将加密笔记记录以固定文件名持久化到应用沙箱 filesDir。
 * 安全基线：
 * - 文件路径 = context.filesDir + 固定文件名，用户输入绝不参与路径拼接；
 * - 写入内容为 JSON 记录（仅含加密元数据与密文），不含明文密码/派生密钥/明文正文；
 * - 所有打开的文件描述符在 finally 中关闭，保证资源释放。
 */
export class FileService {
  /** 读取文件大小上限（字节）：防止损坏/恶意构造的超大文件导致内存耗尽；正常笔记记录远小于该值 */
  private static readonly MAX_FILE_SIZE: number = 16 * 1024 * 1024;

  /** 笔记文件的沙箱绝对路径（固定文件名） */
  static getNoteFilePath(context: common.Context): string {
    return context.filesDir + '/' + AppConfig.NOTE_FILE_NAME;
  }

  /**
   * 将记录序列化为 JSON 并覆盖写入固定沙箱文件。
   * @throws NoteError 任一 IO 环节失败时抛出（message 为用户提示，原始错误码仅记日志）
   */
  static async saveRecord(context: common.Context, record: EncryptedNoteRecord): Promise<void> {
    const filePath: string = FileService.getNoteFilePath(context);
    // 记录中不含敏感明文，可安全序列化
    const jsonText: string = JSON.stringify(record);
    let fd: number = -1;
    try {
      const file: fileIo.File = fileIo.openSync(filePath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fd = file.fd;
      fileIo.writeSync(fd, jsonText);
    } catch (error) {
      const err = error as BusinessError;
      Logger.error(`write note file failed, code=${err.code}`);
      throw new NoteError(NoteErrorCode.FILE_CORRUPT, '保存笔记文件失败');
    } finally {
      // 无论成败，确保已打开的文件描述符被关闭
      if (fd >= 0) {
        fileIo.closeSync(fd);
      }
    }
    Logger.info('write note file ok');
  }

  /**
   * 从固定沙箱文件读取并解析加密笔记记录。
   * @returns 文件不存在时返回 null（UI 提示"暂无保存的笔记"）；
   * 文件存在但 JSON 解析/字段校验失败时抛 NoteError(FILE_CORRUPT)。
   */
  static async readRecord(context: common.Context): Promise<EncryptedNoteRecord | null> {
    const filePath: string = FileService.getNoteFilePath(context);
    // 文件不存在：返回 null，由上层给出"暂无保存的笔记"提示
    if (!fileIo.accessSync(filePath)) {
      Logger.info('note file not found');
      return null;
    }
    let fd: number = -1;
    try {
      const file: fileIo.File = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      fd = file.fd;
      // 先取文件大小用于分配定长缓冲区（超上限视为损坏，防超大文件耗尽内存）
      const stat: fileIo.Stat = fileIo.statSync(fd);
      if (stat.size <= 0 || stat.size > FileService.MAX_FILE_SIZE) {
        Logger.error('note file size out of range');
        throw new NoteError(NoteErrorCode.FILE_CORRUPT, '笔记数据损坏');
      }
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      const bytesRead: number = fileIo.readSync(fd, buffer);
      if (bytesRead === 0) {
        Logger.error('note file is empty');
        throw new NoteError(NoteErrorCode.FILE_CORRUPT, '笔记数据损坏');
      }
      // 按 JSON 文本解析（文件内容为记录 JSON，不含敏感明文）
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
      const jsonText: string = decoder.decodeToString(new Uint8Array(buffer, 0, bytesRead));
      let raw: RawNoteRecord;
      try {
        raw = JSON.parse(jsonText) as RawNoteRecord;
      } catch (error) {
        Logger.error('parse note file json failed');
        throw new NoteError(NoteErrorCode.FILE_CORRUPT, '笔记数据损坏');
      }
      // 字段结构校验（version/算法标识/字段类型），不通过视为数据损坏
      const record: EncryptedNoteRecord | null = buildNoteRecord(raw);
      if (record === null) {
        Logger.error('note record validation failed');
        throw new NoteError(NoteErrorCode.FILE_CORRUPT, '笔记数据损坏');
      }
      Logger.info('read note file ok');
      return record;
    } catch (error) {
      // 已分类的业务异常原样上抛，仅对未预期异常做统一包装
      if (error instanceof NoteError) {
        throw error;
      }
      const err = error as BusinessError;
      Logger.error(`read note file failed, code=${err.code}`);
      throw new NoteError(NoteErrorCode.FILE_CORRUPT, '笔记数据损坏');
    } finally {
      // 无论成败，确保已打开的文件描述符被关闭
      if (fd >= 0) {
        fileIo.closeSync(fd);
      }
    }
  }
}
