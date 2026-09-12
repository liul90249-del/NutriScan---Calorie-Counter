import Foundation
import DeviceCheck
import CryptoKit

/// An App Attest proof validates the app instance; it does not establish first-use history.
actor NutriScanDeviceAttest {
    static let shared = NutriScanDeviceAttest()
    private var running = false
    private struct State: Codable {
        var keyID: String
        var challenge: String?
        var attestation: String?
        var expiresAt: Date?
    }
    private let endpoint = URL(string: "https://squadlive.onrender.com/v1/partners/nutriscan/device")!
    func verify(appTransactionID: String, environment: String, credential: String) async throws {
        guard !running else { return }
        guard DCAppAttestService.shared.isSupported else { throw URLError(.unsupportedURL) }
        running = true
        defer { running = false }
        let key = SHA256.hash(data: Data((environment + ":" + appTransactionID).utf8)).map { String(format: "%02x", $0) }.joined()
        var directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("PartnerDeviceAttest", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
        let file = directory.appendingPathComponent(key + ".json")
        var state: State?
        do { state = try JSONDecoder().decode(State.self, from: Data(contentsOf: file)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { state = nil }
        let status = try await request(["action": "status"], appTransactionID, environment, credential)
        if let remoteKey = status["key_id"] as? String {
            guard state?.keyID == remoteKey else { throw URLError(.userAuthenticationRequired) }
        } else {
            // A key whose proof expired before registration may be replaced only
            // when the authenticated server confirms no device key is registered.
            if let pending = state, let expiry = pending.expiresAt, expiry < Date() {
                state = nil
            }
            if state == nil {
                let generated = try await DCAppAttestService.shared.generateKey()
                state = State(keyID: generated)
                try persist(state!, file)
            }
            guard var pending = state else { throw URLError(.userAuthenticationRequired) }
            if pending.attestation == nil {
                let challenge = try await request(["action": "challenge", "kind": "attest"], appTransactionID, environment, credential)
                guard let nonce = challenge["challenge"] as? String else { throw URLError(.badServerResponse) }
                let data = try await DCAppAttestService.shared.attestKey(pending.keyID, clientDataHash: Data(SHA256.hash(data: Data(nonce.utf8))))
                pending.challenge = nonce; pending.attestation = data.base64EncodedString()
                pending.expiresAt = Date().addingTimeInterval(90)
                try persist(pending, file); state = pending
            }
            guard let nonce = pending.challenge, let proof = pending.attestation else { throw URLError(.badServerResponse) }
            let ack = try await request(["action": "verify", "kind": "attest", "key_id": pending.keyID, "challenge": nonce, "proof": proof], appTransactionID, environment, credential)
            guard ack["device_attested"] as? Bool == true else { throw URLError(.userAuthenticationRequired) }
        }
        guard let state else { throw URLError(.userAuthenticationRequired) }
        let challenge = try await request(["action": "challenge", "kind": "assert"], appTransactionID, environment, credential)
        guard let nonce = challenge["challenge"] as? String, let payload = challenge["payload"] as? String else { throw URLError(.badServerResponse) }
        let proof = try await DCAppAttestService.shared.generateAssertion(state.keyID, clientDataHash: Data(SHA256.hash(data: Data(payload.utf8))))
        let ack = try await request(["action": "verify", "kind": "assert", "key_id": state.keyID, "challenge": nonce, "proof": proof.base64EncodedString()], appTransactionID, environment, credential)
        guard ack["device_verified"] as? Bool == true else { throw URLError(.userAuthenticationRequired) }
    }
    private func persist(_ state: State, _ file: URL) throws {
        try JSONEncoder().encode(state).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private func request(_ fields: [String: String], _ appTransactionID: String, _ environment: String, _ credential: String) async throws -> [String: Any] {
        var body = fields; body["environment"] = environment; body["app_transaction_id"] = appTransactionID
        var request = URLRequest(url: endpoint); request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credential, forHTTPHeaderField: "X-Installation-Credential")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.badServerResponse) }
        return value
    }
}
