import Foundation
import WebKit

/// Serves `nmail-cid:` requests from the message's parts, downloading them from Gmail when the bytes aren't local.
@MainActor
public final class CIDSchemeHandler: NSObject, WKURLSchemeHandler {
    public override init() {}

    public var attachments: [Attachment] = []
    public var gmail: GmailClient?
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private static let cache = NSCache<NSString, NSData>()

    public func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let part = MailHTML.attachment(for: url, in: attachments) else {
            return task.didFailWithError(URLError(.fileDoesNotExist))
        }
        let key = ObjectIdentifier(task)
        let gmail = gmail
        tasks[key] = Task { [weak self] in
            var data = part.data ?? Self.cache.object(forKey: part.id as NSString) as Data?
            if data == nil, let gmail, let remoteId = part.gmailAttachmentId {
                data = try? await gmail.attachment(messageId: part.messageId, id: remoteId)
                if let data { Self.cache.setObject(data as NSData, forKey: part.id as NSString) }
            }
            guard let self, self.tasks.removeValue(forKey: key) != nil else { return }
            guard let data else { return task.didFailWithError(URLError(.resourceUnavailable)) }
            task.didReceive(URLResponse(url: url, mimeType: part.mimeType, expectedContentLength: data.count, textEncodingName: nil))
            task.didReceive(data)
            task.didFinish()
        }
    }

    public func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        tasks.removeValue(forKey: ObjectIdentifier(task))?.cancel()
    }
}
