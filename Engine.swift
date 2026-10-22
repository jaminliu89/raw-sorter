import Foundation
import CryptoKit
import Darwin

struct ToolError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    func check() throws {
        lock.lock(); let value = stopped; lock.unlock()
        if value { throw ToolError("任务已停止，已校验文件保留。未完成文件可能使用最终名称或 .partial，未记入校验通过列表的文件不算完成。") }
    }
}

struct Photo {
    let url: URL
    var camera: String
    let bytes: Int64
    let modified: Date
    let identity: UInt64
    var original = ""
    var model = ""
    var serial = ""
    var groupKey = ""
    var error = ""
    var seconds: Int64 = 0
    var nanos: Int64 = 0
    var subsecondDigits = 0
    var inferredZone = false
    var proposed = ""
    var displayTime = ""
}

struct ScanResult {
    var photos: [Photo]
    let roots: [URL]
    let collisionGroups: Int
    let warnings: [String]
    var totalBytes: Int64 { photos.reduce(0) { $0 + $1.bytes } }
    var invalid: Int { photos.filter { !$0.error.isEmpty }.count }
}

struct SourceDiscovery {
    let candidates: [(url: URL, count: Int)]
    let skipped: [String]
}

struct CameraSetting {
    let name: String
    let offset: Double
}

enum Engine {
    static let extensions: Set<String> = ["arw", "cr2", "cr3", "nef", "raf", "dng", "orf", "rw2"]
    static let fm = FileManager.default
    static func cameraCode(_ index: Int) -> String {
        var number = index + 1, code = ""
        repeat { number -= 1; code = String(UnicodeScalar(65 + number % 26)!) + code; number /= 26 } while number > 0
        return code
    }
    static func canonical(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath()
    }
    static func inside(_ child: URL, _ parent: URL) -> Bool {
        child.path == parent.path || child.path.hasPrefix(parent.path + "/")
    }
    static func availableCapacity(important: Int64?, regular: Int64?, filesystem: Int64?) throws -> Int64 {
        // 部分外置盘的 importantUsage 返回 0，不能据此覆盖实际可用容量。
        guard let bytes = [important, regular, filesystem].compactMap({ $0 }).filter({ $0 >= 0 }).max() else {
            throw ToolError("无法确定目标磁盘的剩余空间，请重新选择保存位置")
        }
        return bytes
    }
    static func generatedOutput(_ url: URL) -> Bool {
        let record = url.appendingPathComponent("排序与校验记录.json")
        guard let data = try? Data(contentsOf: record), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["计划文件数"] is NSNumber && object["文件"] is [[String: Any]]
    }
    static func outputURL(parent: String, name: String) throws -> URL {
        let folder = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folder.isEmpty, folder != ".", folder != "..", !folder.contains("/"), !folder.contains("\0"), folder.utf8.count <= 240 else {
            throw ToolError("请输入有效的新文件夹名称，不能包含斜线或使用 .、..")
        }
        let location = canonical(parent)
        var directory: ObjCBool = false
        guard fm.fileExists(atPath: location.path, isDirectory: &directory), directory.boolValue else { throw ToolError("保存位置不存在，请选择一个已有的文件夹") }
        return location.appendingPathComponent(folder)
    }
    static func discover(root path: String, excluding: [URL], allowDirectRAW: Bool = false, stop: StopFlag) throws -> SourceDiscovery {
        let root = canonical(path)
        var directory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue else { throw ToolError("照片主目录不存在，请重新选择") }
        var skipped: [String] = []
        func excluded(_ url: URL) -> Bool {
            if excluding.contains(where: { inside(url, $0) }) { return true }
            // 跳过本工具已生成的汇总目录，避免再次将复制品识别为第三台相机。
            if generatedOutput(url) {
                skipped.append(url.lastPathComponent); return true
            }
            return false
        }
        if excluded(root) { throw ToolError("选择的是汇总输出目录，请选择包含各机位原片的主目录") }
        let children = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey], options: [.skipsHiddenFiles])
        var candidates: [(url: URL, count: Int)] = []
        var directRAW = 0
        for child in children.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            try stop.check()
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
            if values.isSymbolicLink == true { continue }
            if values.isRegularFile == true, extensions.contains(child.pathExtension.lowercased()) { directRAW += 1 }
            guard values.isDirectory == true, !excluded(child) else { continue }
            var count = 0
            var readError: Error?
            guard let files = fm.enumerator(at: child, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey], options: [.skipsHiddenFiles], errorHandler: { _, error in readError = error; return false }) else { throw ToolError("无法读取：\(child.path)") }
            for case let file as URL in files {
                try stop.check()
                let info = try file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
                if info.isSymbolicLink == true { files.skipDescendants(); continue }
                if info.isDirectory == true, excluded(file) { files.skipDescendants(); continue }
                if info.isRegularFile == true, extensions.contains(file.pathExtension.lowercased()) { count += 1 }
            }
            if let readError { throw ToolError("目录读取不完整：\(readError.localizedDescription)") }
            if count > 0 { candidates.append((child, count)) }
        }
        if directRAW > 0, allowDirectRAW { return SourceDiscovery(candidates: [(root, directRAW + candidates.reduce(0) { $0 + $1.count })], skipped: skipped) }
        guard directRAW == 0 else { throw ToolError("主目录本身也含 \(directRAW) 张 RAW，无法自动划分机位。请选择各机位文件夹共同的上一级目录，或手动添加来源。") }
        return SourceDiscovery(candidates: candidates, skipped: skipped)
    }
    static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian); f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = format; f.isLenient = false
        return f
    }
    static func metadata(_ paths: [URL]) throws -> [[String: Any]] {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("exiftool/exiftool").path
        let executable = [bundled, ProcessInfo.processInfo.environment["RAW_EXIFTOOL"], "/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool"].compactMap { $0 }.first { fm.fileExists(atPath: $0) }
        guard let executable else { throw ToolError("未找到 ExifTool，请重新构建包含 ExifTool 的应用。") }
        let p = Process(), out = Pipe(), err = Pipe()
        // 固定禁用用户 ExifTool 配置；参数只读取元数据，不写入原片。
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [executable, "-config", "", "-j", "-api", "structformat=jsonq", "-DateTimeOriginal", "-SubSecTimeOriginal", "-OffsetTimeOriginal", "-Make", "-Model", "-SerialNumber", "-BodySerialNumber", "-InternalSerialNumber", "--"] + paths.map(\.path)
        p.standardOutput = out; p.standardError = err
        // 小批次读取，避免 stderr 管道写满导致子进程阻塞。
        let errorFile = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        fm.createFile(atPath: errorFile.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errorFile)
        p.standardError = errorHandle
        defer { try? errorHandle.close(); try? fm.removeItem(at: errorFile) }
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let result = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !result.isEmpty else {
            let reason = (try? String(contentsOf: errorFile, encoding: .utf8)) ?? ""
            throw ToolError("ExifTool 读取失败：\(reason.prefix(500))")
        }
        return result
    }
    static func applyMetadata(_ raw: [String: Any], to photo: inout Photo, offset: Double) throws {
        func string(_ key: String) -> String { raw[key].map { String(describing: $0) } ?? "" }
        photo.original = string("DateTimeOriginal")
        photo.model = string("Model")
        let dateFormat = formatter("yyyy:MM:dd HH:mm:ss")
        guard let date = dateFormat.date(from: photo.original), dateFormat.string(from: date) == photo.original else {
            throw ToolError("缺失或无效的拍摄时间，不使用文件修改时间替代")
        }
        let sub = string("SubSecTimeOriginal")
        guard sub.isEmpty || (sub.allSatisfy { $0.isASCII && $0.isNumber } && sub.count <= 9) else {
            throw ToolError("无法识别的亚秒值：\(sub)")
        }
        photo.subsecondDigits = sub.count
        var zone = string("OffsetTimeOriginal")
        photo.inferredZone = zone.isEmpty
        if zone.isEmpty { zone = "+08:00" }
        let parts = Array(zone)
        guard parts.count == 6, parts[0] == "+" || parts[0] == "-", parts[3] == ":",
              let hours = Int(String(parts[1...2])), let minutes = Int(String(parts[4...5])), hours <= 14, minutes < 60, hours != 14 || minutes == 0 else {
            throw ToolError("无法识别的时区：\(zone)")
        }
        guard offset.isFinite, abs(offset) <= 86400 * 365 else { throw ToolError("时间偏移请限制在正负 365 天内") }
        let zoneSeconds = Int64((hours * 3600 + minutes * 60) * (parts[0] == "-" ? -1 : 1))
        photo.seconds = Int64(date.timeIntervalSince1970.rounded()) - zoneSeconds
        photo.nanos = Int64(sub.padding(toLength: 9, withPad: "0", startingAt: 0)) ?? 0
        photo.nanos += Int64((offset * 1_000_000_000).rounded())
        photo.seconds += photo.nanos / 1_000_000_000
        photo.nanos %= 1_000_000_000
        if photo.nanos < 0 { photo.seconds -= 1; photo.nanos += 1_000_000_000 }
        let local = Date(timeIntervalSince1970: Double(photo.seconds + 8 * 3600))
        let fraction = String(format: "%09lld", photo.nanos)
        photo.displayTime = formatter("yyyy-MM-dd HH:mm:ss").string(from: local) + (sub.isEmpty ? "（原片无亚秒）" : "." + String(fraction.prefix(max(3, sub.count)))) + " +08:00"
        photo.proposed = formatter("yyyyMMdd_HHmmss").string(from: local) + "_" + fraction + "_" + photo.camera + "_" + photo.url.lastPathComponent
    }
    static func cameraIdentity(_ raw: [String: Any], fallback: String) -> (key: String, serial: String) {
        let make = String(describing: raw["Make"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let model = String(describing: raw["Model"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        for tag in ["BodySerialNumber", "SerialNumber", "InternalSerialNumber"] {
            guard let value = raw[tag] else { continue }
            let serial = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
            if !serial.isEmpty, !["0", "unknown", "n/a", "none"].contains(serial.lowercased()), !serial.allSatisfy({ $0 == "0" }) {
                return ("serial|\(make)|\(model)|\(serial.uppercased())", serial)
            }
        }
        return ("folder|" + fallback, "")
    }
    static func scan(paths: [String], offsets: [Double], labels: [String]? = nil, groupBySerial: Bool = false, cameraSettings: [String: CameraSetting] = [:], stop: StopFlag, progress: @escaping (String) -> Void) throws -> ScanResult {
        guard !paths.isEmpty, offsets.count == paths.count, paths.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw ToolError("请为每个机位选择来源文件夹并填写偏移") }
        let names = labels ?? paths.indices.map { cameraCode($0) }
        guard names.count == paths.count, names.allSatisfy({ !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) && $0 != "." && $0 != ".." && $0.utf8.count <= 60 && !$0.contains(where: { "/\\:\0".contains($0) }) }), Set(names.map { $0.precomposedStringWithCanonicalMapping.lowercased() }).count == names.count else {
            throw ToolError("机位标识需唯一，最长 60 字节，不能含斜线、反斜线、冒号或首尾空格")
        }
        guard offsets.allSatisfy({ $0.isFinite && abs($0) <= 86400 * 365 }) else { throw ToolError("各机位的偏移请填写正负 365 天内的有效秒数") }
        let offsetsByName = Dictionary(uniqueKeysWithValues: zip(names, offsets))
        if groupBySerial, !cameraSettings.isEmpty {
            let settings = Array(cameraSettings.values)
            let labels = settings.map(\.name)
            guard Set(labels.map { $0.precomposedStringWithCanonicalMapping.lowercased() }).count == labels.count,
                  labels.allSatisfy({ !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) && $0 != "." && $0 != ".." && $0.utf8.count <= 60 && !$0.contains(where: { "/\\:\0".contains($0) }) }),
                  settings.allSatisfy({ $0.offset.isFinite && abs($0.offset) <= 86400 * 365 }) else { throw ToolError("相机标识必须唯一且有效，偏移须在正负 365 天内") }
        }
        let roots = paths.map(canonical)
        for i in roots.indices {
            for j in 0..<i {
                guard !inside(roots[i], roots[j]), !inside(roots[j], roots[i]) else { throw ToolError("各机位来源目录不能相同或互相包含") }
            }
        }
        var photos: [Photo] = [], warnings: [String] = []
        for (i, root) in roots.enumerated() {
            let previousCount = photos.count
            var directory: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue else { throw ToolError("来源文件夹不存在：\(root.path)") }
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey], options: [.skipsHiddenFiles], errorHandler: { url, error in
                warnings.append("无法扫描 \(url.path)：\(error.localizedDescription)"); return true
            }) else { throw ToolError("无法扫描：\(root.path)") }
            for case let url as URL in enumerator {
                try stop.check()
                let resource = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
                if resource.isDirectory == true, generatedOutput(url) { enumerator.skipDescendants(); continue }
                guard resource.isSymbolicLink != true, resource.isRegularFile == true, extensions.contains(url.pathExtension.lowercased()) else { continue }
                let attributes = try fm.attributesOfItem(atPath: url.path)
                photos.append(Photo(url: url, camera: names[i], bytes: (attributes[.size] as! NSNumber).int64Value,
                                    modified: attributes[.modificationDate] as! Date, identity: (attributes[.systemFileNumber] as! NSNumber).uint64Value))
            }
            if photos.count == previousCount { warnings.append("机位 \(names[i]) 未找到 RAW，请检查来源或移除该空机位") }
        }
        guard !photos.isEmpty else { throw ToolError("所选机位中没有找到 RAW 文件") }
        photos.sort { $0.url.path < $1.url.path }
        let groups = Dictionary(grouping: photos, by: { $0.url.lastPathComponent.lowercased() })
        var serialNames: [String: String] = [:]
        for start in stride(from: 0, to: photos.count, by: 60) {
            try stop.check()
            let end = min(start + 60, photos.count)
            progress("读取拍摄时间 \(start) / \(photos.count)…")
            let values = try metadata(Array(photos[start..<end]).map(\.url))
            let mapped = Dictionary(values.compactMap { r -> (String, [String: Any])? in
                guard let path = r["SourceFile"] as? String else { return nil }; return (path, r)
            }, uniquingKeysWith: { first, _ in first })
            for index in start..<end {
                do {
                    guard let raw = mapped[photos[index].url.path], raw["Error"] == nil else { throw ToolError("无法读取此 RAW 的元数据") }
                    var offset = offsetsByName[photos[index].camera]!
                    if groupBySerial {
                        let root = roots.first(where: { inside(photos[index].url, $0) })!
                        let identity = cameraIdentity(raw, fallback: root.path)
                        photos[index].groupKey = identity.key; photos[index].serial = identity.serial
                        if !cameraSettings.isEmpty, cameraSettings[identity.key] == nil { throw ToolError("发现新的相机身份，请重新识别来源后预览") }
                        if serialNames[identity.key] == nil { serialNames[identity.key] = cameraCode(serialNames.count) }
                        photos[index].camera = cameraSettings[identity.key]?.name ?? serialNames[identity.key]!
                        offset = cameraSettings[identity.key]?.offset ?? 0
                    }
                    try applyMetadata(raw, to: &photos[index], offset: offset)
                } catch { photos[index].error = error.localizedDescription }
            }
        }
        photos.sort {
            if $0.error.isEmpty != $1.error.isEmpty { return $0.error.isEmpty }
            if $0.seconds != $1.seconds { return $0.seconds < $1.seconds }
            if $0.nanos != $1.nanos { return $0.nanos < $1.nanos }
            return $0.url.path < $1.url.path
        }
        for i in photos.indices where photos[i].error.isEmpty {
            // 连续序号保证 Finder 按名称时顺序一致；同一时间按来源路径稳定排序。
            photos[i].proposed = String(format: "%06d_", i + 1) + photos[i].proposed
            if photos[i].proposed.utf8.count > 240 { photos[i].error = "生成的文件名过长，请缩短原文件名后重新预览" }
        }
        return ScanResult(photos: photos, roots: roots, collisionGroups: groups.values.filter { $0.count > 1 }.count, warnings: warnings)
    }
    static func signatureMatches(_ photo: Photo) throws -> Bool {
        let resource = try photo.url.resourceValues(forKeys: [.isSymbolicLinkKey])
        let a = try fm.attributesOfItem(atPath: photo.url.path)
        return resource.isSymbolicLink != true && (a[.size] as? NSNumber)?.int64Value == photo.bytes && (a[.modificationDate] as? Date) == photo.modified && (a[.systemFileNumber] as? NSNumber)?.uint64Value == photo.identity
    }
    static func digest(_ url: URL, stop: StopFlag) throws -> String {
        let f = try FileHandle(forReadingFrom: url); defer { try? f.close() }
        var hash = SHA256()
        while true {
            let read = try autoreleasepool { () throws -> Bool in
                try stop.check()
                guard let data = try f.read(upToCount: 4 * 1024 * 1024), !data.isEmpty else { return false }
                hash.update(data: data)
                return true
            }
            if !read { break }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func publishVerified(_ part: URL, destination: URL, expectedHash: String, stop: StopFlag) throws {
        try stop.check()
        if renamex_np(part.path, destination.path, UInt32(RENAME_EXCL)) == 0 { return }
        let code = errno
        guard [ENOTSUP, ENOSYS, EINVAL].contains(code) else {
            if code == EEXIST { throw ToolError("目标文件已存在，未覆盖：\(destination.lastPathComponent)") }
            throw ToolError("安全重命名失败，未覆盖：\(destination.lastPathComponent)；errno \(code)：\(String(cString: strerror(code)))")
        }
        // ExFAT 不支持 RENAME_EXCL。绝不降级到可能覆盖的普通 rename，
        // 而是原子独占创建最终目标，再复制已校验临时文件并独立复核哈希。
        let fd = Darwin.open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else {
            let failure = errno
            if failure == EEXIST { throw ToolError("目标文件已存在，未覆盖：\(destination.lastPathComponent)") }
            throw ToolError("无法创建兼容写入目标，未覆盖：\(destination.lastPathComponent)；errno \(failure)：\(String(cString: strerror(failure)))")
        }
        let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? output.close() }
        do {
            let input = try FileHandle(forReadingFrom: part)
            defer { try? input.close() }
            var hash = SHA256()
            while true {
                let read = try autoreleasepool { () throws -> Bool in
                    try stop.check()
                    guard let data = try input.read(upToCount: 4 * 1024 * 1024), !data.isEmpty else { return false }
                    try output.write(contentsOf: data); hash.update(data: data)
                    return true
                }
                if !read { break }
            }
            try output.synchronize(); try output.close()
            let copiedHash = hash.finalize().map { String(format: "%02x", $0) }.joined()
            guard copiedHash == expectedHash, try digest(destination, stop: stop) == expectedHash else {
                throw ToolError("兼容写入的 SHA-256 校验不一致")
            }
            // 仅在最终文件复核一致后，清理本任务创建的临时副本；不删除原片。
            try fm.removeItem(at: part)
        } catch {
            throw ToolError("兼容写入未完成：\(error.localizedDescription)\n保留了 .partial；最终名称文件也可能不完整，只有校验记录中标为一致的文件才算完成。")
        }
    }
    static func supportsExclusiveRename(in root: URL) throws -> Bool {
        let source = root.appendingPathComponent(".raw-sorter-probe-" + UUID().uuidString)
        let target = source.appendingPathExtension("renamed")
        let fd = Darwin.open(source.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw ToolError("无法检查目标磁盘的写入能力") }
        Darwin.close(fd)
        defer { try? fm.removeItem(at: source); try? fm.removeItem(at: target) }
        if renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0 { return true }
        let code = errno
        if [ENOTSUP, ENOSYS, EINVAL].contains(code) { return false }
        throw ToolError("目标磁盘能力检查失败；errno \(code)：\(String(cString: strerror(code)))")
    }
    static func copyOne(_ photo: Photo, destination: URL, stop: StopFlag, exclusiveRename: Bool? = nil, bytesProgress: (Int64) -> Void) throws -> String {
        guard try signatureMatches(photo) else { throw ToolError("来源文件自预览后已变化，请重新预览：\(photo.url.lastPathComponent)") }
        let staged = try exclusiveRename ?? supportsExclusiveRename(in: destination.deletingLastPathComponent())
        // ExFAT 直接 O_EXCL 写入最终名称，避免整份 RAW 再复制一遍。
        // 只有目标重读校验通过后才进入完成记录；异常保留中途文件，不伪报完成。
        let part = staged ? destination.appendingPathExtension("partial") : destination
        let sourceFD = Darwin.open(photo.url.path, O_RDONLY | O_NOFOLLOW)
        guard sourceFD >= 0 else { throw ToolError("无法打开来源文件：\(photo.url.lastPathComponent)") }
        let input = FileHandle(fileDescriptor: sourceFD, closeOnDealloc: true)
        defer { try? input.close() }
        let outputFD = Darwin.open(part.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard outputFD >= 0 else { throw ToolError("目标已存在或不可写，未覆盖：\(part.lastPathComponent)") }
        let output = FileHandle(fileDescriptor: outputFD, closeOnDealloc: true)
        defer { try? output.close() }
        var hash = SHA256(), copied: Int64 = 0
        while true {
            let read = try autoreleasepool { () throws -> Bool in
                try stop.check()
                guard let data = try input.read(upToCount: 4 * 1024 * 1024), !data.isEmpty else { return false }
                try output.write(contentsOf: data); hash.update(data: data)
                copied += Int64(data.count); bytesProgress(copied)
                return true
            }
            if !read { break }
        }
        try output.synchronize(); try output.close()
        guard copied == photo.bytes, try signatureMatches(photo) else { throw ToolError("复制期间来源发生变化，保留中途文件，未记为完成，请重新预览") }
        let sourceHash = hash.finalize().map { String(format: "%02x", $0) }.joined()
        let targetHash = try digest(part, stop: stop)
        guard sourceHash == targetHash else { throw ToolError("校验不一致，保留 .partial 文件：\(photo.url.lastPathComponent)") }
        if staged { try publishVerified(part, destination: destination, expectedHash: sourceHash, stop: stop) }
        try? fm.setAttributes([.modificationDate: photo.modified], ofItemAtPath: destination.path)
        return sourceHash
    }
    static func copy(_ result: ScanResult, destination: String, stop: StopFlag, progress: @escaping (Double, String) -> Void) throws -> URL {
        guard result.invalid == 0, result.warnings.isEmpty else { throw ToolError("预览有读取错误，请先解决，避免遗漏照片") }
        let root = canonical(destination)
        guard !result.roots.contains(where: { inside(root, $0) }) else { throw ToolError("汇总目录不能放在任何来源目录内部") }
        guard !fm.fileExists(atPath: root.path) else { throw ToolError("汇总目录已存在，请换一个新目录；本工具不会覆盖或合并已有目录") }
        let parent = root.deletingLastPathComponent()
        let values = try? parent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let attributes = try? fm.attributesOfFileSystem(forPath: parent.path)
        let available = try availableCapacity(important: values?.volumeAvailableCapacityForImportantUsage,
                                             regular: values?.volumeAvailableCapacity.map { Int64($0) },
                                             filesystem: (attributes?[.systemFreeSize] as? NSNumber)?.int64Value)
        guard available > result.totalBytes + 100 * 1024 * 1024 else { throw ToolError("目标磁盘空间不足，需要约 \(ByteCountFormatter.string(fromByteCount: result.totalBytes, countStyle: .file))") }
        try stop.check()
        // mkdir 是独占创建；已有目录会直接失败，保留用户原有文件。
        guard mkdir(root.path, mode_t(0o700)) == 0 else { throw ToolError("无法创建新汇总目录，可能已存在或没有写入权限") }
        let manifestURL = root.appendingPathComponent("排序与校验记录.json")
        let journalURL = root.appendingPathComponent("逐张校验记录.jsonl")
        let journalFD = Darwin.open(journalURL.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
        guard journalFD >= 0 else { throw ToolError("无法创建逐张校验记录") }
        let journal = FileHandle(fileDescriptor: journalFD, closeOnDealloc: true)
        defer { try? journal.close() }
        var rows: [[String: Any]] = []
        var completedBytes: Int64 = 0
        var currentFile = ""
        var lastProgress = Date.distantPast
        let started = Date()
        func manifest(_ state: String, _ reason: String = "") throws {
            let data: [String: Any] = ["状态": state, "说明": reason, "来源": result.roots.map(\.path), "计划文件数": result.photos.count,
                                       "已校验文件数": rows.count, "处理中": currentFile, "输出时区": "+08:00", "同时间规则": "来源完整路径的稳定顺序，不宣称恢复无法记录的真实先后", "文件": rows]
            try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]).write(to: manifestURL, options: .atomic)
        }
        do {
            try manifest("复制中")
            let staged = try supportsExclusiveRename(in: root)
            for (i, photo) in result.photos.enumerated() {
                try autoreleasepool {
                    try stop.check()
                    currentFile = photo.proposed
                    let previous = completedBytes
                    let hash = try copyOne(photo, destination: root.appendingPathComponent(photo.proposed), stop: stop, exclusiveRename: staged) { bytes in
                        let now = Date()
                        if now.timeIntervalSince(lastProgress) >= 0.2 {
                            lastProgress = now
                            let speed = Double(previous + bytes) / max(0.1, now.timeIntervalSince(started)) / 1_000_000
                            progress(Double(previous + bytes) / Double(max(1, result.totalBytes)), String(format: "已校验 %d / %d · %.1f MB/s · 正在复制并校验 %@", rows.count, result.photos.count, speed, photo.url.lastPathComponent))
                        }
                    }
                    let row: [String: Any] = ["来源": photo.url.path, "目标": photo.proposed, "机位": photo.camera, "机身序列号": photo.serial, "相机归组键": photo.groupKey, "原始拍摄时间": photo.original,
                                             "排序时间": photo.displayTime, "原片亚秒位数": photo.subsecondDigits, "时区使用默认值": photo.inferredZone,
                                             "字节数": photo.bytes, "SHA256": hash, "校验": "一致"]
                    rows.append(row)
                    var line = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]); line.append(10)
                    try journal.write(contentsOf: line)
                    completedBytes += photo.bytes; currentFile = ""
                    // 逐张追加小记录，每十张落完整快照，避免整批记录反复序列化和刷盘。
                    if (i + 1) % 10 == 0 { try journal.synchronize(); try manifest("复制中") }
                }
            }
            try journal.synchronize()
            try manifest("已完成")
            progress(1, "完成：\(rows.count) 张照片已复制，SHA-256 逐文件校验全部一致")
            return root
        } catch {
            try? manifest("未完成", error.localizedDescription)
            throw error
        }
    }
}
