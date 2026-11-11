package com.ondsc.trevix

import java.math.BigInteger
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Las mismas operaciones que lib/core/e2ee.dart (paquete cryptography) para descifrar y responder desde las
 * notificaciones: X25519 (RFC 7748), HKDF-SHA256 con sal de 32 ceros y AES-256-GCM como nonce(12) ‖ cifrado ‖
 * etiqueta(16). Sin dependencias de Android para poder probarlo contra la app con kotlinc.
 */
internal object E2eeCrypto {
    private val P: BigInteger = BigInteger.ONE.shiftLeft(255).subtract(BigInteger.valueOf(19))
    private val A24: BigInteger = BigInteger.valueOf(121665)
    private val BASE = ByteArray(32).also { it[0] = 9 }
    private val random = SecureRandom()

    fun randomBytes(n: Int) = ByteArray(n).also(random::nextBytes)

    fun publicKey(seed: ByteArray) = x25519(seed, BASE)

    fun x25519(scalar: ByteArray, u: ByteArray): ByteArray {
        require(scalar.size == 32 && u.size == 32)
        val k = scalar.copyOf()
        k[0] = (k[0].toInt() and 248).toByte()
        k[31] = ((k[31].toInt() and 127) or 64).toByte()
        val n = decode(k)
        val point = u.copyOf()
        point[31] = (point[31].toInt() and 127).toByte()
        val x1 = decode(point).mod(P)
        var x2 = BigInteger.ONE
        var z2 = BigInteger.ZERO
        var x3 = x1
        var z3 = BigInteger.ONE
        var swap = false
        for (t in 254 downTo 0) {
            val bit = n.testBit(t)
            if (swap != bit) {
                x2 = x3.also { x3 = x2 }
                z2 = z3.also { z3 = z2 }
            }
            swap = bit
            val a = x2.add(z2).mod(P)
            val aa = a.multiply(a).mod(P)
            val b = x2.subtract(z2).mod(P)
            val bb = b.multiply(b).mod(P)
            val e = aa.subtract(bb).mod(P)
            val c = x3.add(z3).mod(P)
            val d = x3.subtract(z3).mod(P)
            val da = d.multiply(a).mod(P)
            val cb = c.multiply(b).mod(P)
            val sum = da.add(cb)
            val diff = da.subtract(cb)
            x3 = sum.multiply(sum).mod(P)
            z3 = x1.multiply(diff.multiply(diff)).mod(P)
            x2 = aa.multiply(bb).mod(P)
            z2 = e.multiply(aa.add(A24.multiply(e))).mod(P)
        }
        if (swap) {
            x2 = x3.also { x3 = x2 }
            z2 = z3.also { z3 = z2 }
        }
        return encode(x2.multiply(z2.modPow(P.subtract(BigInteger.valueOf(2)), P)).mod(P))
    }

    private fun decode(le: ByteArray) = BigInteger(1, le.reversedArray())

    private fun encode(n: BigInteger): ByteArray {
        val be = n.toByteArray()
        return ByteArray(32) { i -> be.getOrElse(be.size - 1 - i) { 0 } }
    }

    fun hkdf(ikm: ByteArray, info: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(ByteArray(32), "HmacSHA256"))
        val prk = mac.doFinal(ikm)
        mac.init(SecretKeySpec(prk, "HmacSHA256"))
        mac.update(info)
        mac.update(1.toByte())
        return mac.doFinal()
    }

    fun seal(key: ByteArray, plain: ByteArray, aad: ByteArray): ByteArray {
        val nonce = randomBytes(12)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        cipher.updateAAD(aad)
        return nonce + cipher.doFinal(plain)
    }

    /** Lanza una excepción si la clave no corresponde o el contenido fue alterado. */
    fun open(key: ByteArray, box: ByteArray, aad: ByteArray): ByteArray {
        require(box.size >= 12 + 16)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, box, 0, 12))
        cipher.updateAAD(aad)
        return cipher.doFinal(box, 12, box.size - 12)
    }

    fun messageAad(conversation: Long, epoch: Int, sender: Long) = "msg:$conversation:$epoch:$sender".toByteArray(Charsets.UTF_8)

    private fun wrapInfo(conversation: Long, epoch: Int, recipient: Long) =
        "trevix-wrap:$conversation:$epoch:$recipient".toByteArray(Charsets.UTF_8)

    /** Clave del chat cifrada para un participante: efímera(32) ‖ nonce ‖ cifrado ‖ etiqueta. */
    fun wrap(seed: ByteArray, conversation: Long, epoch: Int, recipient: Long, recipientPublic: ByteArray, chatKey: ByteArray): ByteArray {
        val ephemeral = randomBytes(32)
        val info = wrapInfo(conversation, epoch, recipient)
        val k = hkdf(x25519(ephemeral, recipientPublic) + x25519(seed, recipientPublic), info)
        return publicKey(ephemeral) + seal(k, chatKey, info)
    }

    fun unwrap(seed: ByteArray, conversation: Long, epoch: Int, me: Long, wrapped: ByteArray, wrapperPublic: ByteArray): ByteArray? {
        if (wrapped.size < 32 + 12 + 16 || wrapperPublic.size != 32) return null
        return try {
            val info = wrapInfo(conversation, epoch, me)
            val k = hkdf(x25519(seed, wrapped.copyOfRange(0, 32)) + x25519(seed, wrapperPublic), info)
            open(k, wrapped.copyOfRange(32, wrapped.size), info)
        } catch (_: Exception) {
            null
        }
    }
}
