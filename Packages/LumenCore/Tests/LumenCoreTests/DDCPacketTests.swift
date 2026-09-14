import Testing
@testable import LumenCore

@Suite struct DDCPacketTests {
    @Test func getRequestForContrast() {
        #expect(DDCPacket.getVCPRequest(DDCPacket.contrastVCP) == [0x82, 0x01, 0x12, 0xAE])
    }

    // Real contrast replies from 2026-09-14: LS32D70xE at 50 of 50, G81SF at 45 of 50.
    @Test func parsesRealContrastReplies() throws {
        let ls32: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x12, 0x00, 0x00, 0x32, 0x00, 0x32, 0xA6]
        let g81: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x12, 0x00, 0x00, 0x32, 0x00, 0x2D, 0xB9]
        #expect(try DDCPacket.parseGetVCPReply(ls32, vcp: 0x12) == VCPValue(current: 50, maximum: 50))
        #expect(try DDCPacket.parseGetVCPReply(g81, vcp: 0x12) == VCPValue(current: 45, maximum: 50))
    }

    @Test func getRequestForBrightness() {
        #expect(DDCPacket.getVCPRequest(0x10) == [0x82, 0x01, 0x10, 0xAC])
    }

    @Test func setRequestForBrightness25() {
        #expect(DDCPacket.setVCPRequest(0x10, value: 25) == [0x84, 0x03, 0x10, 0x00, 0x19, 0xB1])
    }

    // Real replies captured from the LS32D70xE and Odyssey G81SF on 2026-09-14.
    @Test func parsesRealReplyAt19of50() throws {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x32, 0x00, 0x13, 0x85, 0x00]
        #expect(try DDCPacket.parseGetVCPReply(reply, vcp: 0x10) == VCPValue(current: 19, maximum: 50))
    }

    @Test func parsesRealReplyAt50of50() throws {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x32, 0x00, 0x32, 0xA4]
        #expect(try DDCPacket.parseGetVCPReply(reply, vcp: 0x10) == VCPValue(current: 50, maximum: 50))
    }

    @Test func rejectsBadChecksum() {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x32, 0x00, 0x13, 0x00]
        #expect(throws: DDCError.badChecksum) { try DDCPacket.parseGetVCPReply(reply, vcp: 0x10) }
    }

    @Test func rejectsWrongOpcode() {
        var reply: [UInt8] = [0x6E, 0x88, 0x03, 0x00, 0x10, 0x00, 0x00, 0x32, 0x00, 0x13, 0x00]
        reply[10] = DDCPacket.replyChecksum(reply[0..<10])
        #expect(throws: DDCError.wrongOpcode) { try DDCPacket.parseGetVCPReply(reply, vcp: 0x10) }
    }

    @Test func rejectsUnsupportedResultCode() {
        var reply: [UInt8] = [0x6E, 0x88, 0x02, 0x01, 0x10, 0x00, 0x00, 0x32, 0x00, 0x13, 0x00]
        reply[10] = DDCPacket.replyChecksum(reply[0..<10])
        #expect(throws: DDCError.unsupported) { try DDCPacket.parseGetVCPReply(reply, vcp: 0x10) }
    }

    @Test func rejectsShortReply() {
        #expect(throws: DDCError.tooShort) { try DDCPacket.parseGetVCPReply([0x6E, 0x88], vcp: 0x10) }
    }

    @Test func rejectsMismatchedVCP() {
        var reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x12, 0x00, 0x00, 0x32, 0x00, 0x13, 0x00]
        reply[10] = DDCPacket.replyChecksum(reply[0..<10])
        #expect(throws: DDCError.vcpMismatch) { try DDCPacket.parseGetVCPReply(reply, vcp: 0x10) }
    }

    @Test func normalisesCurrentAgainstReportedMaximum() {
        #expect(VCPValue(current: 25, maximum: 50).normalised == 0.5)
        #expect(VCPValue(current: 7, maximum: 0).normalised == 0)
    }

    @Test func convertsNormalisedBackToRawClamped() {
        #expect(VCPValue.raw(forNormalised: 0.1, maximum: 50) == 5)
        #expect(VCPValue.raw(forNormalised: 1.4, maximum: 50) == 50)
        #expect(VCPValue.raw(forNormalised: -0.2, maximum: 50) == 0)
    }
}
