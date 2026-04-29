# typescript-go 全量 Zig 重构计划（重命名为 zts）

  ## 摘要

  目标不是“把 Go 包一层 Zig”，而是把当前 typescript-go 的编译器核心、LSP 核心、API 服务端核心全部迁到 Zig，并以当前仓库行为为兼容基线。
  一期对外必须同时提供三类能力：

  - zts CLI
  - zts lsp --stdio 语言服务
  - @zts/native-preview JS API（sync / async / fs / proto / ast 出口保留同类结构）

  迁移期允许 Go 与 Zig 在同仓短期并存，但 Go 只作为参考实现和回归基线；最终默认入口、构建、分发、扩展全部切到 Zig，并删除 Go 实现。

  ## 关键设计

  ### 对外命名与接口

  - CLI 名称统一改为 zts
  - npm 包统一改为 @zts/native-preview
  - VS Code 扩展统一改为 ZTS (Native Preview)，扩展 id 改为 zts.native-preview
  - 配置前缀统一改为 zts.native-preview.*
  - 统一开关改为 js/ts.experimental.useZts 与 zts.experimental.useZts
  - JS API 出口形状保持当前模型：
      - @zts/native-preview/sync
      - @zts/native-preview/async
      - @zts/native-preview/fs
      - @zts/native-preview/proto
      - @zts/native-preview/ast

  ### 核心架构

  - 新增 Zig 主实现目录，按子系统拆为：
      - core: scanner、parser、AST、symbols、types、checker、emit
      - project: tsconfig 解析、module resolution、project graph、incremental state、watch
      - services: CLI dispatcher、LSP server、API session server
      - runtime: VFS、bundled libs、path/OS abstraction、diagnostics、serialization
  - Zig 核心直接承担语义逻辑；不再依赖 Go，也不以嵌入现有 Go 为过渡方案
  - JS API 继续采用子进程/pipe 协议连接 Zig 核心：
      - async API 继续用 JSON-RPC
      - sync API 继续保留当前 MessagePack tuple 风格
      - 目标是保持现有测试和调用方式可迁移，而不是暴露新的 FFI/动态库模型
  - VS Code 扩展继续作为 TypeScript 包装层，仅替换启动目标、配置键、命令和品牌；LSP 语义全部来自 Zig 二进制

  ### 兼容边界

  - 兼容目标优先对齐当前 typescript-go 的外部行为，而不是一步追平官方 TypeScript 的所有差异
  - 行为兼容优先级：
      1. CLI 诊断、退出码、emit 结果
      2. LSP 请求/响应行为
      3. JS API 调用结果与对象模型
      4. watch / incremental / project references
  - 不要求保留旧的 tsgo 名称、旧 npm 包名、旧扩展 id
  - 不追求与当前内部 Go API 二进制兼容；只保留对外产品行为兼容

  ## 实施阶段

  ### 阶段 0：冻结基线与差分框架

  - 冻结现有 Go 主线为参考实现，只接受阻塞型修复
  - 建立 Go-vs-Zig 差分测试驱动：
      - 相同输入跑两套实现
      - 比较 CLI 退出码、诊断文本、emit 输出、LSP 响应、JS API 结果
  - 抽取当前仓库的最小“产品契约”：
      - CLI 参数与子命令集合
      - LSP 启动方式与能力声明
      - JS API 协议方法、消息结构、导出面
  - 先不公开 Zig 预览；只有差分框架和接口契约完成后才进入实现阶段

  ### 阶段 1：Zig CLI 核心打通

  - 在 Zig 中先完成：
      - scanner / parser / AST / diagnostics
      - tsconfig 读取
      - module resolution / program creation
      - checker / emitter 的最小闭环
  - 首个可运行目标是 zts CLI，可完成单项目编译、诊断、emit、build mode
  - watch / incremental 在本阶段按“可用但不优化”实现，先保证语义正确
  - 这一阶段结束标准：
      - 现有 CLI smoke tests 全过
      - 核心 baseline 测试达到可比较状态
      - zts 已可替代当前命令行主路径进行本地验证

  ### 阶段 2：LSP 与 JS API 接入 Zig 核心

  - 用 Zig 实现 LSP server，保持 stdio 启动模型
  - 用 Zig 实现 API server：
      - async JSON-RPC 通道
      - sync MessagePack tuple 通道
      - Unix socket / Windows named pipe 支持
  - 将 @zts/native-preview 的 TS 包装层接到 Zig 二进制：
      - bin/zts
      - sync / async client
      - getExePath / 平台包解析
  - 同步把 VS Code 扩展改为启动 zts lsp --stdio
  - 这一阶段结束标准：
      - 现有 JS API sync/async 测试大体复用成功
      - 扩展可在 VS Code 中完成基本 hover / definition / diagnostics / rename / source definition
      - Windows / macOS / Linux 三平台通信模型跑通

  ### 阶段 3：语义与服务完整对齐

  - 用当前仓库测试作为主基线，补齐 Zig 版在以下方面的差距：
      - checker 精细行为
      - declaration emit
      - LSP 高阶功能与 code actions

  ### 阶段 4：切换默认产物并移除 Go

  - 默认构建、测试、打包、发布全部改为 Zig 主线
  - npm 包、VS Code 扩展、文档、脚本、CI 名称全部切到 zts
  - 停止发布 tsgo / @typescript/native-preview / 旧扩展标识
  - 删除 Go 二进制构建链、Go 发布链、Go 入口与旧品牌文档
  - 最终只保留：
      - Zig 核心
      - TypeScript 包装层与扩展层
      - 新的 zts 分发与测试体系

  ## 测试与验收

  - CLI：
      - 编译成功/失败退出码
      - 诊断位置、消息、顺序
      - emit 输出、declaration emit、project references、watch、incremental
  - LSP：
      - initialize / hover / definition / references / rename / code actions / source definition
      - 大型工作区、多项目、配置切换、文件变更
  - JS API：
      - sync 与 async 两条链全部回归
      - pipe/socket、Windows named pipe、stdio 子进程
      - AST、encoder、sourceFileCache、filesystem callback
  - 扩展：
      - 启动与版本发现
      - 命令菜单、trace、API 初始化、workspace tsdk/zsdk 选择
  - 差分：
      - 同一测试输入同时跑 Go 与 Zig
      - 差分以“外部结果”为准，不比较内部实现细节
  - 性能：
      - 至少保留现有 benchmark 入口
      - 在 CLI、LSP 初始化、API 启动、增量诊断四类路径做回归门槛

  ## 默认假设

  - “全量 Zig 重构”解释为：所有编译器/LSP/API 服务端语义迁到 Zig；npm 包和 VS Code 扩展作为薄包装层仍可保留 TypeScript 实现
  - 迁移期允许 Go 与 Zig 同仓并存，但 Go 不再承载新增功能
  - 一期对外必须同时具备 CLI + LSP + JS API，不能只交其中一项
  - 兼容优先级以当前 typescript-go 行为和测试为准，后续再考虑与官方 TypeScript 的差异收敛
  - 对外品牌统一采用 zts 前缀，不保留 tsgo 作为正式公开入口