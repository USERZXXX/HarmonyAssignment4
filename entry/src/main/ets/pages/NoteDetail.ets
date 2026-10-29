import { common } from '@kit.AbilityKit';
import { Logger } from '../common/Logger';
import { NoteDetailParams } from '../model/NoteModels';

/**
 * 详情页：展示主页面经 Want 传入的笔记标题与正文（仅标题/正文，无密码/密钥）。
 * Want params 为 JSON 字符串：解析前做 null/类型防御，解析失败渲染兜底文案，不崩溃。
 * "返回"按钮调用 terminateSelf() 结束详情 Ability，系统返回手势同样生效。
 */
@Entry
@ComponentV2
struct NoteDetail {
  @Local detailTitle: string = '';
  @Local detailContent: string = '';
  private hostContext: common.Context | null = null;

  aboutToAppear(): void {
    // 获取宿主 Ability 上下文（返回按钮 terminateSelf 使用）
    const host: common.Context | undefined = this.getUIContext().getHostContext();
    if (host !== undefined) {
      this.hostContext = host;
    }
    // 读取 NoteDetailAbility 暂存的 Want params（JSON 字符串），先做防御性校验再解析
    const rawParams: Object | undefined = AppStorage.get<Object>('detailParams');
    if (typeof rawParams === 'string' && rawParams.length > 0) {
      try {
        const parsed: NoteDetailParams = JSON.parse(rawParams) as NoteDetailParams;
        if (typeof parsed.title === 'string' && typeof parsed.content === 'string') {
          this.detailTitle = parsed.title;
          this.detailContent = parsed.content;
          Logger.info('detail page params parsed ok');
          return;
        }
      } catch (error) {
        Logger.error('detail page params parse failed');
      }
    }
    // params 缺失/类型不符/解析失败：渲染兜底文案
    Logger.info('detail page params missing or invalid, use fallback');
    this.detailTitle = '（未获取到笔记数据）';
    this.detailContent = '未获取到笔记内容，请返回主界面重试';
  }

  /** 返回主界面：结束当前详情 Ability */
  private onBack(): void {
    if (this.hostContext !== null) {
      (this.hostContext as common.UIAbilityContext).terminateSelf();
    }
  }

  build() {
    Column({ space: 12 }) {
      Text('笔记详情')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)

      Text(this.detailTitle)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .width('100%')

      // 正文区域支持滚动查看长文本
      Scroll() {
        Text(this.detailContent)
          .fontSize(16)
          .width('100%')
      }
      .align(Alignment.Top)
      .layoutWeight(1)
      .width('100%')

      Button('返回')
        .width('100%')
        .onClick(() => {
          this.onBack();
        })
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }
}
