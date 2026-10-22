# RAW 汇集 · RAW Sorter

[![macOS build and test](https://github.com/jaminliu89/raw-sorter/actions/workflows/ci.yml/badge.svg)](https://github.com/jaminliu89/raw-sorter/actions/workflows/ci.yml)

把不同相机、不同文件夹的 RAW 汇总到一个新目录，按拍摄时间与亚秒统一排序，同名照片也全部保留。

原生 macOS 桌面小工具，采用 Swift／AppKit，适合婚礼、活动、旅行等双机与多机位素材整理。每次启动默认进入常用的 **A／B 双机位**；更多来源可切换多机位文件夹模式或机身序列号归组。

**只复制，不移动或修改原片。** 本机读取元数据，复制后独立重读目标文件，逐张核对 SHA-256。没有账号、照片上传、遥测或本地网页服务。

## 下载与安装

从 [Releases](https://github.com/jaminliu89/raw-sorter/releases/latest) 下载 DMG，将「RAW 汇集」拖入 Applications。也提供 ZIP 和 `SHA256SUMS.txt`。

当前安装包面向 **Apple Silicon、macOS 26 及以上**。Intel 与较早 macOS 暂未提供经过验证的安装包。内含 ExifTool 13.55，通过系统自带 Perl 执行，运行无需 Homebrew、Python 或 Node。

应用使用 ad-hoc 临时签名，**尚未经过 Apple 公证**。首次运行可能被 macOS 开发者验证拦截；确认下载来源与校验和后，按系统提示在「系统设置 → 隐私与安全性」中处理。

## 常用操作：A／B 双机位

1. 选择「照片主目录」，例如包含 `相机A/`、`相机B/` 的活动目录。恰好两个 RAW 来源时自动填入 A、B，也可分别点击「选择…」。
2. 选择「保存位置」，输入一个**尚不存在**的新文件夹名称。
3. 两台相机时钟有偏差时分别填写偏移秒数，例如 `0`、`2`、`-0.5`。正数调晚、负数调早，只影响排序与文件名。
4. 点击「读取并预览」，核对时间顺序和输出文件名。
5. 点击「复制并校验」，确认数量、位置和体积后开始。完成后可直接打开汇总文件夹。

发现三个以上来源时，A／B 模式会提示切换多机位或手动选择，**不会静默只取两个文件夹**。

```text
活动目录/
  相机A/  IMG0001.ARW
  相机B/  IMG0001.ARW

新汇总目录/
  000001_20261022_105246_696000000_A_IMG0001.ARW
  000002_20261022_105247_553000000_B_IMG0001.ARW
  排序与校验记录.json
  逐张校验记录.jsonl
```

连续序号保证 Finder 按名称查看时保持统一顺序。

## 更多相机与多个文件夹

| 模式 | 归组方式 | 适用情况 |
|---|---|---|
| A／B 双机位 | 两个来源固定为 A、B，各自校时 | 常见双机拍摄 |
| 多机位 · 文件夹 | 每个来源独立一行，可添加、移除、命名和校时 | 三台以上相机，或按摄影师／机位分组 |
| 多机位 · 序列号 | 逐张识别，同一机身跨文件夹共享名称与偏移 | 多卡目录、同一目录混放不同相机 |

序列号模式的「添加来源…」支持多选额外文件夹；「来源…」可查看该机身涉及的全部来源。无有效序列号时按来源保留并标记，不因型号相同误合并。同一内容的不同来源照片也保留，不自动去重。

身份使用厂商、型号与 `BodySerialNumber`、`SerialNumber` 或 `InternalSerialNumber`。Sony 实拍样本使用 `InternalSerialNumber`，不保证等于机身外壳的印刷号码。重新识别主目录会重新建立列表，手动加入的外部来源需要重新添加。

主目录与保存位置保存在本机；文件夹配置按主目录保存，序列号模式的名称和偏移按机身身份保存。更换拍摄日期后请重新核对偏移。

## 时间精度与文件安全

读取 `DateTimeOriginal`、`SubSecTimeOriginal`、`OffsetTimeOriginal`，不使用文件创建／修改时间代替拍摄时间。统一显示为 `+08:00`；缺时区时按 `+08:00` 解释并记录，缺亚秒时明确标记。

文件名将亚秒补齐九位方便排序，**不代表原片具有九位精度**，记录中保留原始位数。相机之间仍需用同一瞬间的照片校准偏移，本工具不自动校时；相同时间按来源完整路径稳定排序，不能推断未记录的真实先后。

目标目录独占新建，已有目录直接拒绝。文件独占创建，绝不覆盖已有文件。拒绝重复或嵌套来源，不跟随符号链接，跳过本工具生成的汇总目录。预览后来源大小、时间或身份发生变化，会阻止复制。

APFS 等支持独占安全重命名时，先写 `.partial`、校验再提交；ExFAT 不支持时直接独占写最终名称，只写一遍，再独立重读目标校验。逐张追加 JSONL，每十张及结束／报错时保存完整 JSON 快照。

停止或失败会保留生成文件。**ExFAT 中途文件可能已使用最终名称，文件存在不代表完成**，以校验记录为准。再次执行请选择新目录。当前不提供断点续传、自动清理或覆盖重跑。

## 格式与性能

扫描 ARW、CR2、CR3、NEF、RAF、DNG、ORF、RW2 扩展名，可读性取决于 ExifTool 与原片元数据。**实拍验证集中于 Sony A7 IV 的 ARW**，不宣称其他格式均已实机测试。

采用 4 MiB 流式缓冲与逐块内存释放，进度最多每秒更新五次。本机 ExFAT 实测完成 2,077 张、约 85.96 GB 的 Sony ARW 汇总，含逐张校验约 14 分 06 秒，均速约 101.7 MB/s，RSS 采样约 44～90 MB。这是特定机器与磁盘的记录，不是性能保证。

另用 128 张、每轮约 5.30 GB 原片进行八轮缓冲／流水线对照。缓存与刷盘状态造成明显波动，没有稳定胜过原方案的证据，因此没有增加大内存缓存或复制并发。

## 从源码构建

需要 Apple Silicon Mac、macOS 26、Xcode Command Line Tools、系统 Perl，以及下载构建依赖的网络。在仓库根目录执行：

```bash
git clone https://github.com/jaminliu89/raw-sorter.git
cd raw-sorter
bash scripts/bootstrap.sh
bash scripts/test.sh
zsh build.sh
open 'build/RAW 汇集.app'
```

`bootstrap.sh` 下载固定版本的 ExifTool 源码并验证 SHA-256。`build.sh` 编译应用、生成图标、内嵌依赖和许可并临时签名。

完整打包还需要 dmgbuild，仅为构建依赖：

```bash
python3 -m venv work/package-env
work/package-env/bin/pip install dmgbuild==1.6.7
DMGBUILD="$PWD/work/package-env/bin/dmgbuild" bash scripts/release.sh
```

产物位于 `dist/`：DMG、ZIP、SHA-256 校验和。DMG 包含应用、Applications 快捷方式和使用说明 PDF。

## 测试与 CI

[GitHub Actions](https://github.com/jaminliu89/raw-sorter/actions) 在 macOS 26 上运行测试、构建、空 PATH 环境入口冒烟、签名检查与 DMG 验证，再上传安装包。推送与 `VERSION` 一致的 `v*` 标签后自动发布 Release。

默认生成**不含照片内容的 TIFF／EXIF 样本**，检查排序、亚秒、时区、归组、同名保留、独占复制、哈希、停止和来源变化。合成样本检查不能代替真实 RAW 兼容或桌面验收。私人原片、配置、测试记录、历史网页原型与构建目录不入库。

本地原生窗口已验证 A／B 与多机位的识别、另存为、预览、ExFAT 实际复制和独立哈希。CI 不执行 GUI 点击，也不代表所有相机均已实测。

通用的只读目录检查：

```bash
'build/RAW 汇集.app/Contents/MacOS/RawSorter' --inspect '/path/to/source-a' '/path/to/source-b'
```

`RAW_TEST_SOURCE_A`、`RAW_TEST_SOURCE_B` 可让测试脚本使用本地原片，但部分回归断言固定使用项目原始样本的时间，任意照片可能不满足这些断言。普通素材检查建议使用上面的 `--inspect`。

## 许可与反馈

项目源代码使用 [MIT License](LICENSE)。内含 ExifTool 的版权、原有许可和源码获取方式见 [第三方声明](THIRD_PARTY_NOTICES.md)。

问题请提交 [Issue](https://github.com/jaminliu89/raw-sorter/issues)，附 macOS 版本、相机型号、文件系统与脱敏错误。不要公开上传私人照片、完整机身序列号或带个人路径的日志。
