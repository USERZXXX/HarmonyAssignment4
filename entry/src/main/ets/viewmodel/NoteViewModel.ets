import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/Logger';
import {
  CryptoEnvelope,
  EncryptedNoteRecord,
  FetchSampleOutcome,
  LoadNoteOutcome,
  NoteDetailParams,
  NoteDraft,
  NoteError,
  OpResult
} from '../model/NoteModels';
import { CryptoService } from '../service/CryptoService';
import { FileService } from '../service/FileService';
import { NetworkService } from '../service/NetworkService';

/**
 * 视图模型：主页面业务编排（校验 → 加密服务/文件服务 → 操作结果）。
 * 页面（@ComponentV2 + @Local）持有全部 UI 状态；本类为普通类，
 * 方法返回 OpResult，由页面回填到 @Local 字段。
 * 安全基线：所有日志仅记录事件与结果，不记录密码、密钥、笔记内容。
 */
export class NoteViewModel {
  /**
   * 加密保存笔记：校验非空 → 正文加密 → 记录写入沙箱固定文件。
   * @returns 操作结果（成功/失败 + 面向用户的中文提示）
   */
  async saveNote(title: string, content: string, password: string, context: common.Context):
    Promise<OpResult> {
    // 入参校验：标题/正文/密码均不允许为空
    if (title.length === 0) {
      return { success: false, message: '请输入笔记标题' };
    }
    if (content.length === 0) {
      return { success: false, message: '请输入笔记正文' };
    }
    if (password.length === 0) {
      return { success: false, message: '请输入密码' };
    }
    try {
      // 1. 密码派生密钥并对正文做 AES-256-GCM 认证加密
      const envelope: CryptoEnvelope = await CryptoService.encryptContent(password, content);
      // 2. 组装持久化记录（不含明文密码/派生密钥/明文正文）
      const record: EncryptedNoteRecord = CryptoService.toRecord(envelope, title);
      // 3. 覆盖写入沙箱固定文件
      await FileService.saveRecord(context, record);
      Logger.info('save note ok');
      return { success: true, message: '加密保存成功' };
    } catch (error) {
      if (error instanceof NoteError) {
        Logger.error(`save note failed, code=${error.code}`);
        return { success: false, message: error.message };
      }
      Logger.error('save note failed, unexpected error');
      return { success: false, message: '加密保存失败，请重试' };
    }
  }

  /**
   * 读取并解密笔记：密码非空校验 → 读取沙箱记录（无文件 → "暂无保存的笔记"）
   * → 解密正文 → 返回操作结果与笔记草稿（成功时供页面回填标题/正文输入框）。
   * 重启后沙箱文件天然持久存在，无需额外处理。
   */
  async loadNote(password: string, context: common.Context): Promise<LoadNoteOutcome> {
    if (password.length === 0) {
      return { result: { success: false, message: '请输入密码' }, draft: null };
    }
    try {
      // 1. 读取固定沙箱文件（文件不存在返回 null）
      const record: EncryptedNoteRecord | null = await FileService.readRecord(context);
      if (record === null) {
        Logger.info('load note: no saved note yet');
        return { result: { success: false, message: '暂无保存的笔记' }, draft: null };
      }
      // 2. 用当前输入的密码解密正文（密码错误/数据损坏在服务内分类抛错）
      const content: string = await CryptoService.decryptContent(password, record);
      Logger.info('load note ok');
      const draft: NoteDraft = { title: record.title, content: content };
      return { result: { success: true, message: '读取并解密成功' }, draft: draft };
    } catch (error) {
      if (error instanceof NoteError) {
        Logger.error(`load note failed, code=${error.code}`);
        return { result: { success: false, message: error.message }, draft: null };
      }
      Logger.error('load note failed, unexpected error');
      return { result: { success: false, message: '读取解密失败，请重试' }, draft: null };
    }
  }

  /**
   * 获取网络示例文本：HTTPS GET 固定示例接口（请求不携带任何用户数据），
   * 成功返回示例文本，失败（无网络/超时/非 200）返回带友好提示的错误结果。
   */
  async fetchSample(): Promise<FetchSampleOutcome> {
    try {
      const text: string = await NetworkService.fetchSampleText();
      Logger.info('fetch sample ok');
      return { result: { success: true, message: '获取网络示例成功' }, sampleText: text };
    } catch (error) {
      if (error instanceof NoteError) {
        Logger.error(`fetch sample failed, code=${error.code}`);
        return { result: { success: false, message: error.message }, sampleText: '' };
      }
      Logger.error('fetch sample failed, unexpected error');
      return { result: { success: false, message: '获取网络示例失败，请重试' }, sampleText: '' };
    }
  }

  /**
   * 打开详情 Ability：校验当前有内容 → 构造 Want（params 仅含标题/正文，
   * 绝不含密码/密钥）→ startAbility 拉起 NoteDetailAbility。
   */
  async openDetail(context: common.UIAbilityContext, title: string, content: string):
    Promise<OpResult> {
    if (title.length === 0 || content.length === 0) {
      return { success: false, message: '请先输入笔记标题与正文' };
    }
    try {
      // 仅序列化标题与正文，敏感字段（密码/密钥）绝不进入 Want
      const detail: NoteDetailParams = { title: title, content: content };
      const want: Want = {
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'NoteDetailAbility',
        parameters: { 'params': JSON.stringify(detail) }
      };
      await context.startAbility(want);
      Logger.info('open detail ability ok');
      return { success: true, message: '已打开详情页' };
    } catch (error) {
      const err = error as BusinessError;
      Logger.error(`open detail ability failed, code=${err.code}`);
      return { success: false, message: '打开详情页失败' };
    }
  }
}
