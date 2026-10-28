import CopaHUDCore
import Foundation

// Usage: swift run reliability-report <console-log>
// The log is the device console captured with scripts/reliability-run.sh.
let args = CommandLine.arguments.dropFirst()
guard let path = args.first, args.count == 1 else {
  FileHandle.standardError.write(Data("usage: reliability-report <console-log>\n".utf8))
  exit(2)
}
guard let data = FileManager.default.contents(atPath: path) else {
  FileHandle.standardError.write(Data("reliability-report: can't read \(path)\n".utf8))
  exit(1)
}
print(RunReport.parse(String(decoding: data, as: UTF8.self)).summary)
