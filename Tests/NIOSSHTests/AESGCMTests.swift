//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import XCTest
import NIO
import CryptoKit
import NIOFoundationCompat
@testable import NIOSSH


final class AESGCMTests: XCTestCase {
    private func generateKeys(keySize: SymmetricKeySize) -> NIOSSHKeyExchangeResult {
        return NIOSSHKeyExchangeResult(initialInboundIV: .init(randomBytes: 12),
                                       initialOutboundIV: .init(randomBytes: 12),
                                       inboundEncryptionKey: SymmetricKey(size: keySize),
                                       outboundEncryptionKey: SymmetricKey(size: keySize),
                                       inboundMACKey: SymmetricKey(size: .bits128),
                                       outboundMACKey: SymmetricKey(size: .bits128))
    }

    func testSimpleAES128RoundTrip() throws {
        let initialKeys = self.generateKeys(keySize: .bits128)

        let aes128Encryptor = try assertNoThrowWithValue(AES128GCMOpenSSHTransportProtection(initialKeys: initialKeys, allocator: ByteBufferAllocator()))
        let result = try assertNoThrowWithValue(aes128Encryptor.encryptPacket(NIOSSHEncryptablePayload()))

        // This will change when we properly implement encryptable payload, but for now encryptable payload is a zero length string. Because of that,
        // we expect that we will need 15 padding bytes: one byte for the padding length, then 15 more to get out to one block size. Thus, the total
        // length of the result buffer should be 36 bytes: 4 bytes of length, 16 bytes of ciphertext, 16 bytes of tag.
        XCTAssertEqual(result.getInteger(at: 0, as: UInt32.self), 32)
        XCTAssertEqual(result.readableBytes, 36)

        // We should be able to decrypt this now.
        let aes128Decryptor = try assertNoThrowWithValue(AES128GCMOpenSSHTransportProtection(initialKeys: initialKeys.inverted, allocator: ByteBufferAllocator()))

        var resultCopy = result
        XCTAssertNoThrow(try aes128Decryptor.decryptFirstBlock(&resultCopy))
        XCTAssertEqual(resultCopy, result)

        /// After decryption the plaintext should be empty, as there was no payload.
        XCTAssertNoThrow(try aes128Decryptor.decryptAndVerifyRemainingPacket(&resultCopy))
        XCTAssertNotEqual(resultCopy, result)
        XCTAssertEqual(resultCopy.readableBytes, 0)
    }

    func testSimpleAES256RoundTrip() throws {
        let initialKeys = self.generateKeys(keySize: .bits256)

        let aes256Encryptor = try assertNoThrowWithValue(AES256GCMOpenSSHTransportProtection(initialKeys: initialKeys, allocator: ByteBufferAllocator()))
        let result = try assertNoThrowWithValue(aes256Encryptor.encryptPacket(NIOSSHEncryptablePayload()))

        // This will change when we properly implement encryptable payload, but for now encryptable payload is a zero length string. Because of that,
        // we expect that we will need 15 padding bytes: one byte for the padding length, then 15 more to get out to one block size. Thus, the total
        // length of the result buffer should be 36 bytes: 4 bytes of length, 16 bytes of ciphertext, 16 bytes of tag.
        XCTAssertEqual(result.getInteger(at: 0, as: UInt32.self), 32)
        XCTAssertEqual(result.readableBytes, 36)

        // We should be able to decrypt this now.
        let aes256Decryptor = try assertNoThrowWithValue(AES256GCMOpenSSHTransportProtection(initialKeys: initialKeys.inverted, allocator: ByteBufferAllocator()))

        var resultCopy = result
        XCTAssertNoThrow(try aes256Decryptor.decryptFirstBlock(&resultCopy))
        XCTAssertEqual(resultCopy, result)

        /// After decryption the plaintext should be empty, as there was no payload.
        XCTAssertNoThrow(try aes256Decryptor.decryptAndVerifyRemainingPacket(&resultCopy))
        XCTAssertNotEqual(resultCopy, result)
        XCTAssertEqual(resultCopy.readableBytes, 0)
    }

    func testCannotCreateWithIncorrectKeySize() throws {
        let initial128BitKeys = self.generateKeys(keySize: .bits128)

        // We want to check that each key is rejected separately.
        var initialKeys = initial128BitKeys
        initialKeys.inboundEncryptionKey = SymmetricKey(size: .bits256)
        XCTAssertThrowsError(try AES128GCMOpenSSHTransportProtection(initialKeys: initialKeys, allocator: ByteBufferAllocator())) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidKeySize)
        }

        initialKeys = initial128BitKeys
        initialKeys.outboundEncryptionKey = SymmetricKey(size: .bits256)
        XCTAssertThrowsError(try AES128GCMOpenSSHTransportProtection(initialKeys: initialKeys, allocator: ByteBufferAllocator())) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidKeySize)
        }

        let initial256BitKeys = self.generateKeys(keySize: .bits256)

        // We want to check that each key is rejected separately.
        initialKeys = initial256BitKeys
        initialKeys.inboundEncryptionKey = SymmetricKey(size: .bits128)
        XCTAssertThrowsError(try AES256GCMOpenSSHTransportProtection(initialKeys: initialKeys, allocator: ByteBufferAllocator())) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidKeySize)
        }

        initialKeys = initial256BitKeys
        initialKeys.outboundEncryptionKey = SymmetricKey(size: .bits128)
        XCTAssertThrowsError(try AES256GCMOpenSSHTransportProtection(initialKeys: initialKeys, allocator: ByteBufferAllocator())) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidKeySize)
        }
    }

    func testCannotUpdateWithIncorrectKeySize() throws {
        let initial128BitKeys = self.generateKeys(keySize: .bits128)
        let initial256BitKeys = self.generateKeys(keySize: .bits256)

        let aes128 = try assertNoThrowWithValue(AES128GCMOpenSSHTransportProtection(initialKeys: initial128BitKeys, allocator: ByteBufferAllocator()))
        let aes256 = try assertNoThrowWithValue(AES256GCMOpenSSHTransportProtection(initialKeys: initial256BitKeys, allocator: ByteBufferAllocator()))

        // We want to check that each key is rejected separately.
        var updatedKeys = initial128BitKeys
        updatedKeys.inboundEncryptionKey = SymmetricKey(size: .bits256)
        XCTAssertThrowsError(try aes128.updateKeys(updatedKeys)) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidKeySize)
        }

        updatedKeys = initial128BitKeys
        updatedKeys.outboundEncryptionKey = SymmetricKey(size: .bits256)
        XCTAssertThrowsError(try aes128.updateKeys(updatedKeys)) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidKeySize)
        }

        // We want to check that each key is rejected separately.
        updatedKeys = initial256BitKeys
        updatedKeys.inboundEncryptionKey = SymmetricKey(size: .bits128)
        XCTAssertThrowsError(try aes256.updateKeys(updatedKeys)) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidKeySize)
        }

        updatedKeys = initial256BitKeys
        updatedKeys.outboundEncryptionKey = SymmetricKey(size: .bits128)
        XCTAssertThrowsError(try aes256.updateKeys(updatedKeys)) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidKeySize)
        }
    }

    func testCannotCreateWithIncorrectNonceSize() throws {
        let initial128BitKeys = self.generateKeys(keySize: .bits128)
        let initial256BitKeys = self.generateKeys(keySize: .bits256)

        // We want to check that each nonce is rejected separately.
        var initialKeys = initial128BitKeys
        initialKeys.initialInboundIV = Array(randomBytes: 11)
        XCTAssertThrowsError(try AES128GCMOpenSSHTransportProtection(initialKeys: initialKeys, allocator: ByteBufferAllocator())) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidNonceLength)
        }

        initialKeys = initial128BitKeys
        initialKeys.initialOutboundIV = Array(randomBytes: 11)
        XCTAssertThrowsError(try AES128GCMOpenSSHTransportProtection(initialKeys: initialKeys, allocator: ByteBufferAllocator())) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidNonceLength)
        }

        initialKeys = initial128BitKeys
        initialKeys.initialInboundIV = Array(randomBytes: 13)
        XCTAssertThrowsError(try AES128GCMOpenSSHTransportProtection(initialKeys: initialKeys, allocator: ByteBufferAllocator())) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidNonceLength)
        }

        initialKeys = initial128BitKeys
        initialKeys.initialOutboundIV = Array(randomBytes: 13)
        XCTAssertThrowsError(try AES128GCMOpenSSHTransportProtection(initialKeys: initialKeys, allocator: ByteBufferAllocator())) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidNonceLength)
        }

        // We want to check that each key is rejected separately.
        initialKeys = initial256BitKeys
        initialKeys.initialInboundIV = Array(randomBytes: 11)
        XCTAssertThrowsError(try AES256GCMOpenSSHTransportProtection(initialKeys: initialKeys, allocator: ByteBufferAllocator())) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidNonceLength)
        }

        initialKeys = initial256BitKeys
        initialKeys.initialOutboundIV = Array(randomBytes: 11)
        XCTAssertThrowsError(try AES256GCMOpenSSHTransportProtection(initialKeys: initialKeys, allocator: ByteBufferAllocator())) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidNonceLength)
        }

        initialKeys = initial256BitKeys
        initialKeys.initialInboundIV = Array(randomBytes: 13)
        XCTAssertThrowsError(try AES256GCMOpenSSHTransportProtection(initialKeys: initialKeys, allocator: ByteBufferAllocator())) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidNonceLength)
        }

        initialKeys = initial256BitKeys
        initialKeys.initialOutboundIV = Array(randomBytes: 13)
        XCTAssertThrowsError(try AES256GCMOpenSSHTransportProtection(initialKeys: initialKeys, allocator: ByteBufferAllocator())) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidNonceLength)
        }
    }

    func testCannotUpdateWithIncorrectNonceSize() throws {
        let initial128BitKeys = self.generateKeys(keySize: .bits128)
        let initial256BitKeys = self.generateKeys(keySize: .bits256)

        let aes128 = try assertNoThrowWithValue(AES128GCMOpenSSHTransportProtection(initialKeys: initial128BitKeys, allocator: ByteBufferAllocator()))
        let aes256 = try assertNoThrowWithValue(AES256GCMOpenSSHTransportProtection(initialKeys: initial256BitKeys, allocator: ByteBufferAllocator()))

        // We want to check that each nonce is rejected separately.
        var updatedKeys = initial128BitKeys
        updatedKeys.initialInboundIV = Array(randomBytes: 11)
        XCTAssertThrowsError(try aes128.updateKeys(updatedKeys)) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidNonceLength)
        }

        updatedKeys = initial128BitKeys
        updatedKeys.initialOutboundIV = Array(randomBytes: 11)
        XCTAssertThrowsError(try aes128.updateKeys(updatedKeys)) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidNonceLength)
        }

        updatedKeys = initial128BitKeys
        updatedKeys.initialInboundIV = Array(randomBytes: 13)
        XCTAssertThrowsError(try aes128.updateKeys(updatedKeys)) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidNonceLength)
        }

        updatedKeys = initial128BitKeys
        updatedKeys.initialOutboundIV = Array(randomBytes: 13)
        XCTAssertThrowsError(try aes128.updateKeys(updatedKeys)) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidNonceLength)
        }

        updatedKeys = initial256BitKeys
        updatedKeys.initialInboundIV = Array(randomBytes: 11)
        XCTAssertThrowsError(try aes256.updateKeys(updatedKeys)) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidNonceLength)
        }

        updatedKeys = initial256BitKeys
        updatedKeys.initialOutboundIV = Array(randomBytes: 11)
        XCTAssertThrowsError(try aes256.updateKeys(updatedKeys)) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidNonceLength)
        }

        updatedKeys = initial256BitKeys
        updatedKeys.initialInboundIV = Array(randomBytes: 13)
        XCTAssertThrowsError(try aes256.updateKeys(updatedKeys)) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidNonceLength)
        }

        updatedKeys = initial256BitKeys
        updatedKeys.initialOutboundIV = Array(randomBytes: 13)
        XCTAssertThrowsError(try aes256.updateKeys(updatedKeys)) { error in
            XCTAssertEqual(error as? NIOSSHError, .invalidNonceLength)
        }
    }

    func testDecryptingInvalidCiphertextLengthsAES128() throws {
        // The ciphertext can be an invalid length if it is either too short (less than 36 bytes),
        // or if it is not 4 bytes larger than a multiple of 16 (the block size and the tag size).
        // To verify this, we check all sizes smaller than 36 bytes, and then the non-block sizes
        // up to the next multiple of the block size (52 bytes).
        let invalidSizes = Array(0..<36) + Array(37..<52)

        let aes128 = try assertNoThrowWithValue(AES128GCMOpenSSHTransportProtection(initialKeys: self.generateKeys(keySize: .bits128),
                                                                                    allocator: ByteBufferAllocator()))
        var buffer = ByteBufferAllocator().buffer(capacity: 52)

        for ciphertextSize in invalidSizes {
            buffer.clear()
            buffer.writeBytes(repeatElement(42, count: ciphertextSize))

            XCTAssertThrowsError(try aes128.decryptAndVerifyRemainingPacket(&buffer)) { error in
                XCTAssertEqual(error as? NIOSSHError, .invalidEncryptedPacketLength)
            }
        }
    }

    func testDecryptingInvalidCiphertextLengthsAES256() throws {
        // The ciphertext can be an invalid length if it is either too short (less than 36 bytes),
        // or if it is not 4 bytes larger than a multiple of 16 (the block size and the tag size).
        // To verify this, we check all sizes smaller than 36 bytes, and then the non-block sizes
        // up to the next multiple of the block size (52 bytes).
        let invalidSizes = Array(0..<36) + Array(37..<52)

        let aes256 = try assertNoThrowWithValue(AES256GCMOpenSSHTransportProtection(initialKeys: self.generateKeys(keySize: .bits256),
                                                                                    allocator: ByteBufferAllocator()))
        var buffer = ByteBufferAllocator().buffer(capacity: 52)

        for ciphertextSize in invalidSizes {
            buffer.clear()
            buffer.writeBytes(repeatElement(42, count: ciphertextSize))

            XCTAssertThrowsError(try aes256.decryptAndVerifyRemainingPacket(&buffer)) { error in
                XCTAssertEqual(error as? NIOSSHError, .invalidEncryptedPacketLength)
            }
        }
    }

    func testExcessPaddingAES128() throws {
        // This is an annoying test, but we're going to generate a packet with invalid SSH padding length bytes.
        // Specifically, the padding length byte is going to be larger than the amount of padding we actually have.
        // For the zero-data packet, we will have 15 bytes of padding (plus the padding length), and we're going
        // to claim to have 16 bytes.
        var buffer = ByteBufferAllocator().buffer(capacity: 1024)
        buffer.writeInteger(UInt32(36))  // We need the length bytes in order to authenticate them.
        buffer.writeInteger(UInt8(16))
        buffer.writeBytes(repeatElement(0, count: 15))

        // We now need to turn this into an SSH packet. This is sadly just reproducing the encryption logic.
        let keys = self.generateKeys(keySize: .bits128)
        let box = try assertNoThrowWithValue(AES.GCM.seal(buffer.viewBytes(at: 4, length: 16)!,
                                                          using: keys.inboundEncryptionKey,
                                                          nonce: try AES.GCM.Nonce(data: keys.initialInboundIV),
                                                          authenticating: buffer.viewBytes(at: 0, length: 4)!))
        let writtenBytes = buffer.setBytes(box.ciphertext, at: 4)
        XCTAssertEqual(writtenBytes, 16)

        buffer.writeBytes(box.tag)
        XCTAssertEqual(buffer.readableBytes, 36)

        // We can now attempt to decrypt this packet.
        let aes128 = try assertNoThrowWithValue(AES128GCMOpenSSHTransportProtection(initialKeys: keys,
                                                                                    allocator: ByteBufferAllocator()))
        XCTAssertThrowsError(try aes128.decryptAndVerifyRemainingPacket(&buffer)) { error in
            XCTAssertEqual(error as? NIOSSHError, .excessPadding)
        }
    }

    func testExcessPaddingAES256() throws {
        // This is an annoying test, but we're going to generate a packet with invalid SSH padding length bytes.
        // Specifically, the padding length byte is going to be larger than the amount of padding we actually have.
        // For the zero-data packet, we will have 15 bytes of padding (plus the padding length), and we're going
        // to claim to have 16 bytes.
        var buffer = ByteBufferAllocator().buffer(capacity: 1024)
        buffer.writeInteger(UInt32(36))  // We need the length bytes in order to authenticate them.
        buffer.writeInteger(UInt8(16))
        buffer.writeBytes(repeatElement(0, count: 15))

        // We now need to turn this into an SSH packet. This is sadly just reproducing the encryption logic.
        let keys = self.generateKeys(keySize: .bits256)
        let box = try assertNoThrowWithValue(AES.GCM.seal(buffer.viewBytes(at: 4, length: 16)!,
                                                          using: keys.inboundEncryptionKey,
                                                          nonce: try AES.GCM.Nonce(data: keys.initialInboundIV),
                                                          authenticating: buffer.viewBytes(at: 0, length: 4)!))
        let writtenBytes = buffer.setBytes(box.ciphertext, at: 4)
        XCTAssertEqual(writtenBytes, 16)

        buffer.writeBytes(box.tag)
        XCTAssertEqual(buffer.readableBytes, 36)

        // We can now attempt to decrypt this packet.
        let aes256 = try assertNoThrowWithValue(AES256GCMOpenSSHTransportProtection(initialKeys: keys,
                                                                                    allocator: ByteBufferAllocator()))
        XCTAssertThrowsError(try aes256.decryptAndVerifyRemainingPacket(&buffer)) { error in
            XCTAssertEqual(error as? NIOSSHError, .excessPadding)
        }
    }

    func testInsufficientPaddingAES128() throws {
        // This is an annoying test, but we're going to generate a packet with invalid SSH padding length bytes.
        // Specifically, the padding length byte is going to be too small: specifically, 3. For this packet, we
        // are going to have 12 bytes of data, a 1 byte padding length field, and 3 bytes of padding. This is one
        // block size, which is acceptable.
        var buffer = ByteBufferAllocator().buffer(capacity: 1024)
        buffer.writeInteger(UInt32(36))  // We need the length bytes in order to authenticate them.
        buffer.writeInteger(UInt8(3))
        buffer.writeBytes(repeatElement(0, count: 15))

        // We now need to turn this into an SSH packet. This is sadly just reproducing the encryption logic.
        let keys = self.generateKeys(keySize: .bits128)
        let box = try assertNoThrowWithValue(AES.GCM.seal(buffer.viewBytes(at: 4, length: 16)!,
                                                          using: keys.inboundEncryptionKey,
                                                          nonce: try AES.GCM.Nonce(data: keys.initialInboundIV),
                                                          authenticating: buffer.viewBytes(at: 0, length: 4)!))
        let writtenBytes = buffer.setBytes(box.ciphertext, at: 4)
        XCTAssertEqual(writtenBytes, 16)

        buffer.writeBytes(box.tag)
        XCTAssertEqual(buffer.readableBytes, 36)

        // We can now attempt to decrypt this packet.
        let aes128 = try assertNoThrowWithValue(AES128GCMOpenSSHTransportProtection(initialKeys: keys,
                                                                                    allocator: ByteBufferAllocator()))
        XCTAssertThrowsError(try aes128.decryptAndVerifyRemainingPacket(&buffer)) { error in
            XCTAssertEqual(error as? NIOSSHError, .insufficientPadding)
        }
    }

    func testInsufficientPaddingAES256() throws {
        // This is an annoying test, but we're going to generate a packet with invalid SSH padding length bytes.
        // Specifically, the padding length byte is going to be too small: specifically, 3. For this packet, we
        // are going to have 12 bytes of data, a 1 byte padding length field, and 3 bytes of padding. This is one
        // block size, which is acceptable.
        var buffer = ByteBufferAllocator().buffer(capacity: 1024)
        buffer.writeInteger(UInt32(36))  // We need the length bytes in order to authenticate them.
        buffer.writeInteger(UInt8(3))
        buffer.writeBytes(repeatElement(0, count: 15))

        // We now need to turn this into an SSH packet. This is sadly just reproducing the encryption logic.
        let keys = self.generateKeys(keySize: .bits256)
        let box = try assertNoThrowWithValue(AES.GCM.seal(buffer.viewBytes(at: 4, length: 16)!,
                                                          using: keys.inboundEncryptionKey,
                                                          nonce: try AES.GCM.Nonce(data: keys.initialInboundIV),
                                                          authenticating: buffer.viewBytes(at: 0, length: 4)!))
        let writtenBytes = buffer.setBytes(box.ciphertext, at: 4)
        XCTAssertEqual(writtenBytes, 16)

        buffer.writeBytes(box.tag)
        XCTAssertEqual(buffer.readableBytes, 36)

        // We can now attempt to decrypt this packet.
        let aes256 = try assertNoThrowWithValue(AES256GCMOpenSSHTransportProtection(initialKeys: keys,
                                                                                    allocator: ByteBufferAllocator()))
        XCTAssertThrowsError(try aes256.decryptAndVerifyRemainingPacket(&buffer)) { error in
            XCTAssertEqual(error as? NIOSSHError, .insufficientPadding)
        }
    }

    func testBasicNonceManagement() throws {
        let initialNonce: [UInt8] = [1, 1, 1, 1, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE]
        var representedNonce = try assertNoThrowWithValue(SSHAESGCMNonce(keyExchangeResult: initialNonce))

        XCTAssertEqual(Array(representedNonce), initialNonce)
        representedNonce.withUnsafeBytes { innerPtr in
            XCTAssertEqual(Array(innerPtr), initialNonce)
        }

        XCTAssertEqual(representedNonce.count, 12)

        representedNonce.increment()
        var incrementedNonce = initialNonce
        incrementedNonce[11] = 0xFF
        XCTAssertEqual(Array(representedNonce), incrementedNonce)
        representedNonce.withUnsafeBytes { innerPtr in
            XCTAssertEqual(Array(innerPtr), incrementedNonce)
        }

        representedNonce.increment()
        incrementedNonce = [1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0]
        XCTAssertEqual(Array(representedNonce), incrementedNonce)
        representedNonce.withUnsafeBytes { innerPtr in
            XCTAssertEqual(Array(innerPtr), incrementedNonce)
        }
    }
}


extension Array where Element == UInt8 {
    fileprivate init(randomBytes: Int) {
        var rng = CSPRNG()
        self = (0..<randomBytes).map { _ in rng.next() }
    }
}


extension NIOSSHKeyExchangeResult {
    var inverted: NIOSSHKeyExchangeResult {
        return NIOSSHKeyExchangeResult(initialInboundIV: self.initialOutboundIV,
                                       initialOutboundIV: self.initialInboundIV,
                                       inboundEncryptionKey: self.outboundEncryptionKey,
                                       outboundEncryptionKey: self.inboundEncryptionKey,
                                       inboundMACKey: self.outboundMACKey,
                                       outboundMACKey: self.inboundMACKey)
    }
}