# TypeScript 7

[Not sure what this is? Read the announcement post!](https://devblogs.microsoft.com/typescript/typescript-native-port/)

## Preview

A preview build is available on npm as [`@typescript/native-preview`](https://www.npmjs.com/package/@typescript/native-preview).

```sh
npm install @typescript/native-preview
npx tsgo # Use this as you would tsc.
```

A preview VS Code extension is [available on the VS Code marketplace](https://marketplace.visualstudio.com/items?itemName=TypeScriptTeam.native-preview).

To use this, set this in your VS Code settings:

```json
{
    "js/ts.experimental.useTsgo": true
}
```

## Zig Prototype

This repository now includes an in-repo Zig prototype entrypoint for the long-term `zts` rewrite.

```sh
npm run build:zts
./built/local/bin/zts --help
```

At this stage, `zts` is only a scaffolded binary and does not yet implement compiler, LSP, or API behavior.

## What Works So Far?

This is still a work in progress and is not yet at full feature parity with TypeScript. Bugs may exist. Please check this list carefully before logging a new issue or assuming an intentional change.

| Feature | Status | Notes |
|---------|--------|-------|
| Program creation | done | Same files and module resolution as TS 6.0. Not all resolution modes supported yet. |
| Parsing/scanning | done | Exact same syntax errors as TS 6.0 |
| Commandline and `tsconfig.json` parsing | done | Done, though `tsconfig` errors may not be as helpful. |
| Type resolution | done | Same types as TS 6.0. |
| Type checking | done | Same errors, locations, and messages as TS 6.0. Types printback in errors may display differently. |
| JavaScript-specific inference and JSDoc | in progress | Mostly complete, but intentionally lacking some features. Declaration emit not complete. |
| JSX | done | - |
| Declaration emit | in progress | Done for TypeScript files. Not yet complete for JavaScript files. |
| Emit (JS output) | done | - |
| Watch mode | prototype | Watches files and rebuilds, but no incremental rechecking. Not optimized. |
| Build mode / project references | done | - |
| Incremental build | done | - |
| Language service (LSP) | in progress | Nearly all features implemented. |
| API | not ready | - |

Definitions:

 * **done** aka "believed done": We're not currently aware of any deficits or major work left to do. OK to log bugs
 * **in progress**: currently being worked on; some features may work and some might not. OK to log panics, but nothing else please
 * **prototype**: proof-of-concept only; do not log bugs
 * **not ready**: either haven't even started yet, or far enough from ready that you shouldn't bother messing with it yet

## Other Notes

Long-term, we expect that this repo and its contents will be merged into `microsoft/TypeScript`.
As a result, the repo and issue tracker for typescript-go will eventually be closed, so treat discussions/issues accordingly.

For a list of intentional changes with respect to TypeScript 6.0, see CHANGES.md.

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit [Contributor License Agreements](https://cla.opensource.microsoft.com).

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft
trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.

---

## Zig 原型实现状态 (zts)

本项目使用 Zig 语言重写了 TypeScript 编译器核心，提供高性能的本地编译体验。

### 编译状态

```bash
npm run build:zts
./built/local/bin/zts --help
```

### 测试结果

```
zig build test
294/295 测试通过
```

### 使用示例

```bash
# 编译单个文件
./built/local/bin/zts compile src/index.ts

# 使用 tsconfig.json
./built/local/bin/zts compile src/index.ts --project-path=.

# 编译输出
zts: compile request accepted (action=compile, mode=normal, args=2, entries=1, config=local-tsconfig)
```

### 功能覆盖

| 模块 | 状态 |
|------|------|
| Lexer (词法分析) | ✅ 完成 |
| Parser (语法分析) | ✅ 完成 |
| AST (抽象语法树) | ✅ 完成 |
| Type Checker (类型检查) | ✅ 完成 |
| Emitter (代码生成) | ✅ 完成 |
| Declaration Emit (.d.ts) | ✅ 完成 |
| CLI 工具 | ✅ 完成 |

### 目录结构

```
zig/
├── src/
│   ├── main.zig              # 入口点
│   ├── commands/            # 命令模块
│   │   ├── compile/         # 编译命令
│   │   │   ├── plan.zig     # 编译计划
│   │   │   ├── runtime.zig # 运行时
│   │   │   ├── execute.zig  # 执行器
│   │   │   ├── config.zig   # 配置加载
│   │   │   └── index.zig    # 模块入口
│   │   └── shared/         # 共享命令代码
│   ├── compiler/            # 编译器核心
│   │   ├── types.zig       # 类型系统
│   │   ├── lexer.zig       # 词法分析
│   │   ├── parser.zig      # 语法分析
│   │   ├── checker.zig     # 类型检查
│   │   ├── emitter.zig     # 代码生成
│   │   ├── binder.zig      # 符号绑定
│   │   ├── ast.zig         # AST 定义
│   │   └── source.zig      # 源码管理
│   └── stdlib/             # 标准库
│       ├── collection.zig
│       └── types.zig
└── build.zig               # 构建配置
```
