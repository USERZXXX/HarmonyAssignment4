# Implementation Plan: 个人加密笔记应用（EncryptedNote）

**Input**: Feature specification from `spec/encrypted-note/spec.md`

## Summary

在 `D:\code\HarmonyProject\Assignment4` 新建独立单 entry 模块 HarmonyOS 工程，实现"个人加密笔记"：主页面提供标题/正文/密码输入与四个操作按钮；网络模块经 `@kit.NetworkKit` HTTPS GET 获取示例文本；加密模块使用 `@kit.CryptoArchitectureKit` 的 PBKDF2|SHA256 密钥派生 + AES-256-GCM 认证加密（盐/IV 由密码学安全随机数生成）；文件模块以固定文件名将记录 JSON 持久化到应用沙箱 `filesDir`；Stage 模型双 UIAbility（EntryAbility + NoteDetailAbility），经 Want/startAbility 跳转详情；全程 hilog 记录成败且不落敏感数据。

## Technical Context

**Language/Version**: ArkTS（ets），compatibleSdkVersion 6.x / API 24 级别（与 Assignment3 工具链一致），Stage 模型  
**Primary Dependencies**: 官方 Kit：`@kit.NetworkKit`(http)、`@kit.CryptoArchitectureKit`(cryptoFramework)、`@kit.CoreFileKit`(fileIo)、`@kit.PerformanceAnalysisKit`(hilog)、`@kit.ArkTS`(util：Base64/TextEncoder/TextDecoder)。零第三方依赖。  
**State Management**: 全新工程 → State Management V2（@ComponentV2 + @Local；跨 Ability 数据经 Want params 传递，不用全局状态）  
**Storage**: 应用沙箱文件（`context.filesDir` + 固定文件名 `encrypted_note.json`），JSON 文本格式  
**Testing**: 构建级验证：`arkts_check`（严格模式静态检查）+ `devecocli build`（编译产出 hap）；运行时按 spec 验收步骤人工/UI 验证  
**Target Platform**: HarmonyOS 手机/模拟器（debug 签名运行）  
**Project Type**: mobile-app（单 entry 模块 HAP）  
**Performance Goals**: 加密/解密单次操作 < 1s（PBKDF2 10000 次迭代 + 短文本）；网络超时 10s  
**Constraints**: 不使用浏览器/Node 专属 API；不虚构接口；仅申请 `ohos.permission.INTERNET`；不故意植入漏洞；日志与持久化文件不得含明文密码/派生密钥/笔记正文  
**Scale/Scope**: 2 个页面、2 个 UIAbility、3 个 service、约 10 个 ArkTS 文件

## Project Structure

### Documentation (this feature)

```text
Assignment4/spec/encrypted-note/
├── spec.md              # 需求规格（Phase 1）
├── plan.md              # 本文件（Phase 2）
└── tasks.md             # 任务分解（Phase 3）
```

### Source Code (repository root = D:\code\HarmonyProject\Assignment4)

```text
Assignment4/                                   # devecocli create 脚手架生成后增量开发
├── build-profile.json5                        # 脚手架生成（SDK 配置）
├── AppScope/app.json5                         # 脚手架生成
└── entry/
    ├── build-profile.json5                    # 脚手架生成
    ├── src/main/
    │   ├── module.json5                       # 修改：注册双 Ability、INTERNET 权限
    │   ├── resources/base/profile/main_pages.json   # 修改：登记两个页面
    │   └── ets/
    │       ├── entryability/EntryAbility.ets        # 修改：加载 pages/Index（入口）
    │       ├── entryability/NoteDetailAbility.ets   # 新增：详情 UIAbility，加载 pages/NoteDetail
    │       ├── pages/Index.ets                      # 新增：主页面（表单+按钮+结果区）
    │       ├── pages/NoteDetail.ets                 # 新增：详情页（标题/正文+返回）
    │       ├── viewmodel/NoteViewModel.ets          # 新增：页面状态与业务编排
    │       ├── model/NoteModels.ets                 # 新增：EncryptedNoteRecord、RawRecord、OpResult
    │       ├── service/CryptoService.ets            # 新增：PBKDF2 + AES-GCM + CSRNG
    │       ├── service/FileService.ets              # 新增：沙箱文件读写
    │       ├── service/NetworkService.ets           # 新增：HTTPS GET 示例文本
    │       └── common/
    │           ├── AppConfig.ets                    # 新增：URL/文件名/加密参数常量
    │           └── Logger.ets                       # 新增：hilog 封装
    └── oh-package.json5                        # 脚手架生成（不加依赖）
```

**Structure Decision**: 全新工程，选择 **MVVM 层级（最小文件集）**。触发条件命中：多页面（Index/NoteDetail）、持久化（沙箱文件）、业务服务（加密/网络/文件三个可测域服务）。为避免文件碎片化，模型合并为单文件 `model/NoteModels.ets`，常量与日志各一个文件，总计 11 个 ArkTS 文件（含 2 个 Ability），落在 MVVM 6-12 文件目标区间。`viewmodel/` 承担页面状态与编排，页面（pages/）只做 UI 组装与事件绑定，算法与持久化全部在 service/ 层，符合 MVVM 职责边界。资源文件仅用脚手架自带资源，不新增 media。

## Complexity Tracking

无 Constitution 违规需要豁免。

## Research & Decisions

### R1: 密钥派生与认证加密方案（已对照当前 SDK 文档核实）

- **Decision**: 采用 `@ohos.security.cryptoFramework`（`@kit.CryptoArchitectureKit`）：
  - 派生：`cryptoFramework.createKdf('PBKDF2|SHA256')` + `PBKDF2Spec{algName:'PBKDF2', password, salt, iterations:10000, keySize:32}` → `kdf.generateSecret(spec): Promise<DataBlob>`（API 11+）
  - 随机数：`cryptoFramework.createRandom()` + `generateRandomSync(len)` 生成 16 字节盐与 12 字节 IV（API 10+）
  - 加密：`cryptoFramework.createCipher('AES256|GCM|NoPadding')`；`GcmParamsSpec{algName:'GcmParamsSpec', iv, aad:空Uint8Array, authTag}`；密钥经 `createSymKeyGenerator('AES256').convertKey(派生密钥DataBlob)` 转换；加密 `doFinal` 输出的**末尾 16 字节为 authTag**（切片保存，密文与标签分开存储）
  - 解密：用持久化的盐/迭代次数重新派生密钥，`GcmParamsSpec.authTag` 传入保存的标签，`doFinal` 认证失败即抛错（17630001 等）
- **Rationale**: PBKDF2|SHA256 与 AES-256-GCM 均为当前 SDK（API 24 级别）cryptoFramework 直接支持的官方能力，满足"安全派生 + 认证加密 + CSRNG"要求；Code Linter 安全规则（no-unsafe-kdf / no-unsafe-aes）也推荐 PBKDF2|SHA256 并禁止 ECB。
- **Alternatives considered**: HUKS 派生（需密钥别名托管，流程重且密钥不出安全环境与"记录随文件走"的实验目标不符）；SCRYPT（API 18+ 可用但参数复杂度高，短文本场景无必要）；HKDF（不适合低熵口令）。Base64 伪加密被需求明令禁止。

### R2: 网络方案

- **Decision**: `@kit.NetworkKit` 的 `http.createHttp()` → `request(url, options)`，options：`method: GET`、`expectDataType: STRING`、`connectTimeout: 10000`、`readTimeout: 10000`、`usingCache: false`；成功判定 `responseCode === 200`（httpbin 仅 200）；无论成败在 finally 中 `httpRequest.destroy()` 释放资源。URL 集中于 `AppConfig.SAMPLE_URL`（默认 `https://httpbin.org/get`）。
- **Rationale**: 官方 HTTP API 原生支持超时与资源释放；GET 请求天然不携带用户数据，满足"不上传笔记/密码"。
- **Alternatives considered**: WebSocket/RCP（超出需求）；fetch 类浏览器 API（禁止）。

### R3: 文件存储方案

- **Decision**: `@kit.CoreFileKit` 的 `fileIo`：写入 `openSync(path, CREATE|TRUNC|WRITE)` → `writeSync` → `closeSync`（finally 保证关闭）；读取 `accessSync` 先判存在 → `openSync(READ_ONLY)` → `statSync` 取大小 → `readSync` → `closeSync`。路径 = `context.filesDir + '/' + AppConfig.NOTE_FILE_NAME`（固定名 `encrypted_note.json`），用户输入绝不参与路径拼接。文件不存在返回 null（UI 提示"暂无保存的笔记"）。
- **Rationale**: filesDir 为应用专属沙箱，卸载才清除，满足"重启后可读"；固定文件名规避路径注入类审计告警。
- **Alternatives considered**: Preferences/KV（适合小键值，但本需求是单文件记录且需展示文件级 IO 资源管理，JSON 文件更贴题）；数据库（需求明说不引入）。

### R4: 记录封装与损坏检测

- **Decision**: 持久化为单条 JSON：`{version:1, kdfAlg:'PBKDF2-SHA256', cipherAlg:'AES256-GCM', iterations, saltB64, ivB64, tagB64, cipherB64, title}`。title 按需求明文保存（仅正文要求加密）；二进制字段用 `util.Base64Helper` 编码。读取时：JSON.parse 失败/字段缺失/base64 解码失败/长度校验失败（salt 16B、iv 12B、tag 16B）→ 归类"数据损坏"；进入 GCM 解密失败 → 归类"密码错误或数据损坏"。
- **Rationale**: 版本字段为审计实验提供前向兼容演示；元数据齐备且不含密钥/密码。
- **Alternatives considered**: 二进制定长头格式（解析代码量大、易错，JSON 更可读且仍是安全的——密文本身无敏感性）。

### R5: 双 Ability 与跳转

- **Decision**: EntryAbility 保持主入口（`exported: true` + entity.system.home skills，满足正常启动）；NoteDetailAbility `exported: false` 且无 skills（仅供应用内 startAbility 拉起）。跳转：主页面构造 `Want{bundleName, abilityName:'NoteDetailAbility', params:{title, content}}`（仅标题与正文，无密码/密钥）经 `UIAbilityContext.startAbility` 发起；详情页"返回"按钮调用 `terminateSelf()`，系统返回手势同样生效。JSON.parse 解析 Want params 前做 null/类型校验。
- **Rationale**: 符合 Stage 模型最小双 Ability 要求；exported:false 直接满足"详情 Ability 仅供应用内部调用"。
- **Alternatives considered**: 同 Ability 内页面路由（不满足"独立 NoteDetailAbility"需求）；AppStorage 传参（跨 Ability 生命周期耦合，且审计上不如显式 Want 清晰）。

### R6: 状态管理与防重入

- **Decision**: 全新工程用 State Management V2：页面 `@ComponentV2` + `@Local` 持有输入值与结果状态；NoteViewModel 为普通 class（持有引用更新页面 @Local 字段），异步操作期间 `@Local busy: boolean = true` 禁用四个按钮防重复提交。
- **Rationale**: 绿地工程按规范选 V2；无跨页观察需求，不需要 @ObservedV2/@Trace。
- **Alternatives considered**: V1 @State（新工程不推荐混用）。

### R7: 日志安全

- **Decision**: `common/Logger.ets` 封装 hilog（domain 0x0000，固定格式串 `'%{public}s'`），提供 info/error 两级；调用方契约：只传事件与结果（如"encrypt save ok"/"http request failed, code=xxx"），禁止传密码、密钥、笔记正文；标题也不落日志。
- **Rationale**: 集中封装便于静态审计核查；hilog 为官方日志 API。

### R8: 工程脚手架

- **Decision**: Phase 4 首个任务用 `devecocli create --app-name EncryptedNote --project-path D:\code\HarmonyProject\Assignment4`（api-level 默认/auto，与当前环境 SDK 对齐；bundle-name 默认 com.example.encryptednote），随后在脚手架基础上增量实现，不手改脚手架构建文件（module.json5/main_pages.json 除外）。
- **Rationale**: 环境已有可用工具链（Assignment3 即此方式构建成功）；保留官方构建结构。
- **Alternatives considered**: 手工复制 Assignment3 多模块骨架（结构过重且引入无关模块）。

## Data Model

### EncryptedNoteRecord（持久化记录，JSON）

| 字段 | 类型 | 说明 / 校验 |
|---|---|---|
| version | number | 固定 1；≠1 视为损坏 |
| kdfAlg | string | 固定 'PBKDF2-SHA256' |
| cipherAlg | string | 固定 'AES256-GCM' |
| iterations | number | 正整数（当前 10000）；用于解密时重派生 |
| saltB64 | string | base64(salt)，解码后须 16 字节 |
| ivB64 | string | base64(iv)，解码后须 12 字节 |
| tagB64 | string | base64(GCM authTag)，解码后须 16 字节 |
| cipherB64 | string | base64(密文，不含 authTag)，非空 |
| title | string | 明文标题（需求仅要求正文加密） |

**不出现的字段**：明文密码、派生密钥、明文正文。

### CryptoEnvelope（内存中加密结果，service 层内部）

salt: Uint8Array(16)、iv: Uint8Array(12)、tag: Uint8Array(16)、cipher: Uint8Array —— 由 EncryptOutcome 映射到 EncryptedNoteRecord。

### OpResult（UI 反馈）

`{ success: boolean, message: string }` —— message 为面向用户的中文提示；不包含密钥/密文等技术细节。

### 状态流转

- 主页面 @Local：`titleInput / contentInput / passwordInput / sampleText / result(OpResult) / busy`
- 异步链路：按钮 → ViewModel 方法 → service → 更新 result；busy 在链路首尾置位/复位

## Contracts & Interfaces

### CryptoService（service/CryptoService.ets）

- `encryptContent(password: string, plainText: string): Promise<CryptoEnvelope>` —— 前置：password/plainText 非空（页面已校验，service 内再防御一次）；生成随机盐/IV → PBKDF2 派生 → AES-GCM 加密 → 分离 authTag
- `decryptContent(password: string, record: EncryptedNoteRecord): Promise<string>` —— 校验记录字段 → 重派生 → GCM 解密（authTag 校验失败抛 BusinessError，映射为"密码错误或数据损坏"）
- `isPasswordEmpty / isCorruptRecord` 等判定以抛出的 `NoteError`（含 code: 'EMPTY_PASSWORD' | 'WRONG_PASSWORD_OR_CORRUPT' | 'FILE_CORRUPT'）区分；文本 ↔ Uint8Array 用 `util.TextEncoder/TextDecoder`（UTF-8，fatal 解码失败归入损坏）

### FileService（service/FileService.ets）

- `saveRecord(context: Context, record: EncryptedNoteRecord): Promise<void>` —— 序列化 JSON → 覆盖写固定文件；任何 IO 异常上抛
- `readRecord(context: Context): Promise<EncryptedNoteRecord | null>` —— 文件不存在返回 null；存在则读取并解析+校验，损坏抛 'FILE_CORRUPT'
- 资源契约：所有 `openSync` 的 fd 在 finally `closeSync`

### NetworkService（service/NetworkService.ets）

- `fetchSampleText(): Promise<string>` —— GET `AppConfig.SAMPLE_URL`；200 → 返回响应体字符串；非 200 → 抛含状态码错误；异常（无网络/超时）→ 抛 `NoteError('NETWORK_FAIL')` 附原始 message；finally `destroy()`
- 契约：请求 options 不含任何用户数据字段

### NoteViewModel（viewmodel/NoteViewModel.ets）

- `fetchSample(): Promise<void>` —— 调 NetworkService，成功把样例文本写入页面 `sampleText` 并提示，失败写入错误 result
- `saveNote(): Promise<void>` —— 校验非空（标题/正文/密码）→ CryptoService.encryptContent → FileService.saveRecord → result 成功
- `loadNote(): Promise<void>` —— 校验密码非空 → FileService.readRecord（null → "暂无保存的笔记"）→ CryptoService.decryptContent → 回填 titleInput/contentInput
- `openDetail(context: UIAbilityContext): Promise<void>` —— 校验当前有内容 → 构造 Want（params 仅 title/content）→ startAbility；失败落日志与 result
- 所有方法：入口置 busy=true，finally busy=false；所有成败经 Logger 落 hilog

### Want / Ability 契约

- 跳转 Want：`{ bundleName: 'com.example.encryptednote', abilityName: 'NoteDetailAbility', params: JSON.stringify({ title, content }) }`（params 传 string，详情侧 JSON.parse 后按 Record 校验）
- 详情页返回：`terminateSelf()`；详情页对 params 缺失/解析失败渲染兜底文案，不崩溃
- module.json5：EntryAbility（exported true + home skills）；NoteDetailAbility（exported false，无 skills）；`requestPermissions: [ { name: 'ohos.permission.INTERNET' } ]`（系统授权级权限，无需 reason/usedScene）；main_pages.json 登记 `pages/Index`、`pages/NoteDetail`

### AppConfig（common/AppConfig.ets）

`SAMPLE_URL = 'https://httpbin.org/get'`、`NOTE_FILE_NAME = 'encrypted_note.json'`、`PBKDF2_ITERATIONS = 10000`、`SALT_LEN = 16`、`IV_LEN = 12`、`TAG_LEN = 16`、`KEY_SIZE = 32`、`HTTP_TIMEOUT_MS = 10000`
