import AppKit
import Foundation

final class CameraRow {
    var key = ""
    var sources: [String] = []
    let name: NSTextField
    let path: NSTextField
    let offset: NSTextField
    let choose = NSButton(title: "选择…", target: nil, action: nil)
    let remove = NSButton(title: "移除", target: nil, action: nil)
    init(name: String, path: String, offset: String = "0") {
        self.name = NSTextField(string: name); self.path = NSTextField(string: path); self.offset = NSTextField(string: offset)
    }
    var saved: [String: String] { ["name": name.stringValue, "path": path.stringValue, "offset": offset.stringValue, "key": key, "sources": sources.joined(separator: "\n")] }
}

final class CameraList: NSView {
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        // 初次挂到 NSClipView 时 autoresizing 会把文档初始宽度再加一遍，必须对齐实际可视宽度。
        let width = enclosingScrollView?.contentSize.width ?? bounds.width
        if frame.width != width { setFrameSize(NSSize(width: width, height: frame.height)) }
        for (i, row) in subviews.enumerated() { row.frame = NSRect(x: 8, y: CGFloat(i) * 42 + 6, width: max(0, width - 16), height: 32) }
    }
}

final class CameraRowView: NSView {
    override func layout() {
        super.layout()
        let widths: [CGFloat] = [85, max(100, bounds.width - 391), 70, 46, 90, 60]
        var x: CGFloat = 0
        for (i, view) in subviews.enumerated() { view.frame = NSRect(x: x, y: 3, width: widths[i], height: 26); x += widths[i] + 8 }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    var window: NSWindow!
    let photoRoot = NSTextField(string: UserDefaults.standard.string(forKey: "photoRoot") ?? "")
    var cameras: [CameraRow] = []
    let cameraList = CameraList(frame: NSRect(x: 0, y: 0, width: 1060, height: 132))
    let addButton = NSButton(title: "添加机位", target: nil, action: nil)
    let grouping = NSSegmentedControl(labels: ["A／B 双机位", "多机位 · 文件夹", "多机位 · 序列号"], trackingMode: .selectOne, target: nil, action: nil)
    var bySerial: Bool { grouping.selectedSegment == 2 }
    var dualCamera: Bool { grouping.selectedSegment == 0 }
    let saveParent = NSTextField(string: UserDefaults.standard.string(forKey: "saveParent") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures").path)
    let folderName = NSTextField(string: UserDefaults.standard.string(forKey: "folderName") ?? "RAW_汇总")
    let outputPath = NSTextField(wrappingLabelWithString: "")
    let identifyButton = NSButton(title: "识别此目录", target: nil, action: nil)
    let status = NSTextField(wrappingLabelWithString: "选择来源文件夹，点击「读取并预览」。原片始终保留。")
    let summary = NSTextField(labelWithString: "尚未读取照片")
    let table = NSTableView()
    let progress = NSProgressIndicator()
    let scanButton = NSButton(title: "读取并预览", target: nil, action: nil)
    let copyButton = NSButton(title: "复制并校验", target: nil, action: nil)
    let stopButton = NSButton(title: "停止", target: nil, action: nil)
    let revealButton = NSButton(title: "打开汇总文件夹", target: nil, action: nil)
    var chooseButtons: [NSButton] = []
    var result: ScanResult?
    var stop = StopFlag()
    var busy = false
    var completed: URL?

    func label(_ text: String, size: CGFloat = 13, color: NSColor = .secondaryLabelColor) -> NSTextField {
        let v = NSTextField(wrappingLabelWithString: text); v.font = .systemFont(ofSize: size); v.textColor = color; return v
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu(), item = NSMenuItem(); menu.addItem(item)
        let submenu = NSMenu(); submenu.addItem(withTitle: "退出 RAW 汇集", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); item.submenu = submenu
        let edit = NSMenuItem(); menu.addItem(edit); edit.submenu = NSMenu(title: "编辑")
        for (title, action, key) in [("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a"), ("剪切", "cut:", "x")] {
            edit.submenu?.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 960), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "RAW 汇集 · 多机位照片排序"; window.minSize = NSSize(width: 1000, height: 860)
        window.delegate = self; window.center()
        window.backgroundColor = NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.94, alpha: 1)
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!; content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30), stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 25), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -25)])
        let title = label("让所有机位，回到同一条时间线。", size: 26, color: .labelColor)
        title.font = .systemFont(ofSize: 26, weight: .semibold); stack.addArrangedSubview(title)
        stack.addArrangedSubview(label("本机读取元数据 · 精确排序预览 · 只复制，不移动原片"))
        identifyButton.bezelStyle = .rounded; identifyButton.target = self; identifyButton.action = #selector(identifyRoot)
        let rootRow = folderRow("照片主目录", field: photoRoot, tag: 3)
        let rootControls = NSStackView(views: [photoRoot, identifyButton]); rootControls.spacing = 8
        let nameHint = label("仅新建，不覆盖已有目录", size: 11)
        let grid = NSGridView(views: [[rootRow[0], rootControls, rootRow[2]], folderRow("保存位置", field: saveParent, tag: 2), [label("新文件夹名", color: .labelColor), folderName, nameHint]])
        grid.rowSpacing = 10; grid.columnSpacing = 12; grid.xPlacement = .fill; grid.yPlacement = .center
        grid.column(at: 0).width = 84; grid.column(at: 2).width = 140
        stack.addArrangedSubview(grid); grid.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        outputPath.font = .systemFont(ofSize: 12); outputPath.textColor = .secondaryLabelColor
        outputPath.maximumNumberOfLines = 2; stack.addArrangedSubview(outputPath); outputPath.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        addButton.bezelStyle = .rounded; addButton.target = self; addButton.action = #selector(addCamera)
        grouping.selectedSegment = 0
        grouping.target = self; grouping.action = #selector(changeGrouping)
        stack.addArrangedSubview(grouping)
        let cameraHeader = NSStackView(views: [label("机位列表 · 标识 / RAW 来源 / 偏移秒数", size: 14, color: .labelColor), addButton]); cameraHeader.spacing = 20
        stack.addArrangedSubview(cameraHeader)
        let cameraScroll = NSScrollView(); cameraScroll.hasVerticalScroller = true; cameraScroll.borderType = .bezelBorder
        cameraList.autoresizingMask = [.width]; cameraScroll.documentView = cameraList
        stack.addArrangedSubview(cameraScroll); cameraScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        cameraScroll.heightAnchor.constraint(equalToConstant: 136).isActive = true
        stack.addArrangedSubview(label("常用 A／B 双机位默认打开；更多相机可切换多机位模式。各机位独立校时，正数调晚、负数调早，只影响排序与命名。", size: 12))
        if let saved = UserDefaults.standard.array(forKey: "cameraSources") as? [[String: String]], !saved.isEmpty {
            cameras = saved.map { CameraRow(name: $0["name"] ?? "", path: $0["path"] ?? "", offset: $0["offset"] ?? "0") }
        } else {
            cameras = [CameraRow(name: "A", path: ""), CameraRow(name: "B", path: "")]
        }
        renderCameras()
        for f in [photoRoot, saveParent, folderName] { f.delegate = self; f.font = .systemFont(ofSize: 13) }
        stack.addArrangedSubview(label("按拍摄时间＋亚秒排序，输出统一为 +08:00。缺时区时按 +08:00 解释；缺亚秒时会明确标记，同时间不推断真实先后。", size: 12))
        let actions = NSStackView(views: [scanButton, copyButton, stopButton, revealButton]); actions.spacing = 12
        for b in [scanButton, copyButton, stopButton, revealButton] { b.bezelStyle = .rounded; b.target = self }
        scanButton.action = #selector(scan); copyButton.action = #selector(copyPhotos); stopButton.action = #selector(cancel); revealButton.action = #selector(reveal)
        scanButton.keyEquivalent = "\r"; copyButton.isEnabled = false; stopButton.isEnabled = false; revealButton.isEnabled = false
        stack.addArrangedSubview(actions)
        summary.font = .systemFont(ofSize: 14, weight: .medium); stack.addArrangedSubview(summary)
        let columns: [(String, String, CGFloat)] = [("source", "原文件名", 190), ("camera", "机位", 90), ("time", "排序时间（+08:00）", 270), ("target", "汇总后的文件名", 430)]
        for (id, title, width) in columns { let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); c.title = title; c.width = width; table.addTableColumn(c) }
        table.dataSource = self; table.delegate = self; table.rowHeight = 30; table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.borderType = .bezelBorder
        stack.addArrangedSubview(scroll); scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true; scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        progress.style = .bar; progress.isIndeterminate = false; progress.minValue = 0; progress.maxValue = 1
        stack.addArrangedSubview(progress); progress.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        status.font = .systemFont(ofSize: 12); status.maximumNumberOfLines = 3
        stack.addArrangedSubview(status); status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.addArrangedSubview(label("命名：000001_日期_时间_亚秒_A_原文件名.ARW　　复制后读取目标文件，逐张核对 SHA-256。", size: 11))
        refreshOutput()
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if !photoRoot.stringValue.isEmpty { identifyRoot() }
    }
    func folderRow(_ title: String, field: NSTextField, tag: Int) -> [NSView] {
        let b = NSButton(title: tag == 3 ? "选择并识别…" : "选择…", target: self, action: #selector(choose(_:))); b.tag = tag; b.bezelStyle = .rounded; chooseButtons.append(b)
        return [label(title, color: .labelColor), field, b]
    }
    func controlTextDidChange(_ obj: Notification) {
        guard !busy else { return }
        if let field = obj.object as? NSTextField, field === saveParent || field === folderName {
            completed = nil; refreshOutput(); setBusy(false); return
        }
        if let field = obj.object as? NSTextField, cameras.contains(where: { $0.name === field || $0.path === field || $0.offset === field }) { saveCameras() }
        result = nil; copyButton.isEnabled = false
        summary.stringValue = "设置已变化，请重新读取并预览"; table.reloadData()
    }
    func saveCameras() {
        let values = cameras.map(\.saved)
        UserDefaults.standard.set(values, forKey: "cameraSources")
        if bySerial {
            var serialProfiles = UserDefaults.standard.dictionary(forKey: "serialProfiles") as? [String: [String: String]] ?? [:]
            for row in cameras where !row.key.isEmpty { serialProfiles[row.key] = ["name": row.name.stringValue, "offset": row.offset.stringValue] }
            UserDefaults.standard.set(serialProfiles, forKey: "serialProfiles")
            return
        }
        var profiles = UserDefaults.standard.dictionary(forKey: "cameraProfiles") ?? [:]
        profiles[Engine.canonical(photoRoot.stringValue).path] = values
        UserDefaults.standard.set(profiles, forKey: "cameraProfiles")
    }
    func nextCameraName() -> String {
        let used = Set(cameras.map { $0.name.stringValue.lowercased() }); var index = 0
        while used.contains(Engine.cameraCode(index).lowercased()) { index += 1 }
        return Engine.cameraCode(index)
    }
    func renderCameras() {
        cameraList.subviews.forEach { $0.removeFromSuperview() }
        cameraList.setFrameSize(NSSize(width: cameraList.frame.width, height: CGFloat(max(3, cameras.count)) * 42))
        for (i, camera) in cameras.enumerated() {
            for field in [camera.name, camera.path, camera.offset] { field.delegate = self; field.font = .systemFont(ofSize: 13) }
            camera.name.setAccessibilityLabel("第\(i + 1)行机位标识")
            camera.path.setAccessibilityLabel("第\(i + 1)行 RAW 来源")
            camera.offset.setAccessibilityLabel("第\(i + 1)行偏移秒数")
            camera.path.placeholderString = "选择这个机位的 RAW 文件夹"
            camera.path.setContentHuggingPriority(.defaultLow, for: .horizontal)
            camera.path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            camera.choose.bezelStyle = .rounded; camera.choose.target = self; camera.choose.action = #selector(chooseCamera(_:))
            camera.remove.bezelStyle = .rounded; camera.remove.target = self; camera.remove.action = #selector(removeCamera(_:))
            let row = CameraRowView()
            for view in [camera.name, camera.path, camera.choose, label("偏移秒"), camera.offset, camera.remove] { view.translatesAutoresizingMaskIntoConstraints = true; row.addSubview(view) }
            cameraList.addSubview(row)
            camera.path.isEditable = !bySerial; camera.path.toolTip = camera.sources.joined(separator: "\n")
            camera.name.isEditable = !dualCamera
            camera.choose.title = bySerial ? "来源…" : "选择…"
            camera.remove.isEnabled = !bySerial
            camera.remove.isHidden = dualCamera
        }
        cameraList.needsLayout = true
        addButton.title = bySerial ? "添加来源…" : "添加机位"
        addButton.isHidden = dualCamera
    }
    @objc func changeGrouping() {
        if photoRoot.stringValue.isEmpty {
            cameras = [CameraRow(name: "A", path: ""), CameraRow(name: "B", path: "")]; renderCameras(); invalidate(); return
        }
        identifyRoot()
    }
    @objc func addCamera() {
        guard !busy else { return }
        if bySerial {
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true; panel.title = "添加 RAW 来源，按相机身份归组"
            if panel.runModal() == .OK { identifySources(Array(Set(cameras.flatMap(\.sources) + panel.urls.map(\.path))).sorted()) }
        } else { cameras.append(CameraRow(name: nextCameraName(), path: "")); renderCameras(); invalidate(); saveCameras() }
    }
    @objc func removeCamera(_ sender: NSButton) {
        guard !busy, let i = cameras.firstIndex(where: { $0.remove === sender }) else { return }
        cameras.remove(at: i); renderCameras(); invalidate(); saveCameras()
    }
    @objc func chooseCamera(_ sender: NSButton) {
        guard !busy, let camera = cameras.first(where: { $0.choose === sender }) else { return }
        if bySerial { alert("相机来源与身份", camera.path.stringValue + "\n\n" + camera.sources.joined(separator: "\n")); return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.title = "选择机位 \(camera.name.stringValue) 的 RAW 文件夹"
        if !camera.path.stringValue.isEmpty { panel.directoryURL = Engine.canonical(camera.path.stringValue) }
        if panel.runModal() == .OK, let url = panel.url { camera.path.stringValue = url.path; camera.offset.stringValue = "0"; invalidate(); saveCameras() }
    }
    func refreshOutput() {
        do {
            let url = try Engine.outputURL(parent: saveParent.stringValue, name: folderName.stringValue)
            outputPath.stringValue = "将保存到：" + url.path + (FileManager.default.fileExists(atPath: url.path) ? "（目录已存在，请换一个新名称）" : "")
            UserDefaults.standard.set(saveParent.stringValue, forKey: "saveParent")
            UserDefaults.standard.set(folderName.stringValue, forKey: "folderName")
        } catch { outputPath.stringValue = error.localizedDescription }
    }
    @objc func identifyRoot() {
        guard !busy else { return }
        let path = photoRoot.stringValue
        let serial = bySerial
        let excluded = (try? Engine.outputURL(parent: saveParent.stringValue, name: folderName.stringValue)).map { [$0] } ?? []
        stop = StopFlag(); let flag = stop; invalidate(); setBusy(true); status.stringValue = "正在识别主目录中的 RAW 文件夹…"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let found = try Engine.discover(root: path, excluding: excluded, allowDirectRAW: serial, stop: flag)
                DispatchQueue.main.async {
                    UserDefaults.standard.set(path, forKey: "photoRoot")
                    if self.bySerial { self.setBusy(false); self.identifySources(found.candidates.map { $0.url.path }); return }
                    if !found.candidates.isEmpty {
                        if self.dualCamera && found.candidates.count != 2 {
                            self.cameras = [CameraRow(name: "A", path: ""), CameraRow(name: "B", path: "")]; self.renderCameras()
                            self.summary.stringValue = "发现 \(found.candidates.count) 个来源，A／B 模式需要两个来源"
                            self.status.stringValue = "请手动选择 A、B，或切换「多机位」以保留全部来源。未自动忽略任何来源。"
                            self.setBusy(false); return
                        }
                        let profiles = UserDefaults.standard.dictionary(forKey: "cameraProfiles") ?? [:]
                        let saved = profiles[Engine.canonical(path).path] as? [[String: String]]
                        let prior = saved?.map { CameraRow(name: $0["name"] ?? "", path: $0["path"] ?? "", offset: $0["offset"] ?? "0") } ?? self.cameras
                        var identified: [CameraRow] = []
                        let candidates = Dictionary(found.candidates.map { ($0.url.path, $0) }, uniquingKeysWith: { first, _ in first })
                        for row in prior where !row.path.stringValue.isEmpty {
                            if candidates[Engine.canonical(row.path.stringValue).path] != nil, !identified.contains(where: { Engine.canonical($0.path.stringValue).path == Engine.canonical(row.path.stringValue).path }) { identified.append(row) }
                        }
                        for candidate in found.candidates where !identified.contains(where: { Engine.canonical($0.path.stringValue).path == candidate.url.path }) {
                            var n = 0
                            while identified.contains(where: { $0.name.stringValue.lowercased() == Engine.cameraCode(n).lowercased() }) { n += 1 }
                            identified.append(CameraRow(name: Engine.cameraCode(n), path: candidate.url.path))
                        }
                        if self.dualCamera { for (i, row) in identified.enumerated() { row.name.stringValue = Engine.cameraCode(i) } }
                        self.cameras = identified; self.renderCameras(); self.saveCameras()
                        self.summary.stringValue = "发现 \(identified.count) 个机位，共 \(found.candidates.reduce(0) { $0 + $1.count }) 张 RAW"
                        self.status.stringValue = "已列出全部 RAW 来源，请核对机位标识与偏移后读取预览。" + (found.skipped.isEmpty ? "" : "已跳过汇总目录：" + found.skipped.joined(separator: "、"))
                    } else {
                        self.cameras = self.dualCamera ? [CameraRow(name: "A", path: ""), CameraRow(name: "B", path: "")] : []; self.renderCameras()
                        self.summary.stringValue = "没有识别到 RAW 来源"
                        self.status.stringValue = "请重新选择主目录，或点击「添加机位」手动选择来源。"
                    }
                    self.setBusy(false)
                }
            } catch { DispatchQueue.main.async { self.cameras = self.dualCamera ? [CameraRow(name: "A", path: ""), CameraRow(name: "B", path: "")] : []; self.renderCameras(); self.status.stringValue = error.localizedDescription; self.summary.stringValue = "自动识别未完成，可重新选择主目录或手动选择来源"; self.setBusy(false) } }
        }
    }
    func identifySources(_ paths: [String]) {
        guard !paths.isEmpty else { cameras = []; renderCameras(); invalidate(); status.stringValue = "没有找到 RAW 来源，请添加来源或重新选择主目录"; return }
        let prior = cameras
        let profiles = UserDefaults.standard.dictionary(forKey: "serialProfiles") as? [String: [String: String]] ?? [:]
        stop = StopFlag(); let flag = stop; invalidate(); setBusy(true)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let value = try Engine.scan(paths: paths, offsets: paths.map { _ in 0 }, groupBySerial: true, stop: flag) { message in DispatchQueue.main.async { self.status.stringValue = "识别相机身份：" + message } }
                guard value.invalid == 0, value.warnings.isEmpty else { throw ToolError("来源读取不完整，无法安全归组：" + (value.photos.first(where: { !$0.error.isEmpty })?.error ?? value.warnings.joined(separator: "；"))) }
                let groups = Dictionary(grouping: value.photos, by: \.groupKey)
                DispatchQueue.main.async {
                    var rows: [CameraRow] = []
                    for key in groups.keys.sorted() where !key.isEmpty {
                        let photos = groups[key]!, sample = photos[0]
                        let old = prior.first { $0.key == key }
                        let saved = profiles[key]
                        var name = old?.name.stringValue ?? saved?["name"] ?? Engine.cameraCode(rows.count)
                        if rows.contains(where: { $0.name.stringValue.lowercased() == name.lowercased() }) { var n = 0; while rows.contains(where: { $0.name.stringValue.lowercased() == Engine.cameraCode(n).lowercased() }) { n += 1 }; name = Engine.cameraCode(n) }
                        let sources = paths.filter { path in photos.contains { Engine.inside($0.url, Engine.canonical(path)) } }
                        let description = sample.model + " · " + (sample.serial.isEmpty ? "无序列号，按来源保留" : "序列号 " + sample.serial) + " · \(sources.count) 个来源 / \(photos.count) 张"
                        let row = CameraRow(name: name, path: description, offset: old?.offset.stringValue ?? saved?["offset"] ?? "0"); row.key = key; row.sources = sources; rows.append(row)
                    }
                    self.cameras = rows; self.renderCameras(); self.saveCameras(); self.setBusy(false)
                    self.summary.stringValue = "\(paths.count) 个来源 → \(rows.count) 个相机身份，共 \(value.photos.count) 张 RAW"
                    self.status.stringValue = "已逐张读取身份。同一序列号共享名称与偏移；无序列号按来源保留。请核对后读取预览。" + (value.invalid > 0 ? "有 \(value.invalid) 张元数据异常，预览将阻止复制。" : "")
                }
            } catch { DispatchQueue.main.async { self.setBusy(false); self.result = nil; self.cameras = []; self.renderCameras(); self.summary.stringValue = "相机身份识别未完成"; self.status.stringValue = error.localizedDescription } }
        }
    }
    @objc func choose(_ sender: NSButton) {
        if sender.tag == 2 {
            let panel = NSOpenPanel(); panel.title = "选择保存位置（汇总文件夹将建在这里）"
            panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
            panel.directoryURL = Engine.canonical(saveParent.stringValue)
            if panel.runModal() == .OK, let url = panel.url { saveParent.stringValue = url.path; completed = nil; refreshOutput(); setBusy(false) }
        } else if sender.tag == 3 {
            let panel = NSOpenPanel(); panel.title = "选择包含各机位 RAW 文件夹的主目录"
            panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
            panel.directoryURL = Engine.canonical(photoRoot.stringValue)
            if panel.runModal() == .OK, let url = panel.url { photoRoot.stringValue = url.path; identifyRoot() }
        }
    }
    func invalidate() { result = nil; copyButton.isEnabled = false; table.reloadData(); summary.stringValue = "设置已变化，请重新读取并预览" }
    func setBusy(_ value: Bool) {
        busy = value; scanButton.isEnabled = !value; stopButton.isEnabled = value
        let target = try? Engine.outputURL(parent: saveParent.stringValue, name: folderName.stringValue)
        let validTarget = target.map { !FileManager.default.fileExists(atPath: $0.path) } ?? false
        copyButton.isEnabled = !value && validTarget && result != nil && result!.invalid == 0 && result!.warnings.isEmpty && completed == nil
        identifyButton.isEnabled = !value
        addButton.isEnabled = !value
        grouping.isEnabled = !value
        for field in [photoRoot, saveParent, folderName] { field.isEnabled = !value }
        for row in cameras { for field in [row.name, row.path, row.offset] { field.isEnabled = !value }; row.choose.isEnabled = !value; row.remove.isEnabled = !value && !bySerial }
        for b in chooseButtons { b.isEnabled = !value }
        revealButton.isEnabled = !value && completed != nil
    }
    func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.addButton(withTitle: "知道了"); a.runModal()
    }
    @objc func scan() {
        if dualCamera && cameras.count != 2 { alert("A／B 双机位", "请分别选择 A 和 B 两个来源文件夹。"); return }
        let offsets = cameras.compactMap { Double($0.offset.stringValue) }
        guard !cameras.isEmpty, offsets.count == cameras.count, offsets.allSatisfy(\.isFinite) else { alert("机位或偏移格式有误", "至少添加一个机位，各机位偏移请输入有效秒数，例如 0、2 或 -0.5。"); return }
        window.makeFirstResponder(nil)
        let serial = bySerial
        let paths = serial ? Array(Set(cameras.flatMap(\.sources))).sorted() : cameras.map { $0.path.stringValue }
        let labels = cameras.map { $0.name.stringValue }
        let settings = Dictionary(cameras.enumerated().map { ($0.element.key, CameraSetting(name: $0.element.name.stringValue, offset: offsets[$0.offset])) }, uniquingKeysWith: { first, _ in first })
        saveCameras()
        stop = StopFlag(); let flag = stop; result = nil; completed = nil; table.reloadData(); progress.doubleValue = 0
        setBusy(true); status.stringValue = "正在扫描 RAW 文件…"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let value = try Engine.scan(paths: paths, offsets: serial ? paths.map { _ in 0 } : offsets, labels: serial ? nil : labels, groupBySerial: serial, cameraSettings: serial ? settings : [:], stop: flag) { message in DispatchQueue.main.async { self.status.stringValue = message } }
                DispatchQueue.main.async {
                    self.result = value; self.table.reloadData(); self.progress.doubleValue = 1
                    let precise = value.photos.filter { $0.subsecondDigits > 0 && $0.error.isEmpty }.count
                    self.summary.stringValue = "\(labels.count) 个机位　·　\(value.photos.count) 张 RAW　·　\(ByteCountFormatter.string(fromByteCount: value.totalBytes, countStyle: .file))　·　\(precise) 张有亚秒　·　\(value.invalid) 张读取异常"
                    let assumed = value.photos.filter(\.inferredZone).count
                    let counts = Dictionary(grouping: value.photos, by: \.camera)
                    let breakdown = labels.map { "\($0)：\(counts[$0]?.count ?? 0) 张" }.joined(separator: "；")
                    self.status.stringValue = value.warnings.isEmpty ? "\(breakdown)。\(assumed) 张缺时区，按 +08:00 解释。确认顺序后复制。" : value.warnings.joined(separator: "；")
                    self.setBusy(false)
                }
            } catch { DispatchQueue.main.async { self.status.stringValue = error.localizedDescription; self.summary.stringValue = "未完成预览"; self.setBusy(false) } }
        }
    }
    @objc func copyPhotos() {
        guard let value = result else { return }
        let path: String
        do { path = try Engine.outputURL(parent: saveParent.stringValue, name: folderName.stringValue).path }
        catch { alert("保存位置有误", error.localizedDescription); return }
        let a = NSAlert(); a.messageText = "复制 \(value.photos.count) 张 RAW 到新文件夹？"
        let counts = Dictionary(grouping: value.photos, by: \.camera)
        let breakdown = counts.keys.sorted().map { "\($0)：\(counts[$0]!.count) 张" }.joined(separator: "；")
        a.informativeText = "目标：\(path)\n机位：\(breakdown)\n预计占用：\(ByteCountFormatter.string(fromByteCount: value.totalBytes, countStyle: .file))\n只复制，不修改原片。目标文件夹必须尚不存在；逐张校验 SHA-256。"
        a.addButton(withTitle: "开始复制"); a.addButton(withTitle: "取消")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        stop = StopFlag(); let flag = stop; setBusy(true); progress.doubleValue = 0
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let root = try Engine.copy(value, destination: path, stop: flag) { fraction, message in DispatchQueue.main.async { self.progress.doubleValue = fraction; self.status.stringValue = message } }
                DispatchQueue.main.async { self.completed = root; self.setBusy(false); self.alert("复制与校验完成", "\(value.photos.count) 张 RAW 的 SHA-256 全部一致。原片保留。\n校验记录已保存在汇总目录。") }
            } catch { DispatchQueue.main.async { self.status.stringValue = error.localizedDescription; self.setBusy(false); self.alert("任务未完成", error.localizedDescription + "\n已生成文件保留，详情见目标目录中的排序与校验记录。再次执行请使用新的汇总目录。") } }
        }
    }
    @objc func cancel() { stop.cancel(); status.stringValue = "正在安全停止，请稍候…"; stopButton.isEnabled = false }
    @objc func reveal() { if let completed { NSWorkspace.shared.open(completed) } }
    func numberOfRows(in tableView: NSTableView) -> Int { result?.photos.count ?? 0 }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let photo = result?.photos[row] else { return nil }
        let value: String
        switch tableColumn?.identifier.rawValue {
        case "source": value = photo.url.lastPathComponent
        case "camera": value = photo.camera
        case "time": value = photo.error.isEmpty ? photo.displayTime : photo.error
        default: value = photo.proposed
        }
        let cell = NSTextField(labelWithString: value); cell.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        cell.lineBreakMode = .byTruncatingMiddle; cell.toolTip = value; cell.textColor = photo.error.isEmpty ? .labelColor : .systemRed
        return cell
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if busy { alert("任务正在进行", "请先点击「停止」，等待任务结束后再退出。"); return false }; NSApp.terminate(nil); return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if busy { alert("任务正在进行", "请先点击「停止」，等待任务结束后再退出。"); return .terminateCancel }; return .terminateNow
    }
}

if CommandLine.arguments.contains("--inspect") {
    do {
        let args = CommandLine.arguments
        let i = args.firstIndex(of: "--inspect")!
        let paths = Array(args.dropFirst(i + 1))
        let result = try Engine.scan(paths: paths, offsets: Array(repeating: 0, count: paths.count), stop: StopFlag()) { print($0) }
        print("COUNT=\(result.photos.count) INVALID=\(result.invalid) SUBSECOND=\(result.photos.filter { $0.subsecondDigits > 0 }.count) WARNINGS=\(result.warnings.count)")
        for p in result.photos.prefix(5) { print("\(p.displayTime) -> \(p.proposed) \(p.error)") }
        exit(result.invalid == 0 && result.warnings.isEmpty ? 0 : 1)
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let delegate = AppDelegate(); NSApplication.shared.delegate = delegate; NSApplication.shared.run()
}
