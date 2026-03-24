import Foundation
import CryptoKit
import Security

struct FFmpegBinaryIdentity: Sendable, Equatable {
    let architecture: String
    let fileName: String
    let sha256: String

    nonisolated static let x86_64 = FFmpegBinaryIdentity(
        architecture: "x86_64",
        fileName: "ffmpeg-binary-x86_64",
        sha256: "26b3ff92f64950f16be16eed88fe29064c2df516efdfac66cb8fa9abed030bdf"
    )

    nonisolated static let arm64 = FFmpegBinaryIdentity(
        architecture: "arm64",
        fileName: "ffmpeg-binary-arm64",
        sha256: "3b586ff896c0339e8fd574c143aaccac23c80789341e22d4202f8013a133d3a4"
    )

    nonisolated static let all = [arm64, x86_64]

    nonisolated static func identity(forFileName fileName: String) -> FFmpegBinaryIdentity? {
        all.first { $0.fileName == fileName }
    }
}

struct FFmpegBinaryVerifier: Sendable {
    private let helperDirectory: String

    nonisolated init(helperDirectory: String) {
        self.helperDirectory = helperDirectory
    }

    nonisolated func verifyRuntimeBinary(atPath path: String, bundleURL: URL) -> Bool {
        if isPackagedHelper(atPath: path, bundleURL: bundleURL) {
            return verifyPackagedHelperSignature(atPath: path)
        } else {
            return verifyVendoredBinary(atPath: path)
        }
    }

    nonisolated func verifyVendoredBinary(atPath path: String) -> Bool {
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        guard let identity = FFmpegBinaryIdentity.identity(forFileName: fileName) else {
            return false
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else {
            return false
        }

        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return hex == identity.sha256
    }

    private nonisolated func isPackagedHelper(atPath path: String, bundleURL: URL) -> Bool {
        let packagedHelperDirectory = bundleURL
            .appendingPathComponent(helperDirectory)
            .resolvingSymlinksInPath()
            .path
        let binaryDirectory = URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .path
        return binaryDirectory == packagedHelperDirectory
    }

    private nonisolated func verifyPackagedHelperSignature(atPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path) as CFURL
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url, SecCSFlags(), &staticCode)

        guard createStatus == errSecSuccess, let staticCode else {
            return false
        }

        let checkStatus = SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil)
        return checkStatus == errSecSuccess
    }
}
