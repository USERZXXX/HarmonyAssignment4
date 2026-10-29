import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { Logger } from '../common/Logger';

/**
 * 详情 UIAbility：由主页面经 Want（仅携带标题/正文，不含密码/密钥）拉起，
 * 加载 pages/NoteDetail 展示当前笔记。
 * module.json5 中配置 exported: false 且无 skills，仅供应用内部 startAbility 调用。
 */
export default class NoteDetailAbility extends UIAbility {
  /** 将 Want 中的 params（JSON 字符串，仅含标题/正文）暂存到 AppStorage，供详情页读取 */
  private storeWantParams(want: Want): void {
    let rawParams: string = '';
    const parameters: Record<string, Object> | undefined = want.parameters;
    if (parameters !== undefined) {
      const value: Object | undefined = parameters['params'];
      if (typeof value === 'string') {
        rawParams = value;
      }
    }
    // 仅暂存标题/正文的 JSON 字符串，不含密码/密钥等敏感数据
    AppStorage.setOrCreate('detailParams', rawParams);
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.storeWantParams(want);
    Logger.info('NoteDetailAbility onCreate');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // Ability 已在运行时再次被拉起：刷新详情参数
    this.storeWantParams(want);
    Logger.info('NoteDetailAbility onNewWant');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/NoteDetail', (err) => {
      if (err.code) {
        Logger.error(`NoteDetailAbility load content failed, code=${err.code}`);
        return;
      }
      Logger.info('NoteDetailAbility load content ok');
    });
  }

  onDestroy(): void {
    Logger.info('NoteDetailAbility onDestroy');
  }
}
