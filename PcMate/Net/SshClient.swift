import Foundation
import Crypto
import _CryptoExtras
import NIOCore
import NIOFoundationCompat
import NIOSSH
import Citadel

// MARK: - SSH / SFTP 回退

/// SSH 回退通道：命令执行走 Citadel 的 exec，文件浏览/传输走 SFTP。
/// 主机密钥按 TOFU 指纹固定；首次连接时由上层保存指纹。
final class SshClient: @unchecked Sendable {

    private let connection: Connection
    private var client: SSHClient?
    private var sftp: SFTPClient?
    private let fingerprintLock = NSLock()
    private var _capturedFingerprint: String = ""

    private var lastCPUTotal: Double = 0
    private var lastCPUIdle: Double = 0
    private var lastRx: Int64 = 0
    private var lastTx: Int64 = 0
    private var lastNetTime: TimeInterval = 0

    private(set) var hostInfo: HostInfo?

    init(connection: Connection) {
        self.connection = connection
    }

    var capturedFingerprint: String {
        fingerprintLock.lock()
        defer { fingerprintLock.unlock() }
        return _capturedFingerprint
    }

    // MARK: 连接

    func connect() async throws -> HostInfo {
        let validator = TOFUHostKeyValidator(expected: connection.sshFingerprint) { [weak self] fingerprint in
            guard let self else { return }
            self.fingerprintLock.lock()
            self._capturedFingerprint = fingerprint
            self.fingerprintLock.unlock()
        }
        let auth = try Self.authentication(for: connection)
        let client = try await SSHClient.connect(
            host: connection.host,
            port: connection.port,
            authenticationMethod: auth,
            hostKeyValidator: .custom(validator),
            reconnect: .never
        )
        self.client = client
        self.sftp = try await client.openSFTP()
        let info = try await loadHostInfo()
        self.hostInfo = info
        return info
    }

    func close() async {
        if let sftp { try? await sftp.close() }
        if let client { try? await client.close() }
        sftp = nil
        client = nil
    }

    // MARK: 基础命令

    private func run(_ command: String, maxBytes: Int = 8_000_000) async throws -> String {
        guard let client else { throw PcMateError.connectionClosed }
        let buffer = try await client.executeCommand(command, maxResponseSize: maxBytes)
        return String(buffer: buffer)
    }

    private func runPowerShell(_ script: String) async throws -> String {
        let data = script.data(using: .utf16LittleEndian) ?? Data()
        let encoded = data.base64EncodedString()
        return try await run("powershell -NoProfile -NonInteractive -EncodedCommand \(encoded)", maxBytes: 12_000_000)
    }

    // MARK: 主机信息

    private func loadHostInfo() async throws -> HostInfo {
        let probe = try await run("uname -s 2>/dev/null || cmd /c ver 2>/dev/null || ver 2>/dev/null")
        let isWindows = probe.lowercased().contains("windows")
            || probe.lowercased().contains("mingw")
            || probe.lowercased().contains("cygwin")
        return isWindows ? try await loadWindowsHost() : try await loadLinuxHost()
    }

    private func loadLinuxHost() async throws -> HostInfo {
        let script = """
        echo "HOST=$(hostname 2>/dev/null)"
        echo "KERNEL=$(uname -r 2>/dev/null)"
        echo "CORES=$(nproc 2>/dev/null)"
        echo "CPU=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//')"
        echo "MEM=$(awk '/MemTotal/ {print $2*1024}' /proc/meminfo 2>/dev/null)"
        echo "GPU=$(lspci 2>/dev/null | grep -i -m1 'vga\\|3d' | cut -d: -f3- | sed 's/^ *//')"
        echo "ROOT=$([ "$(id -u)" = "0" ] && echo 1 || echo 0)"
        echo "OS=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '\\"')"
        """
        let text = try await run(script)
        let values = parseKeyValues(text)
        return HostInfo(
            hostname: values["HOST"] ?? "",
            os: .linux,
            osLabel: values["OS"] ?? "Linux",
            kernel: values["KERNEL"] ?? "",
            cpuModel: values["CPU"] ?? "",
            cores: Int(values["CORES"] ?? "") ?? 0,
            totalMemBytes: Int64(values["MEM"] ?? "") ?? 0,
            gpuName: (values["GPU"] ?? "").isEmpty ? nil : values["GPU"],
            gpuMemBytes: 0,
            isRoot: values["ROOT"] == "1",
            agentVersion: ""
        )
    }

    private func loadWindowsHost() async throws -> HostInfo {
        let script = """
        $os = Get-CimInstance Win32_OperatingSystem
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $gpu = Get-CimInstance Win32_VideoController | Select-Object -First 1
        $root = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        Write-Output ('HOST=' + $env:COMPUTERNAME)
        Write-Output ('KERNEL=' + $os.Version)
        Write-Output ('CORES=' + $cpu.NumberOfCores)
        Write-Output ('CPU=' + $cpu.Name)
        Write-Output ('MEM=' + ([int64]$os.TotalVisibleMemorySize * 1024))
        Write-Output ('GPU=' + $gpu.Name)
        Write-Output ('ROOT=' + [int]$root)
        Write-Output ('OS=' + $os.Caption)
        """
        let text = try await runPowerShell(script)
        let values = parseKeyValues(text)
        return HostInfo(
            hostname: values["HOST"] ?? "",
            os: .windows,
            osLabel: values["OS"] ?? "Windows",
            kernel: values["KERNEL"] ?? "",
            cpuModel: values["CPU"] ?? "",
            cores: Int(values["CORES"] ?? "") ?? 0,
            totalMemBytes: Int64(values["MEM"] ?? "") ?? 0,
            gpuName: (values["GPU"] ?? "").isEmpty ? nil : values["GPU"],
            gpuMemBytes: 0,
            isRoot: values["ROOT"] == "1",
            agentVersion: ""
        )
    }

    // MARK: 实时快照

    func snapshot() async throws -> Snapshot {
        guard let hostInfo else { throw PcMateError.connectionClosed }
        return hostInfo.os == .windows ? try await windowsSnapshot() : try await linuxSnapshot()
    }

    private func linuxSnapshot() async throws -> Snapshot {
        let script = """
        echo '--CPU'
        head -n1 /proc/stat
        echo '--MEM'
        free -b 2>/dev/null
        echo '--NET'
        cat /proc/net/dev
        echo '--DISK'
        df -P -B1 2>/dev/null
        echo '--UPTIME'
        cat /proc/uptime
        echo '--PROCS'
        ps -e --no-headers 2>/dev/null | wc -l
        echo '--LOAD'
        cat /proc/loadavg
        echo '--SPEED'
        grep -m1 'cpu MHz' /proc/cpuinfo 2>/dev/null
        """
        let text = try await run(script)
        let sections = parseSections(text)
        var snapshot = Snapshot()

        if let cpuLine = sections["CPU"]?.split(separator: "\n").first {
            let parts = cpuLine.split(whereSeparator: { $0 == " " || $0 == "\t" }).dropFirst().compactMap { Double(String($0)) }
            if parts.count >= 4 {
                let total = parts.reduce(0, +)
                let idle = parts[3] + (parts.count > 4 ? parts[4] : 0)
                if lastCPUTotal > 0, total > lastCPUTotal {
                    let deltaTotal = total - lastCPUTotal
                    let deltaIdle = idle - lastCPUIdle
                    snapshot.cpuPercent = min(max((1 - deltaIdle / deltaTotal) * 100, 0), 100)
                }
                lastCPUTotal = total
                lastCPUIdle = idle
            }
        }

        if let memText = sections["MEM"] {
            for line in memText.split(separator: "\n") {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                guard parts.count >= 4 else { continue }
                if parts[0] == "Mem:" {
                    snapshot.memTotal = Int64(parts[1]) ?? 0
                    snapshot.memUsed = Int64(parts[2]) ?? 0
                    snapshot.memFree = Int64(parts[3]) ?? 0
                    snapshot.memAvailable = parts.count > 6 ? (Int64(parts[6]) ?? 0) : (Int64(parts[3]) ?? 0)
                    snapshot.memBuffers = parts.count > 5 ? (Int64(parts[5]) ?? 0) : 0
                    snapshot.memCached = parts.count > 5 ? (Int64(parts[5]) ?? 0) : 0
                } else if parts[0] == "Swap:" {
                    snapshot.swapTotal = Int64(parts[1]) ?? 0
                    snapshot.swapUsed = Int64(parts[2]) ?? 0
                }
            }
        }

        if let netText = sections["NET"] {
            var rx: Int64 = 0
            var tx: Int64 = 0
            for line in netText.split(separator: "\n") {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let iface = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                if iface == "lo" { continue }
                let fields = line[line.index(after: colon)...]
                    .split(whereSeparator: { $0 == " " || $0 == "\t" })
                    .map(String.init)
                guard fields.count >= 10 else { continue }
                rx += Int64(fields[0]) ?? 0
                tx += Int64(fields[8]) ?? 0
            }
            let now = Date().timeIntervalSince1970
            if lastNetTime > 0, now > lastNetTime {
                let seconds = now - lastNetTime
                snapshot.netRxBps = Int64(max(Double(rx - lastRx) / seconds, 0))
                snapshot.netTxBps = Int64(max(Double(tx - lastTx) / seconds, 0))
            }
            snapshot.netRxTotal = rx
            snapshot.netTxTotal = tx
            lastRx = rx
            lastTx = tx
            lastNetTime = now
        }

        if let diskText = sections["DISK"] {
            for line in diskText.split(separator: "\n").dropFirst() {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                guard parts.count >= 6 else { continue }
                let total = Int64(parts[1]) ?? 0
                let used = Int64(parts[2]) ?? 0
                guard total > 0 else { continue }
                let mount = parts[5...].joined(separator: " ")
                let percent = Double(parts[4].replacingOccurrences(of: "%", with: "")) ?? (Double(used) / Double(total) * 100)
                snapshot.disks.append(DiskInfo(
                    name: mount,
                    detail: parts[0],
                    totalBytes: total,
                    usedBytes: used,
                    percent: percent
                ))
            }
        }

        if let uptimeText = sections["UPTIME"]?.split(separator: " ").first,
           let seconds = Double(String(uptimeText)) {
            snapshot.uptimeSeconds = Int64(seconds)
        }
        if let procText = sections["PROCS"]?.trimmingCharacters(in: .whitespacesAndNewlines) {
            snapshot.processCount = Int(procText) ?? 0
        }
        if let load = sections["LOAD"]?.trimmingCharacters(in: .whitespacesAndNewlines), !load.isEmpty {
            snapshot.loadAverage = load
        }
        if let speedLine = sections["SPEED"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           let value = speedLine.split(separator: ":").last,
           let mhz = Double(String(value).trimmingCharacters(in: .whitespaces)) {
            snapshot.cpuSpeedMhz = Int(mhz)
        }
        snapshot.latencyMs = 0
        return snapshot
    }

    private func windowsSnapshot() async throws -> Snapshot {
        let script = """
        $os = Get-CimInstance Win32_OperatingSystem
        $cpu = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'"
        $memTotal = [int64]$os.TotalVisibleMemorySize * 1024
        $memFree = [int64]$os.FreePhysicalMemory * 1024
        $memUsed = $memTotal - $memFree
        $disks = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3'
        $stats = Get-NetAdapterStatistics -ErrorAction SilentlyContinue
        $rx = 0; $tx = 0
        if ($stats) {
            $rx = ($stats | Measure-Object -Property ReceivedBytes -Sum).Sum
            $tx = ($stats | Measure-Object -Property SentBytes -Sum).Sum
        }
        $uptime = [int64]((Get-Date) - $os.LastBootUpTime).TotalSeconds
        $procCount = (Get-Process).Count
        Write-Output ('CPU|' + $cpu.PercentProcessorTime)
        Write-Output ('MEM|' + $memTotal + '|' + $memUsed + '|' + $memFree)
        foreach ($d in $disks) {
            $size = [double]$d.Size
            $used = $size - [double]$d.FreeSpace
            $pct = if ($size -gt 0) { [math]::Round(($used / $size) * 100, 1) } else { 0 }
            Write-Output ('DISK|' + $d.DeviceID + '|' + $d.VolumeName + '|' + [int64]$size + '|' + [int64]$used + '|' + $pct)
        }
        Write-Output ('NET|' + [int64]$rx + '|' + [int64]$tx)
        Write-Output ('UPTIME|' + $uptime)
        Write-Output ('PROCS|' + $procCount)
        """
        let text = try await runPowerShell(script)
        var snapshot = Snapshot()
        let now = Date().timeIntervalSince1970
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard let kind = parts.first else { continue }
            switch kind {
            case "CPU":
                if parts.count > 1 { snapshot.cpuPercent = Double(parts[1]) ?? 0 }
            case "MEM":
                if parts.count > 3 {
                    snapshot.memTotal = Int64(parts[1]) ?? 0
                    snapshot.memUsed = Int64(parts[2]) ?? 0
                    snapshot.memFree = Int64(parts[3]) ?? 0
                    snapshot.memAvailable = snapshot.memFree
                }
            case "DISK":
                if parts.count >= 6 {
                    let total = Int64(parts[3]) ?? 0
                    let used = Int64(parts[4]) ?? 0
                    let name = parts[2].isEmpty ? parts[1] : "\(parts[1]) \(parts[2])"
                    snapshot.disks.append(DiskInfo(
                        name: name,
                        detail: parts[1],
                        totalBytes: total,
                        usedBytes: used,
                        percent: Double(parts[5]) ?? 0
                    ))
                }
            case "NET":
                if parts.count > 2 {
                    let rx = Int64(parts[1]) ?? 0
                    let tx = Int64(parts[2]) ?? 0
                    if lastNetTime > 0, now > lastNetTime {
                        let seconds = now - lastNetTime
                        snapshot.netRxBps = Int64(max(Double(rx - lastRx) / seconds, 0))
                        snapshot.netTxBps = Int64(max(Double(tx - lastTx) / seconds, 0))
                    }
                    snapshot.netRxTotal = rx
                    snapshot.netTxTotal = tx
                    lastRx = rx
                    lastTx = tx
                    lastNetTime = now
                }
            case "UPTIME":
                if parts.count > 1 { snapshot.uptimeSeconds = Int64(parts[1]) ?? 0 }
            case "PROCS":
                if parts.count > 1 { snapshot.processCount = Int(parts[1]) ?? 0 }
            default:
                break
            }
        }
        return snapshot
    }

    // MARK: 进程

    func processes() async throws -> ProcessSnapshot {
        guard let hostInfo else { throw PcMateError.connectionClosed }
        return hostInfo.os == .windows ? try await windowsProcesses() : try await linuxProcesses()
    }

    private func linuxProcesses() async throws -> ProcessSnapshot {
        let text = try await run("ps -eo pid,user,pcpu,rss,comm,args --sort=-pcpu 2>/dev/null | head -n 200")
        var items: [ProcessInfo] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 5, let pid = Int(parts[0]) else { continue }
            let rssKB = Int64(parts[3]) ?? 0
            items.append(ProcessInfo(
                pid: pid,
                name: parts[4],
                user: parts[1],
                cpuPercent: Double(parts[2]) ?? 0,
                memBytes: rssKB * 1024,
                command: parts.count > 5 ? parts[5] : parts[4]
            ))
        }
        let totalText = try await run("ps -e --no-headers 2>/dev/null | wc -l")
        let total = Int(totalText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? items.count
        return ProcessSnapshot(items: items, totalCount: total)
    }

    private func windowsProcesses() async throws -> ProcessSnapshot {
        let script = """
        $procs = @{}
        Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $procs[[int]$_.Id] = $_ }
        $items = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne '_Total' -and $_.Name -ne 'Idle' } |
            Sort-Object PercentProcessorTime -Descending |
            Select-Object -First 160
        foreach ($p in $items) {
            $id = [int]$p.IDProcess
            $name = $p.Name
            if ($procs.ContainsKey($id)) { $name = $procs[$id].ProcessName }
            Write-Output ('PROC|' + $id + '|' + $name + '|' + $p.PercentProcessorTime + '|' + [int64]$p.WorkingSet + '|' + $p.Name)
        }
        Write-Output ('TOTAL|' + (Get-Process -ErrorAction SilentlyContinue).Count)
        """
        let text = try await runPowerShell(script)
        var items: [ProcessInfo] = []
        var total = 0
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if parts.first == "TOTAL" {
                total = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
                continue
            }
            guard parts.count >= 6, parts[0] == "PROC", let pid = Int(parts[1]) else { continue }
            items.append(ProcessInfo(
                pid: pid,
                name: parts[2],
                user: "",
                cpuPercent: Double(parts[3]) ?? 0,
                memBytes: Int64(parts[4]) ?? 0,
                command: parts[5]
            ))
        }
        return ProcessSnapshot(items: items, totalCount: total > 0 ? total : items.count)
    }

    func kill(pid: Int) async throws -> String {
        guard pid > 1 else { throw PcMateError.message("不能结束系统进程") }
        guard let hostInfo else { throw PcMateError.connectionClosed }
        if hostInfo.os == .windows {
            let text = try await runPowerShell("Stop-Process -Id \(pid) -Force -ErrorAction Stop; Write-Output '进程已结束'")
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        _ = try await run("kill -9 \(pid) 2>&1")
        return "进程已结束"
    }

    // MARK: 清理

    func cleanup(mode: CleanupMode) async throws -> CleanupResult {
        guard let hostInfo else { throw PcMateError.connectionClosed }
        return hostInfo.os == .windows ? try await windowsCleanup() : try await linuxCleanup(mode: mode)
    }

    private func linuxCleanup(mode: CleanupMode) async throws -> CleanupResult {
        let before = try await linuxAvailableMemory()
        let value: String
        switch mode {
        case .linuxPage: value = "1"
        case .linuxDentry: value = "2"
        case .linuxDeep: value = "3"
        default: value = "3"
        }
        var command = "sync; echo \(value) > /proc/sys/vm/drop_caches"
        if mode == .linuxDeep {
            command += "; echo 1 > /proc/sys/vm/compact_memory 2>/dev/null"
        }
        if !connection.sudoPassword.isEmpty {
            let quoted = shellQuote(connection.sudoPassword)
            command = "echo \(quoted) | sudo -S sh -c \(shellQuote(command))"
        } else if hostInfo?.isRoot != true {
            // 没有 sudo 密码时用 -n，避免 sudo 在远端等待输入把会话挂住。
            command = "sudo -n sh -c \(shellQuote(command))"
        }
        let output = try await run(command + " 2>&1")
        let lower = output.lowercased()
        if lower.contains("permission denied") || lower.contains("operation not permitted") {
            throw PcMateError.message("清理需要 root 权限，请填写 sudo 密码后重试")
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
        let after = try await linuxAvailableMemory()
        return CleanupResult(
            success: true,
            beforeBytes: before,
            afterBytes: after,
            metricLabel: "可用内存",
            message: after >= before ? "已释放 \(Fmt.bytes(after - before))" : "清理完成，当前可用 \(Fmt.bytes(after))",
            log: output.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func linuxAvailableMemory() async throws -> Int64 {
        let text = try await run("free -b 2>/dev/null | awk '/^Mem:/ {print $7}'")
        return Int64(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private func windowsCleanup() async throws -> CleanupResult {
        let beforeScript = "(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory * 1024"
        let before = Int64((try await runPowerShell(beforeScript)).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let script = """
        Add-Type -TypeDefinition @'
        using System;
        using System.Runtime.InteropServices;
        public class PcMateMemTrim {
            [DllImport("psapi.dll")]
            public static extern bool EmptyWorkingSet(IntPtr hProcess);
        }
        '@
        Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
            try { [PcMateMemTrim]::EmptyWorkingSet($_.Handle) | Out-Null } catch { }
        }
        Write-Output '工作集已整理'
        """
        let output = try await runPowerShell(script)
        try? await Task.sleep(nanoseconds: 400_000_000)
        let after = Int64((try await runPowerShell(beforeScript)).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return CleanupResult(
            success: true,
            beforeBytes: before,
            afterBytes: after,
            metricLabel: "可用内存",
            message: after >= before ? "已回收 \(Fmt.bytes(after - before))" : "整理完成，当前可用 \(Fmt.bytes(after))",
            log: output.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    // MARK: SFTP 文件

    var initialPath: String {
        hostInfo?.os == .windows ? "C:/" : "/"
    }

    func list(path: String) async throws -> RemoteListing {
        guard let sftp else { throw PcMateError.connectionClosed }
        let target = path.isEmpty ? initialPath : path
        let names = try await sftp.listDirectory(atPath: target)
        var entries: [RemoteFileEntry] = []
        for name in names {
            for component in name.components {
                if component.filename == "." || component.filename == ".." { continue }
                let attributes = component.attributes
                let isDir = (attributes.permissions.map { ($0 & 0o170000) == 0o040000 } ?? false)
                    || component.longname.hasPrefix("d")
                let modified = attributes.accessModificationTime?.modificationTime
                entries.append(RemoteFileEntry(
                    name: component.filename,
                    path: RemotePath.join(target, component.filename),
                    isDir: isDir,
                    sizeBytes: Int64(attributes.size ?? 0),
                    modifiedMs: modified.map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
                ))
            }
        }
        entries.sort { lhs, rhs in
            if lhs.isDir != rhs.isDir { return lhs.isDir }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return RemoteListing(path: target, parent: RemotePath.parent(target), entries: entries)
    }

    func download(path: String, to destination: URL) async throws -> URL {
        guard let sftp else { throw PcMateError.connectionClosed }
        let buffer = try await sftp.withFile(filePath: path, flags: .read) { file in
            try await file.readAll()
        }
        let data = Data(buffer.readableBytesView)
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: destination.path) {
            try manager.removeItem(at: destination)
        }
        try data.write(to: destination)
        return destination
    }

    func upload(name: String, data: Data, directory: String) async throws -> RemoteFileEntry {
        guard let sftp else { throw PcMateError.connectionClosed }
        let target = RemotePath.join(directory, name)
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        let payload = buffer
        try await sftp.withFile(filePath: target, flags: [.write, .create, .truncate]) { file in
            try await file.write(payload)
        }
        return RemoteFileEntry(
            name: name,
            path: target,
            isDir: false,
            sizeBytes: Int64(data.count),
            modifiedMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    func makeDirectory(path: String) async throws -> String {
        guard let sftp else { throw PcMateError.connectionClosed }
        try await sftp.createDirectory(atPath: path)
        return "文件夹已创建"
    }

    func delete(path: String) async throws -> String {
        guard let sftp else { throw PcMateError.connectionClosed }
        do {
            try await sftp.remove(at: path)
        } catch {
            // 目录要用 rmdir；先试文件删除，失败后再按目录处理。
            try await sftp.rmdir(at: path)
        }
        return "已删除"
    }

    // MARK: 解析工具

    private func parseKeyValues(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let index = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: index)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { result[key] = value }
        }
        return result
    }

    private func parseSections(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var current = ""
        var buffer: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("--") {
                if !current.isEmpty { result[current] = buffer.joined(separator: "\n") }
                current = String(trimmed.dropFirst(2))
                buffer = []
            } else {
                buffer.append(String(line))
            }
        }
        if !current.isEmpty { result[current] = buffer.joined(separator: "\n") }
        return result
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: 认证

    private static func authentication(for connection: Connection) throws -> SSHAuthenticationMethod {
        if connection.authType == .key, !connection.privateKey.isEmpty {
            let decryptionKey = connection.passphrase.isEmpty ? nil : Data(connection.passphrase.utf8)
            if let key = try? Curve25519.Signing.PrivateKey(sshEd25519: connection.privateKey, decryptionKey: decryptionKey) {
                return .ed25519(username: connection.username, privateKey: key)
            }
            if let key = try? Insecure.RSA.PrivateKey(sshRsa: connection.privateKey, decryptionKey: decryptionKey) {
                return .rsa(username: connection.username, privateKey: key)
            }
            throw PcMateError.message("无法解析私钥，请确认是 OpenSSH 格式（ed25519 或 RSA）")
        }
        return .passwordBased(username: connection.username, password: connection.password)
    }
}

// MARK: - TOFU 主机密钥校验

private final class TOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {

    private let expected: String?
    private let onFingerprint: @Sendable (String) -> Void

    init(expected: String?, onFingerprint: @escaping @Sendable (String) -> Void) {
        self.expected = expected
        self.onFingerprint = onFingerprint
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        var buffer = ByteBufferAllocator().buffer(capacity: 256)
        _ = hostKey.write(to: &buffer)
        let data = Data(buffer.readableBytesView)
        let digest = SHA256.hash(data: data)
        let fingerprint = "SHA256:" + Data(digest).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        onFingerprint(fingerprint)

        if let expected, !expected.isEmpty,
           PinnedTLSDelegate.normalize(expected) != PinnedTLSDelegate.normalize(fingerprint) {
            validationCompletePromise.fail(PcMateError.tlsFingerprintMismatch(expected: expected, actual: fingerprint))
        } else {
            validationCompletePromise.succeed(())
        }
    }
}
