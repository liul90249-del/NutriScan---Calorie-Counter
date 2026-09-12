import Foundation
import StoreKit
import CryptoKit

/// Stores only signed purchase proofs, never food logs or profile information.
actor PartnerTransactionOutbox {
    static let shared = PartnerTransactionOutbox()
    private let endpoint = URL(string: "https://squadlive.onrender.com/v1/partners/nutriscan/transactions")!
    private var flushing = false
    private struct Item: Codable, Equatable {
        let transactionID: String
        let signedTransaction: String
        let isAppTransaction: Bool?
    }
    private func directory() throws -> URL {
        var url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("VerifiedTransactionOutbox", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        return url
    }
    func enqueue(_ result: VerificationResult<Transaction>) throws {
        guard case .verified(let transaction) = result else { return }
        let item = Item(transactionID: String(transaction.id), signedTransaction: result.jwsRepresentation, isAppTransaction: nil)
        // Separate files make each write durable before StoreKit.finish().
        let identity = String(describing: transaction.environment) + ":" + String(transaction.id)
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = try directory().appendingPathComponent(key + ".json")
        try JSONEncoder().encode(item).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        Task { await flush() }
    }
    func collectAppTransaction() async {
        do {
            let result = try await AppTransaction.shared
            guard case .verified(let transaction) = result else { return }
            let item = Item(transactionID: transaction.appTransactionID, signedTransaction: result.jwsRepresentation, isAppTransaction: true)
            let identity = "app:" + String(describing: transaction.environment) + ":" + transaction.appTransactionID
            let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
            let file = try directory().appendingPathComponent(key + ".json")
            try JSONEncoder().encode(item).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            await flush()
        } catch {
            // App receipt availability must not prevent using the app.
        }
    }
    func flush() async {
        guard !flushing else { return }
        flushing = true
        defer { flushing = false }
        guard let root = try? directory(),
              let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(50) {
            do {
                let saved = try Data(contentsOf: file)
                let item = try JSONDecoder().decode(Item.self, from: saved)
                let isApp = item.isAppTransaction == true
                let target = isApp ? endpoint.deletingLastPathComponent().appendingPathComponent("app-transactions") : endpoint
                var request = URLRequest(url: target)
                request.httpMethod = "POST"
                request.timeoutInterval = 15
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: [isApp ? "signed_app_transaction" : "signed_transaction": item.signedTransaction])
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let ack = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      ack["received"] as? Bool == true,
                      ack["transaction_id"] as? String == item.transactionID else { continue }
                // Do not erase a newer revocation proof queued while uploading this file.
                if try Data(contentsOf: file) == saved { try FileManager.default.removeItem(at: file) }
            } catch {
                // Keep durable proof for the next launch or transaction-triggered flush.
                continue
            }
        }
    }
}
