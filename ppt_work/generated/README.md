# 答辩 PPT 正式技术页清单

以下是应直接插入答辩文件的正式整页图（16:9，1672 × 941）。已同步汇编为 [技术章节 PPTX](../信号处理算子库_技术页_P03-P19.pptx)，含 P03～P19 共 17 页。P01 封面、P02 团队页和 P20 致谢页由团队自行制作；不要误用目录中早期的 P03/P18 迭代版本。

| 页码 | 正式文件 | 生成方式 |
|---|---|---|
| P03 | `P03_赛题重述_整页_v03_技术链路.png` | GPT 生图，技术链路版 |
| P04 | `P04_技术路线_统一L6实测_v07.png` | GPT 生图编辑；保留技术路线构图，Task1/Task2 标签同步为统一 L6 实测中位数 |
| P05 | `P05_Wiener_Tile_Halo_整页_v01.png` | GPT 生图 |
| P06 | `P06_IIR_Affine_Prefix_Scan_整页_v01.png` | GPT 生图 |
| P07 | `P07_Periodogram_R2C_Fusion_Cache_整页_v01.png` | GPT 生图 |
| P08 | `P08_Task1_Device_Resident_整页_v01.png` | GPT 生图 |
| P09 | `P09_Task1_统一L1-L6_实测_v07.png` | 真实统一 L1–L6 曲线、L6 中位数与检测门禁 |
| P10 | `P10_Task2_Score_Only_生图重构_v06.png` | GPT 生图重构；逐帧全量张量与 batched score-only 的结构对比 |
| P11 | `P11_Task2_统一L1-L6_实测_v07.png` | 真实统一 L1–L6 曲线、L6 中位数与轨迹门禁 |
| P12 | `P12_代码架构_整页_v01.png` | GPT 生图 |
| P13 | `P13_81算子与公共机制_整页_v01.png` | GPT 生图 |
| P14 | `P14_统一L6正确性_实测_v07.png` | 真实统一 L6 正确性与 12 点运行门禁 |
| P15 | `P15_算子库性能总览_整页_v02.png` | 真实 JSON 图表：81/81 算子有性能记录 |
| P16 | `P16_统一L1-L6规模与热点_实测_v07.png` | 真实统一曲线与 L6 Top3 GPU event 阶段 |
| P17 | `P17_统一测评与改进方向_生图重构_v06.png` | GPT 生图重构；统一测评与参数 A/B 的先后关系 |
| P18 | `P18_核心亮点_生图重构_v06.png` | GPT 生图重构；三类结构重构的可视化亮点 |
| P19 | `P19_AI工具使用说明_生图重构_v06.png` | GPT 生图重构；AI 辅助、真实证据和人工核验的闭环 |

P15 使用 `RUN 2026-07-20 SNAPSHOT` 的单位 benchmark。P04、P09、P11、P14、P16 已使用 **ZQ500 实测 unified_l1_l6_v1**：原 `final-input` 被纳入新 L6，旧 task `scales/` 与旧 `final/` 数字不得回填这些正式数据页。表格、原始哈希和复测规则分别见 [数据表](../data_tables/) 与 [统一 L1–L6 复测计划](../unified_scale_retest_plan.md)。
