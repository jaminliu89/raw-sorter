import Foundation
import CryptoKit

@main struct Tests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw ToolError("测试失败：" + message) }
        print("PASS " + message)
    }
    static func main() throws {
        let fm = FileManager.default
        let work = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("test-" + UUID().uuidString)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let a = work.appendingPathComponent("A"), b = work.appendingPathComponent("B")
        try fm.createDirectory(at: a, withIntermediateDirectories: true)
        try fm.createDirectory(at: b, withIntermediateDirectories: true)
        let env = ProcessInfo.processInfo.environment
        let sourceA = URL(fileURLWithPath: env["RAW_TEST_SOURCE_A"] ?? "work/fixtures/A.ARW")
        let sourceB = URL(fileURLWithPath: env["RAW_TEST_SOURCE_B"] ?? "work/fixtures/B.ARW")
        let sampleA = a.appendingPathComponent("SAME.ARW"), sampleB = b.appendingPathComponent("SAME.ARW")
        try fm.copyItem(at: sourceA, to: sampleA); try fm.copyItem(at: sourceB, to: sampleB)
        let discovery = try Engine.discover(root: work.path, excluding: [], stop: StopFlag())
        try require(discovery.candidates.map(\.count) == [1, 1], "主目录自动识别两个 RAW 来源及数量")
        let output = try Engine.outputURL(parent: work.path, name: "另存为")
        try require(output.path == work.appendingPathComponent("另存为").path, "另存为位置和文件夹名正确拼接")
        var invalidNameRejected = false
        do { _ = try Engine.outputURL(parent: work.path, name: "../越界") } catch { invalidNameRejected = true }
        try require(invalidNameRejected, "拒绝路径穿越文件夹名")
        let externalCapacity = try Engine.availableCapacity(important: 0, regular: 820_596_178_944, filesystem: 820_596_178_944)
        try require(externalCapacity == 820_596_178_944, "外置盘 importantUsage 返回 0 时使用实际可用容量")
        let fullCapacity = try Engine.availableCapacity(important: 0, regular: 0, filesystem: 0)
        try require(fullCapacity == 0, "真实满盘仍返回零，不绕过空间检查")
        let scan = try Engine.scan(paths: [a.path, b.path], offsets: [0, 0], stop: StopFlag()) { _ in }
        try require(scan.photos.count == 2 && scan.invalid == 0, "样本的拍摄元数据读取")
        try require(scan.collisionGroups == 1, "识别来自两台相机的同名文件")
        try require(Set(scan.photos.map(\.proposed)).count == 2, "汇总文件名唯一")
        try require(scan.photos[0].seconds <= scan.photos[1].seconds, "按拍摄时间排序")
        try require(scan.photos.allSatisfy { $0.subsecondDigits == 3 }, "读取到三位亚秒")
        var p = scan.photos[0]
        try Engine.applyMetadata(["DateTimeOriginal": "2026:10:22 12:00:00", "SubSecTimeOriginal": "001", "OffsetTimeOriginal": "+08:00"], to: &p, offset: -0.002)
        try require(p.nanos == 999_000_000 && p.displayTime.contains("11:59:59.999"), "保留 001 前导零，负偏移跨秒正确")
        try Engine.applyMetadata(["DateTimeOriginal": "2026:10:22 12:00:00", "SubSecTimeOriginal": "100", "OffsetTimeOriginal": "+09:00"], to: &p, offset: 0)
        try require(p.displayTime.contains("11:00:00.100"), "不同时区归一化到 +08:00")
        try Engine.applyMetadata(["DateTimeOriginal": "2026:10:22 12:00:00"], to: &p, offset: 0)
        try require(p.inferredZone && p.subsecondDigits == 0 && p.displayTime.contains("原片无亚秒"), "缺失时区和亚秒明确标记")
        do { try Engine.applyMetadata([:], to: &p, offset: 0); throw ToolError("应拒绝缺失拍摄时间") }
        catch { try require(error.localizedDescription.contains("拍摄时间"), "缺失拍摄时间不降级到文件时间") }
        let target = work.appendingPathComponent("汇总")
        _ = try Engine.copy(scan, destination: target.path, stop: StopFlag()) { _, _ in }
        for photo in scan.photos {
            let originalHash = try Engine.digest(photo.url, stop: StopFlag())
            let copyHash = try Engine.digest(target.appendingPathComponent(photo.proposed), stop: StopFlag())
            try require(originalHash == copyHash, "复制后独立重读 SHA-256 一致：" + photo.camera)
            try require(fm.fileExists(atPath: photo.url.path), "原片仍然保留：" + photo.camera)
        }
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: target.appendingPathComponent("排序与校验记录.json"))) as! [String: Any]
        try require(manifest["状态"] as? String == "已完成" && manifest["已校验文件数"] as? Int == 2, "结果记录包含真实完成状态和校验数量")
        let afterCopy = try Engine.discover(root: work.path, excluding: [], stop: StopFlag())
        try require(afterCopy.candidates.count == 2 && afterCopy.skipped.contains("汇总"), "自动识别跳过已生成的汇总目录")
        let extra = work.appendingPathComponent("第三来源")
        try fm.createDirectory(at: extra, withIntermediateDirectories: true)
        try Data([0]).write(to: extra.appendingPathComponent("test.ARW"))
        let ambiguous = try Engine.discover(root: work.path, excluding: [], stop: StopFlag())
        try require(ambiguous.candidates.count == 3, "多于两个来源仍完整列出")
        let excluded = try Engine.discover(root: work.path, excluding: [extra], stop: StopFlag())
        try require(excluded.candidates.count == 2, "识别排除当前目标目录")
        do { _ = try Engine.copy(scan, destination: target.path, stop: StopFlag()) { _, _ in }; throw ToolError("应拒绝既有目录") }
        catch { try require(error.localizedDescription.contains("已存在"), "既有汇总目录不会被覆盖") }
        let photo = scan.photos[0], existing = target.appendingPathComponent(photo.proposed)
        let hashBefore = try Engine.digest(existing, stop: StopFlag())
        do { _ = try Engine.copyOne(photo, destination: existing, stop: StopFlag()) { _ in }; throw ToolError("应拒绝既有文件") }
        catch { try require(error.localizedDescription.contains("未覆盖"), "单文件重名时原子拒绝覆盖") }
        let hashAfter = try Engine.digest(existing, stop: StopFlag())
        try require(hashBefore == hashAfter, "既有目标文件的哈希未变化")
        do { _ = try Engine.scan(paths: [a.path, a.path], offsets: [0, 0], stop: StopFlag()) { _ in }; throw ToolError("应拒绝重叠来源") }
        catch { try require(error.localizedDescription.contains("互相包含"), "拒绝重复或嵌套来源") }
        let stopped = StopFlag(); stopped.cancel()
        do { _ = try Engine.copy(scan, destination: work.appendingPathComponent("已停止").path, stop: stopped) { _, _ in }; throw ToolError("应停止任务") }
        catch { try require(error.localizedDescription.contains("停止"), "停止操作不会继续复制") }
        if CommandLine.arguments.count > 2 {
            let external = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("真实RAW复制验证-" + UUID().uuidString)
            _ = try Engine.copy(scan, destination: external.path, stop: StopFlag()) { _, _ in }
            for p in scan.photos {
                let sourceHash = try Engine.digest(p.url, stop: StopFlag())
                let output = external.appendingPathComponent(p.proposed)
                let targetHash = try Engine.digest(output, stop: StopFlag())
                try require(sourceHash == targetHash, "实际外置盘完整 RAW 复制与哈希校验：" + p.camera)
                try require(!fm.fileExists(atPath: output.appendingPathExtension("partial").path), "外置盘成功后已清理本任务临时副本：" + p.camera)
            }
            let existingExternal = external.appendingPathComponent(scan.photos[0].proposed)
            let before = try Engine.digest(existingExternal, stop: StopFlag())
            var collisionRejected = false
            do { _ = try Engine.copyOne(scan.photos[0], destination: existingExternal, stop: StopFlag()) { _ in } }
            catch { collisionRejected = error.localizedDescription.contains("未覆盖") }
            try require(collisionRejected, "实际 ExFAT 上同名目标仍拒绝覆盖")
            let after = try Engine.digest(existingExternal, stop: StopFlag())
            try require(before == after, "实际 ExFAT 既有文件哈希不变")
            let record = try JSONSerialization.jsonObject(with: Data(contentsOf: external.appendingPathComponent("排序与校验记录.json"))) as! [String: Any]
            try require(record["状态"] as? String == "已完成" && record["已校验文件数"] as? Int == 2, "实际外置盘两张 RAW 的结果记录为已完成")
            print("EXTERNAL_EVIDENCE " + external.path)
        }
        let rigRoot = work.appendingPathComponent("三机位")
        let rigDirs = (1...3).map { rigRoot.appendingPathComponent("机位\($0)") }
        for (i, folder) in rigDirs.enumerated() {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try fm.copyItem(at: i == 1 ? sourceB : sourceA, to: folder.appendingPathComponent("SAME.ARW"))
        }
        let rigDiscovery = try Engine.discover(root: rigRoot.path, excluding: [], stop: StopFlag())
        try require(rigDiscovery.candidates.count == 3, "自动识别三个样本来源，不限制为两个")
        let rigs = try Engine.scan(paths: rigDirs.map(\.path), offsets: [0, 0, -3600], labels: ["主机", "副机", "游机"], stop: StopFlag()) { _ in }
        try require(rigs.photos.count == 3 && Set(rigs.photos.map(\.camera)) == Set(["主机", "副机", "游机"]), "三机位同名 RAW 全部保留并使用自定义机位标识")
        try require(rigs.photos.first?.camera == "游机" && rigs.photos.first!.displayTime.contains("04:52:46.696"), "第三机位独立偏移正确生效，不复用第二机位偏移")
        try require(rigs.photos.allSatisfy { $0.proposed.contains("_\($0.camera)_SAME.ARW") }, "输出名称保留各机位标识及原文件名")
        let rigOutput = try Engine.copy(rigs, destination: rigRoot.appendingPathComponent("汇总").path, stop: StopFlag()) { _, _ in }
        for p in rigs.photos {
            let expected = try Engine.digest(p.url, stop: StopFlag())
            let actual = try Engine.digest(rigOutput.appendingPathComponent(p.proposed), stop: StopFlag())
            try require(expected == actual, "三机位复制独立哈希一致：" + p.camera)
        }
        var duplicateRejected = false
        do { _ = try Engine.scan(paths: rigDirs.map(\.path), offsets: [0, 0, 0], labels: ["A", "B", "a"], stop: StopFlag()) { _ in } }
        catch { duplicateRejected = error.localizedDescription.contains("唯一") }
        try require(duplicateRejected, "拒绝大小写冲突的机位标识")
        var thirdOverlapRejected = false
        do { _ = try Engine.scan(paths: [a.path, b.path, a.appendingPathComponent("child").path], offsets: [0, 0, 0], stop: StopFlag()) { _ in } }
        catch { thirdOverlapRejected = error.localizedDescription.contains("互相包含") }
        try require(thirdOverlapRejected, "检测第三及后续来源与任意已有来源的重叠")
        let single = try Engine.scan(paths: [a.path], offsets: [0], stop: StopFlag()) { _ in }
        try require(single.photos.count == 1 && single.photos[0].camera == "A", "支持单机位且不要求补齐两个来源")
        try require(Engine.cameraCode(26) == "AA" && Engine.cameraCode(702) == "AAA", "默认机位编号超过 Z 后仍可扩展")
        print("MULTICAM_EVIDENCE " + rigRoot.path)
        let serialScan = try Engine.scan(paths: rigDirs.map(\.path), offsets: [0, 0, 0], groupBySerial: true, stop: StopFlag()) { _ in }
        try require(serialScan.photos.count == 3 && Set(serialScan.photos.map(\.groupKey)).count == 2, "同一机身的多个文件夹按真实序列号合并，保留全部照片")
        try require(serialScan.photos.allSatisfy { !$0.serial.isEmpty }, "读取到可用的机身序列号")
        let sameBody = serialScan.photos.filter { $0.url.path.contains("机位1/") || $0.url.path.contains("机位3/") }
        try require(Set(sameBody.map(\.camera)).count == 1, "同一机身的两个来源共享机位标识")
        let settings = Dictionary(serialScan.photos.map { ($0.groupKey, CameraSetting(name: $0.url.path.contains("机位2/") ? "副机" : "主机", offset: $0.url.path.contains("机位2/") ? 0 : -3600)) }, uniquingKeysWith: { first, _ in first })
        let adjusted = try Engine.scan(paths: rigDirs.map(\.path), offsets: [0, 0, 0], groupBySerial: true, cameraSettings: settings, stop: StopFlag()) { _ in }
        try require(adjusted.photos.filter { $0.camera == "主机" }.allSatisfy { $0.displayTime.contains("04:52:46.696") }, "按相机设置的偏移应用到该相机所有来源")
        let mixed = work.appendingPathComponent("混合来源"); try fm.createDirectory(at: mixed, withIntermediateDirectories: true)
        try fm.copyItem(at: sourceA, to: mixed.appendingPathComponent("one.ARW")); try fm.copyItem(at: sourceB, to: mixed.appendingPathComponent("two.ARW"))
        let mixedScan = try Engine.scan(paths: [mixed.path], offsets: [0], groupBySerial: true, stop: StopFlag()) { _ in }
        try require(Set(mixedScan.photos.map(\.camera)).count == 2, "同一文件夹内混放的不同相机仍逐张识别")
        let unknownA = Engine.cameraIdentity(["Make": "SONY", "Model": "ILCE-7M4", "SerialNumber": "0000"], fallback: "a")
        let unknownB = Engine.cameraIdentity(["Make": "SONY", "Model": "ILCE-7M4"], fallback: "b")
        try require(unknownA.serial.isEmpty && unknownA.key != unknownB.key, "缺失或占位序列号按来源分开，不按型号误合并")
        let serialOutput = try Engine.copy(adjusted, destination: work.appendingPathComponent("序列号汇总").path, stop: StopFlag()) { _, _ in }
        try require(adjusted.photos.allSatisfy { fm.fileExists(atPath: serialOutput.appendingPathComponent($0.proposed).path) }, "序列号归组后全部文件可独占复制与校验")
        let handle = try FileHandle(forWritingTo: photo.url); try handle.seekToEnd(); try handle.write(contentsOf: Data([0])); try handle.close()
        do { _ = try Engine.copyOne(photo, destination: work.appendingPathComponent("变化.ARW"), stop: StopFlag()) { _ in }; throw ToolError("应拒绝已变化来源") }
        catch { try require(error.localizedDescription.contains("已变化"), "预览后来源变化会阻止复制") }
        print("EVIDENCE " + work.path)
    }
}
