import Foundation
import StoreKit
import CryptoKit
import Security

/// Stores only signed purchase proofs, never food logs or profile information.
actor PartnerTransactionOutbox {
    static let shared = PartnerTransactionOutbox()
    private let endpoint = URL(string: "https://squadlive.onrender.com/v1/partners/nutriscan/transactions")!
    private var flushing = false
    private struct Item: Codable, Equatable {
        let transactionID: String
        let signedTransaction: String
        let isAppTransaction: Bool?
        let environment: String?
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
        let item = Item(transactionID: String(transaction.id), signedTransaction: result.jwsRepresentation, isAppTransaction: nil, environment: nil)
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
            guard transaction.environment == .production || transaction.environment == .sandbox else { return }
            let environment = transaction.environment == .production ? "Production" : "Sandbox"
            let item = Item(transactionID: transaction.appTransactionID, signedTransaction: result.jwsRepresentation, isAppTransaction: true, environment: environment)
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
                if isApp, let environment = item.environment {
                    let credential = try NutriScanInstallationCredential.loadOrCreate(appTransactionID: item.transactionID, environment: environment)
                    request.setValue(credential, forHTTPHeaderField: "X-Installation-Credential")
                }
                request.httpMethod = "POST"
                request.timeoutInterval = 15
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: [isApp ? "signed_app_transaction" : "signed_transaction": item.signedTransaction])
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let ack = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      ack["received"] as? Bool == true,
                      ack["transaction_id"] as? String == item.transactionID else { continue }
                if isApp, let environment = item.environment, ack["installation"] is [String: Any] {
                    let credential = try NutriScanInstallationCredential.loadOrCreate(appTransactionID: item.transactionID, environment: environment)
                    Task { try? await NutriScanDeviceAttest.shared.verify(appTransactionID: item.transactionID, environment: environment, credential: credential) }
                }
                // Do not erase a newer revocation proof queued while uploading this file.
                if try Data(contentsOf: file) == saved { try FileManager.default.removeItem(at: file) }
            } catch {
                // Keep durable proof for the next launch or transaction-triggered flush.
                continue
            }
        }
    }
}


/// Private to this device. Never overwrite an existing credential on a read error.
private enum NutriScanInstallationCredential {
    static func loadOrCreate(appTransactionID: String, environment: String) throws -> String {
        let account = SHA256.hash(data: Data((environment + ":" + appTransactionID).utf8))
            .map { String(format: "%02x", $0) }.joined()
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                 kSecAttrService as String: "com.liuzhigang.NutriScan.partner-installation",
                                 kSecAttrAccount as String: account,
                                 kSecAttrSynchronizable as String: false]
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8),
                  value.range(of: "^ni_[a-f0-9]{64}$", options: .regularExpression) != nil else {
                throw URLError(.userAuthenticationRequired)
            }
            return value
        }
        guard status == errSecItemNotFound else { throw URLError(.userAuthenticationRequired) }
        var random = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else {
            throw URLError(.cannotCreateFile)
        }
        let value = "ni_" + random.map { String(format: "%02x", $0) }.joined()
        var attributes = base
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecValueData as String] = Data(value.utf8)
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
            throw URLError(.cannotWriteToFile)
        }
        return value
    }
}
