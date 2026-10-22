# 第三方组件

RAW 汇集自身源代码使用 MIT License，见 LICENSE。

应用内包含 Phil Harvey 的 ExifTool 13.55 脚本与 Perl 模块。
ExifTool 按其原有许可分发：与 Perl 相同的许可条款，可选择 Artistic License 或 GNU GPL。
上游完整 LICENSE 原文随安装包保存在 `RAW 汇集.app/Contents/Resources/exiftool/LICENSE`。
ExifTool 的模块版权注释原样保留；项目自身的 MIT License 不替代第三方许可。

上游项目：https://github.com/exiftool/exiftool

构建时使用固定标签 13.55 的源码归档，并检查 SHA-256：
`5c9d422ad128fab728aacc5cc0aa77095d14cde74931389dd961d3d720e6b316`。

ExifTool 通过 macOS 系统自带的 `/usr/bin/perl` 执行。用户无需安装 Homebrew、Python 或 Node。
