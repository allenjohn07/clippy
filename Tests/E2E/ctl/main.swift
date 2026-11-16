// e2ectl — tiny CLI used by the browser (Playwright) tests and scripts/e2e.sh.
//   e2ectl key cmd+shift+v | click X Y | popup PID | front | copy TEXT | copy-image PATH
//   e2ectl save-clipboard PATH | restore-clipboard PATH
import Cocoa

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else {
    FileHandle.standardError.write("usage: e2ectl <key|click|popup|copy|save-clipboard|restore-clipboard> ...\n".data(using: .utf8)!)
    exit(2)
}

switch cmd {
case "key":
    E2E.key(args[1])
case "click":
    E2E.click(CGPoint(x: Double(args[1])!, y: Double(args[2])!))
case "popup":
    if let f = E2E.popupFrame(pid: pid_t(args[1])!) {
        print("\(f.minX) \(f.minY) \(f.width) \(f.height)")
    } else {
        print("none")
    }
case "front":
    print(NSWorkspace.shared.frontmostApplication?.localizedName ?? "")
case "copy":
    E2E.copy(args[1])
case "copy-image":
    guard let data = FileManager.default.contents(atPath: args[1]),
          let rep = NSBitmapImageRep(data: data) ?? NSImage(data: data)?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("can't read image \(args[1])\n".data(using: .utf8)!); exit(1)
    }
    E2E.copyImage(png: png)
case "save-clipboard":
    E2E.saveClipboard(to: args[1])
case "restore-clipboard":
    E2E.restoreClipboard(from: args[1])
default:
    FileHandle.standardError.write("unknown command \(cmd)\n".data(using: .utf8)!)
    exit(2)
}
