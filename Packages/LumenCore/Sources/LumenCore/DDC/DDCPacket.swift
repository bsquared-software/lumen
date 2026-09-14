/// Why a DDC/CI "Get VCP Feature" reply was rejected.
public enum DDCError: Error, Equatable, Sendable {
    case tooShort
    case badChecksum
    case wrongOpcode
    /// The monitor answered but does not support this VCP code.
    case unsupported
    case vcpMismatch
}

/// A VCP feature value as reported by a monitor, e.g. brightness `19` of `50`.
public struct VCPValue: Equatable, Sendable {
    public let current: UInt16
    public let maximum: UInt16

    public init(current: UInt16, maximum: UInt16) {
        self.current = current
        self.maximum = maximum
    }

    /// `current / maximum`, clamped to `0...1`. Samsung monitors report a maximum of 50, so
    /// Lumen always works in this normalised range.
    public var normalised: Double {
        maximum == 0 ? 0 : min(1, Double(current) / Double(maximum))
    }

    public static func raw(forNormalised value: Double, maximum: UInt16) -> UInt16 {
        UInt16((min(1, max(0, value)) * Double(maximum)).rounded())
    }
}

/// DDC/CI wire format for the two messages Lumen needs: get and set a VCP feature.
///
/// Requests are written to I2C chip `0x37` at data address `0x51`. The checksum covers the
/// destination address (`0x6E`), the source address (`0x51`) and the payload. Replies carry
/// their own checksum seeded with `0x50`.
public enum DDCPacket {
    public static let chipAddress: UInt32 = 0x37
    public static let dataAddress: UInt32 = 0x51
    public static let brightnessVCP: UInt8 = 0x10
    public static let contrastVCP: UInt8 = 0x12
    /// Length of a "Get VCP Feature" reply.
    public static let replyLength = 11

    private static let requestSeed: UInt8 = 0x6E ^ 0x51

    public static func getVCPRequest(_ vcp: UInt8) -> [UInt8] {
        withChecksum([0x82, 0x01, vcp])
    }

    public static func setVCPRequest(_ vcp: UInt8, value: UInt16) -> [UInt8] {
        withChecksum([0x84, 0x03, vcp, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    public static func parseGetVCPReply(_ reply: [UInt8], vcp: UInt8) throws(DDCError) -> VCPValue {
        guard reply.count >= replyLength else { throw .tooShort }
        guard replyChecksum(reply[0..<10]) == reply[10] else { throw .badChecksum }
        guard reply[2] == 0x02 else { throw .wrongOpcode }
        guard reply[3] == 0x00 else { throw .unsupported }
        guard reply[4] == vcp else { throw .vcpMismatch }
        return VCPValue(
            current: UInt16(reply[8]) << 8 | UInt16(reply[9]),
            maximum: UInt16(reply[6]) << 8 | UInt16(reply[7])
        )
    }

    static func replyChecksum(_ bytes: ArraySlice<UInt8>) -> UInt8 {
        bytes.reduce(0x50, ^)
    }

    private static func withChecksum(_ payload: [UInt8]) -> [UInt8] {
        payload + [payload.reduce(requestSeed, ^)]
    }
}
