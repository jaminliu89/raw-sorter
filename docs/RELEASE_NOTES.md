默认恢复 A／B 双机位：自动识别两个来源或分别选择 A、B，各自校时，统一排序与独占复制。

保留多机位文件夹模式，以及逐张读取序列号、跨目录合并同一相机的模式。无序列号按来源保留，同名照片全部保留。

安装：下载 DMG，拖入 Applications。适用于 Apple Silicon、macOS 26 及以上。包内包含 ExifTool，无需 Homebrew、Python 或 Node。

安装包使用 ad-hoc 临时签名，尚未经 Apple 公证；macOS 可能提示无法验证开发者。请先确认来源与 SHA256SUMS.txt。

CI 使用自动生成的 TIFF/EXIF 样本验证元数据与文件处理，不包含用户照片。实拍 Sony ARW 与 ExFAT 的验证范围见 README。
