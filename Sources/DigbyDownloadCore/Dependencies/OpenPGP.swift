import Foundation
import CryptoKit
import Security

/// Minimal OpenPGP verifier for one job: checking yt-dlp's detached signature on its checksum file
/// (`SHA2-256SUMS.sig`) against yt-dlp's signing key, which is pinned in the app. macOS has no `gpg`,
/// so this implements exactly what's needed: v4 RSA keys, v4 binary signatures, SHA-256/512.
public enum OpenPGP {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case malformed(String), unsupported(String), wrongKey, badSignature
        public var description: String {
            switch self {
            case .malformed(let s): "Malformed signature data (\(s))"
            case .unsupported(let s): "Unsupported signature (\(s))"
            case .wrongKey: "Signed by a different key than yt-dlp’s"
            case .badSignature: "The signature doesn’t match the file"
            }
        }
    }

    public struct PublicKey {
        public var n: Data, e: Data
        public var fingerprint: Data
        public var keyID: Data { fingerprint.suffix(8) }
    }

    // MARK: Armor

    public static func dearmor(_ text: String) throws -> Data {
        var inBody = false, b64 = ""
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("-----BEGIN") { inBody = false; continue }
            if line.hasPrefix("-----END") { break }
            if !inBody { if line.isEmpty { inBody = true }; continue }   // skip armor headers
            if line.hasPrefix("=") { continue }                             // CRC24 line
            b64 += line
        }
        guard let d = Data(base64Encoded: b64), !d.isEmpty else { throw Failure.malformed("armor") }
        return d
    }

    // MARK: Packets

    struct Packet { var tag: Int; var body: Data }

    static func packets(_ data: Data) throws -> [Packet] {
        let b = [UInt8](data)
        var i = 0, out: [Packet] = []
        while i < b.count {
            let h = b[i]; i += 1
            guard h & 0x80 != 0 else { throw Failure.malformed("packet header") }
            var tag: Int, len: Int
            if h & 0x40 != 0 {                     // new format
                tag = Int(h & 0x3f)
                guard i < b.count else { throw Failure.malformed("length") }
                let o1 = Int(b[i]); i += 1
                if o1 < 192 { len = o1 }
                else if o1 < 224 { guard i < b.count else { throw Failure.malformed("length") }; len = ((o1 - 192) << 8) + Int(b[i]) + 192; i += 1 }
                else if o1 == 255 { guard i + 4 <= b.count else { throw Failure.malformed("length") }
                    len = Int(b[i]) << 24 | Int(b[i+1]) << 16 | Int(b[i+2]) << 8 | Int(b[i+3]); i += 4 }
                else { throw Failure.unsupported("partial body length") }
            } else {                               // old format
                tag = Int((h >> 2) & 0x0f)
                switch h & 3 {
                case 0: guard i < b.count else { throw Failure.malformed("length") }; len = Int(b[i]); i += 1
                case 1: guard i + 2 <= b.count else { throw Failure.malformed("length") }; len = Int(b[i]) << 8 | Int(b[i+1]); i += 2
                case 2: guard i + 4 <= b.count else { throw Failure.malformed("length") }
                    len = Int(b[i]) << 24 | Int(b[i+1]) << 16 | Int(b[i+2]) << 8 | Int(b[i+3]); i += 4
                default: len = b.count - i
                }
            }
            guard len >= 0, i + len <= b.count else { throw Failure.malformed("truncated packet") }
            out.append(Packet(tag: tag, body: Data(b[i..<(i + len)])))
            i += len
        }
        return out
    }

    static func mpi(_ b: [UInt8], _ i: inout Int) throws -> Data {
        guard i + 2 <= b.count else { throw Failure.malformed("MPI") }
        let bits = Int(b[i]) << 8 | Int(b[i+1]); i += 2
        let n = (bits + 7) / 8
        guard i + n <= b.count else { throw Failure.malformed("MPI") }
        defer { i += n }
        return Data(b[i..<(i + n)])
    }

    /// The primary public key (tag 6) of a transferable key.
    public static func publicKey(armored: String) throws -> PublicKey {
        guard let p = try packets(dearmor(armored)).first(where: { $0.tag == 6 }) else { throw Failure.malformed("no public key") }
        let b = [UInt8](p.body)
        guard b.count > 6, b[0] == 4 else { throw Failure.unsupported("key version") }
        guard b[5] == 1 || b[5] == 3 else { throw Failure.unsupported("key algorithm \(b[5])") }
        var i = 6
        let n = try mpi(b, &i), e = try mpi(b, &i)
        var fp = Data([0x99, UInt8(p.body.count >> 8), UInt8(p.body.count & 0xff)]); fp.append(p.body)
        return PublicKey(n: n, e: e, fingerprint: Data(Insecure.SHA1.hash(data: fp)))
    }

    // MARK: Verification

    /// Verifies a detached binary signature (`.sig`, binary or armored) over `data`.
    public static func verify(data: Data, signature sigData: Data, key: PublicKey) throws {
        let raw = (String(data: sigData, encoding: .utf8)?.contains("BEGIN PGP SIGNATURE") == true)
            ? try dearmor(String(decoding: sigData, as: UTF8.self)) : sigData
        guard let p = try packets(raw).first(where: { $0.tag == 2 }) else { throw Failure.malformed("no signature packet") }
        let b = [UInt8](p.body)
        guard b.count > 6, b[0] == 4 else { throw Failure.unsupported("signature version") }
        guard b[1] == 0x00 else { throw Failure.unsupported("signature type \(b[1])") }
        guard b[2] == 1 || b[2] == 3 else { throw Failure.unsupported("signature algorithm \(b[2])") }
        let hashAlgo = b[3]
        let hashedLen = Int(b[4]) << 8 | Int(b[5])
        guard 6 + hashedLen + 2 <= b.count else { throw Failure.malformed("subpackets") }
        let hashed = Array(b[6..<(6 + hashedLen)])
        var i = 6 + hashedLen
        let unhashedLen = Int(b[i]) << 8 | Int(b[i+1]); i += 2
        guard i + unhashedLen + 2 <= b.count else { throw Failure.malformed("subpackets") }
        let unhashed = Array(b[i..<(i + unhashedLen)]); i += unhashedLen
        let left16 = Array(b[i..<(i + 2)]); i += 2
        let sig = try mpi(b, &i)

        // Which key made it? Issuer fingerprint (33) or issuer key id (16), hashed or not.
        let issuer = subpackets(hashed) + subpackets(unhashed)
        if let fp = issuer.first(where: { $0.type == 33 })?.data, fp.count == 21 {
            guard fp.dropFirst() == key.fingerprint else { throw Failure.wrongKey }
        } else if let id = issuer.first(where: { $0.type == 16 })?.data {
            guard id == key.keyID else { throw Failure.wrongKey }
        }

        // Hashed material: data ‖ signature header and hashed subpackets ‖ v4 trailer.
        var trailer = Data(b[0..<(6 + hashedLen)])
        let n = UInt32(6 + hashedLen)
        trailer.append(contentsOf: [0x04, 0xFF, UInt8(n >> 24), UInt8((n >> 16) & 0xff), UInt8((n >> 8) & 0xff), UInt8(n & 0xff)])
        let digest: Data, algorithm: SecKeyAlgorithm
        switch hashAlgo {
        case 8: var h = SHA256(); h.update(data: data); h.update(data: trailer); digest = Data(h.finalize()); algorithm = .rsaSignatureDigestPKCS1v15SHA256
        case 10: var h = SHA512(); h.update(data: data); h.update(data: trailer); digest = Data(h.finalize()); algorithm = .rsaSignatureDigestPKCS1v15SHA512
        default: throw Failure.unsupported("hash algorithm \(hashAlgo)")
        }
        guard Array(digest.prefix(2)) == left16 else { throw Failure.badSignature }

        let secKey = try rsaKey(key)
        let modulusBytes = key.n.drop(while: { $0 == 0 }).count
        let padded = Data(repeating: 0, count: max(0, modulusBytes - sig.count)) + sig
        var error: Unmanaged<CFError>?
        guard SecKeyVerifySignature(secKey, algorithm, digest as CFData, padded as CFData, &error) else { throw Failure.badSignature }
    }

    static func subpackets(_ b: [UInt8]) -> [(type: Int, data: Data)] {
        var i = 0, out: [(Int, Data)] = []
        while i < b.count {
            var len = Int(b[i]); i += 1
            if len >= 192 && len < 255 { guard i < b.count else { break }; len = ((len - 192) << 8) + Int(b[i]) + 192; i += 1 }
            else if len == 255 { guard i + 4 <= b.count else { break }; len = Int(b[i]) << 24 | Int(b[i+1]) << 16 | Int(b[i+2]) << 8 | Int(b[i+3]); i += 4 }
            guard len >= 1, i + len <= b.count else { break }
            out.append((Int(b[i] & 0x7f), Data(b[(i + 1)..<(i + len)])))
            i += len
        }
        return out
    }

    /// RSA public key from (n, e) via a DER RSAPublicKey structure.
    static func rsaKey(_ k: PublicKey) throws -> SecKey {
        func integer(_ d: Data) -> Data {
            var v = Data(d.drop(while: { $0 == 0 }))
            if v.isEmpty { v = Data([0]) }
            if v.first! & 0x80 != 0 { v.insert(0, at: 0) }
            return Data([0x02]) + length(v.count) + v
        }
        func length(_ n: Int) -> Data {
            if n < 128 { return Data([UInt8(n)]) }
            var bytes: [UInt8] = []; var x = n
            while x > 0 { bytes.insert(UInt8(x & 0xff), at: 0); x >>= 8 }
            return Data([0x80 | UInt8(bytes.count)] + bytes)
        }
        let body = integer(k.n) + integer(k.e)
        let der = Data([0x30]) + length(body.count) + body
        let attrs: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(der as CFData, attrs as CFDictionary, &error) else { throw Failure.malformed("RSA key") }
        return key
    }
}

/// yt-dlp's release signing key (from github.com/yt-dlp/yt-dlp/blob/master/public.key), pinned so a
/// compromised download location can't substitute its own key. Fingerprint AC0C BBE6 848D 6A87 3464 AF4E 57CF 6593 3B5A 7581.
public enum PinnedKeys {
    public static let ytDlpFingerprint = "ac0cbbe6848d6a873464af4e57cf65933b5a7581"
    public static let ytDlp = """
    -----BEGIN PGP PUBLIC KEY BLOCK-----

    mQINBGP78C4BEAD0rF9zjGPAt0thlt5C1ebzccAVX7Nb1v+eqQjk+WEZdTETVCg3
    WAM5ngArlHdm/fZqzUgO+pAYrB60GKeg7ffUDf+S0XFKEZdeRLYeAaqqKhSibVal
    DjvOBOztu3W607HLETQAqA7wTPuIt2WqmpL60NIcyr27LxqmgdN3mNvZ2iLO+bP0
    nKR/C+PgE9H4ytywDa12zMx6PmZCnVOOOu6XZEFmdUxxdQ9fFDqd9LcBKY2LDOcS
    Yo1saY0YWiZWHtzVoZu1kOzjnS5Fjq/yBHJLImDH7pNxHm7s/PnaurpmQFtDFruk
    t+2lhDnpKUmGr/I/3IHqH/X+9nPoS4uiqQ5HpblB8BK+4WfpaiEg75LnvuOPfZIP
    KYyXa/0A7QojMwgOrD88ozT+VCkKkkJ+ijXZ7gHNjmcBaUdKK7fDIEOYI63Lyc6Q
    WkGQTigFffSUXWHDCO9aXNhP3ejqFWgGMtCUsrbkcJkWuWY7q5ARy/05HbSM3K4D
    U9eqtnxmiV1WQ8nXuI9JgJQRvh5PTkny5LtxqzcmqvWO9TjHBbrs14BPEO9fcXxK
    L/CFBbzXDSvvAgArdqqlMoncQ/yicTlfL6qzJ8EKFiqW14QMTdAn6SuuZTodXCTi
    InwoT7WjjuFPKKdvfH1GP4bnqdzTnzLxCSDIEtfyfPsIX+9GI7Jkk/zZjQARAQAB
    tDdTaW1vbiBTYXdpY2tpICh5dC1kbHAgc2lnbmluZyBrZXkpIDxjb250YWN0QGdy
    dWI0ay54eXo+iQJOBBMBCgA4FiEErAy75oSNaoc0ZK9OV89lkztadYEFAmP78C4C
    GwMFCwkIBwIGFQoJCAsCBBYCAwECHgECF4AACgkQV89lkztadYEVqQ//cW7TxhXg
    7Xbh2EZQzXml0egn6j8QaV9KzGragMiShrlvTO2zXfLXqyizrFP4AspgjSn/4NrI
    8mluom+Yi+qr7DXT4BjQqIM9y3AjwZPdywe912Lxcw52NNoPZCm24I9T7ySc8lmR
    FQvZC0w4H/VTNj/2lgJ1dwMflpwvNRiWa5YzcFGlCUeDIPskLx9++AJE+xwU3LYm
    jQQsPBqpHHiTBEJzMLl+rfd9Fg4N+QNzpFkTDW3EPerLuvJniSBBwZthqxeAtw4M
    UiAXh6JvCc2hJkKCoygRfM281MeolvmsGNyQm+axlB0vyldiPP6BnaRgZlx+l6MU
    cPqgHblb7RW5j9lfr6OYL7SceBIHNv0CFrt1OnkGo/tVMwcs8LH3Ae4a7UJlIceL
    V54aRxSsZU7w4iX+PB79BWkEsQzwKrUuJVOeL4UDwWajp75OFaUqbS/slDDVXvK5
    OIeuth3mA/adjdvgjPxhRQjA3l69rRWIJDrqBSHldmRsnX6cvXTDy8wSXZgy51lP
    m4IVLHnCy9m4SaGGoAsfTZS0cC9FgjUIyTyrq9M67wOMpUxnuB0aRZgJE1DsI23E
    qdvcSNVlO+39xM/KPWUEh6b83wMn88QeW+DCVGWACQq5N3YdPnAJa50617fGbY6I
    gXIoRHXkDqe23PZ/jURYCv0sjVtjPoVC+bg=
    =bJkn
    -----END PGP PUBLIC KEY BLOCK-----
    """
}
