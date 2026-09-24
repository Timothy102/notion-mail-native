import Foundation
import MailMCP

// stdout carries only protocol messages; everything else goes to stderr.
let server = MCPServer.live(environment: ProcessInfo.processInfo.environment)
for try await line in FileHandle.standardInput.bytes.lines where !line.isEmpty {
    if let reply = await server.handle(line) {
        FileHandle.standardOutput.write(Data((reply + "\n").utf8))
    }
}
