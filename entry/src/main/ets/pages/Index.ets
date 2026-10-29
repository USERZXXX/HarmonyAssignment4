import { common } from '@kit.AbilityKit';
import { FetchSampleOutcome, LoadNoteOutcome, OpResult } from '../model/NoteModels';
import { NoteViewModel } from '../viewmodel/NoteViewModel';

/**
 * 主页面（入口页）：
 * - 笔记标题 / 正文（多行）/ 密码（掩码）输入；
 * - 四个操作按钮：获取网络示例 / 加密保存 / 读取并解密 / 打开详情；
 * - 结果提示区（成功/失败分色展示）；
 * - busy 防重入：异步操作期间禁用按钮，避免重复提交。
 */
@Entry
@ComponentV2
struct Index {
  @Local titleInput: string = '';
  @Local contentInput: string = '';
  @Local passwordInput: string = '';
  @Local sampleText: string = '';
  @Local resultMsg: OpResult = { success: true, message: '请输入笔记内容后进行操作' };
  @Local busy: boolean = false;
  private vm: NoteViewModel = new NoteViewModel();
  private hostContext: common.Context | null = null;

  aboutToAppear(): void {
    // 获取宿主 Ability 上下文（文件读写 / Ability 跳转使用）
    const host: common.Context | undefined = this.getUIContext().getHostContext();
    if (host !== undefined) {
      this.hostContext = host;
    }
  }

  /** 加密保存：busy 防重入 → 调用视图模型 → 回填结果 */
  private async onSaveNote(): Promise<void> {
    if (this.busy || this.hostContext === null) {
      return;
    }
    this.busy = true;
    try {
      this.resultMsg = await this.vm.saveNote(
        this.titleInput, this.contentInput, this.passwordInput, this.hostContext);
    } finally {
      this.busy = false;
    }
  }

  /** 读取并解密：busy 防重入 → 调用视图模型 → 成功时回填标题/正文输入框 */
  private async onLoadNote(): Promise<void> {
    if (this.busy || this.hostContext === null) {
      return;
    }
    this.busy = true;
    try {
      const outcome: LoadNoteOutcome = await this.vm.loadNote(this.passwordInput, this.hostContext);
      this.resultMsg = outcome.result;
      if (outcome.draft !== null) {
        this.titleInput = outcome.draft.title;
        this.contentInput = outcome.draft.content;
      }
    } finally {
      this.busy = false;
    }
  }

  /** 获取网络示例：busy 防重入 → 调用视图模型 → 暂存示例文本 */
  private async onFetchSample(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const outcome: FetchSampleOutcome = await this.vm.fetchSample();
      this.resultMsg = outcome.result;
      if (outcome.sampleText.length > 0) {
        this.sampleText = outcome.sampleText;
      }
    } finally {
      this.busy = false;
    }
  }

  /** 把已获取的网络示例文本填入笔记正文输入框 */
  private onFillSample(): void {
    if (this.sampleText.length === 0) {
      return;
    }
    this.contentInput = this.sampleText;
  }

  /** 打开详情：busy 防重入 → 经 Want（仅标题/正文）拉起 NoteDetailAbility */
  private async onOpenDetail(): Promise<void> {
    if (this.busy || this.hostContext === null) {
      return;
    }
    const abilityContext: common.UIAbilityContext = this.hostContext as common.UIAbilityContext;
    this.busy = true;
    try {
      this.resultMsg = await this.vm.openDetail(abilityContext, this.titleInput, this.contentInput);
    } finally {
      this.busy = false;
    }
  }

  build() {
    Column({ space: 12 }) {
      Text('个人加密笔记')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)

      TextInput({ placeholder: '请输入笔记标题', text: this.titleInput })
        .width('100%')
        .onChange((value: string) => {
          this.titleInput = value;
        })

      TextArea({ placeholder: '请输入笔记正文', text: this.contentInput })
        .width('100%')
        .height(110)
        .onChange((value: string) => {
          this.contentInput = value;
        })

      TextInput({ placeholder: '请输入加密密码', text: this.passwordInput })
        .width('100%')
        .type(InputType.Password)
        .onChange((value: string) => {
          this.passwordInput = value;
        })

      Row({ space: 12 }) {
        Button('获取网络示例')
          .enabled(!this.busy)
          .layoutWeight(1)
          .onClick(() => {
            this.onFetchSample();
          })
        Button('加密保存')
          .enabled(!this.busy)
          .layoutWeight(1)
          .onClick(() => {
            this.onSaveNote();
          })
      }
      .width('100%')

      Row({ space: 12 }) {
        Button('读取并解密')
          .enabled(!this.busy)
          .layoutWeight(1)
          .onClick(() => {
            this.onLoadNote();
          })
        Button('打开详情')
          .enabled(!this.busy)
          .layoutWeight(1)
          .onClick(() => {
            this.onOpenDetail();
          })
      }
      .width('100%')

      // 操作结果提示区：成功绿色 / 失败红色
      if (this.resultMsg.success) {
        Text(this.resultMsg.message)
          .fontSize(15)
          .fontColor('#2E7D32')
          .width('100%')
          .textAlign(TextAlign.Center)
      } else {
        Text(this.resultMsg.message)
          .fontSize(15)
          .fontColor('#C62828')
          .width('100%')
          .textAlign(TextAlign.Center)
      }

      // 网络示例展示区：仅在已获取到示例文本时显示
      if (this.sampleText.length > 0) {
        Text(this.sampleText)
          .fontSize(13)
          .fontColor('#424242')
          .width('100%')
          .maxLines(6)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding(10)
          .borderRadius(8)
          .backgroundColor('#F5F5F5')

        Button('填入正文')
          .enabled(!this.busy)
          .width('100%')
          .onClick(() => {
            this.onFillSample();
          })
      }
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }
}
