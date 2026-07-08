# 中科芯迁移记录硬规则

中科芯迁移期间，本文规则与 `AGENT.md` 同级优先。发现的不兼容点、需要修改点、已修改点、暂缓点和 fallback，必须全部记录到 `docs/migration/zhongkexin/change_log.md`。

## 必须记录的情况

- 发现中科芯平台与既有 CUDA 代码、SDK 示例、runtime、库 target、头文件、链接方式、数值结果、性能、工具链或运行行为上的差异。
- 发现需要修改源码、CMake、脚本、测试、demo、报告或文档的地方。
- 实施了任何中科芯相关修改。
- 引入、保留或删除 fallback。
- 调整 public API、报告字段、测试阈值、性能 gate、验证命令或构建入口。

## 每条记录至少包含

- 编号。
- 发现阶段。
- 模块或文件。
- 问题现象。
- 原因判断。
- 计划修改。
- 实际修改。
- 对 CPU reference 与中科芯 ZQ500 GPU 链路的影响范围。
- 验证命令和验证结果。
- 当前状态和后续处理阶段。

## 执行要求

- 即使暂时不修，也必须先记录。
- 修改前记录“计划修改”，修改后补充“实际修改”和“验证结果”。
- 每个阶段关闭前，必须核对台账，确认没有只存在于聊天记录或终端输出中的问题。
- 更新 `docs/migration/zhongkexin/change_log.md` 后，同步检查 `docs/migration/zhongkexin/status.md` 是否需要更新。
