package com.ondsc.trevix

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Chats cifrados en las notificaciones: muestra el mensaje descifrado y permite responder cifrando la respuesta.
 * La app (lib/core/e2ee.dart) entrega aquí la clave privada de la cuenta cuando la carga con el PIN; se guarda en
 * las preferencias privadas cifrada con una clave AES del Android Keystore, que no sale del teléfono. Se borra al
 * cerrar sesión, al cambiar de cuenta y si la clave de la cuenta cambia.
 */
object E2ee {
    private const val ALIAS = "trevix_e2ee"
    private const val UID = "e2ee_uid"
    private const val KEY_ID = "e2ee_kid"
    private const val SEED = "e2ee_seed"

    private class Identity(val uid: Long, val keyId: Long, val seed: ByteArray)
    private class Member(val userId: Long, val keyId: Long?, val publicKey: String?)
    private class ChatKeys(val e2ee: Boolean, val epoch: Int, val stale: Boolean, val members: List<Member>) {
        val everyoneHasKey get() = members.isNotEmpty() && members.all { it.publicKey != null }
    }

    @Volatile private var identity: Identity? = null
    private val epochKeys = HashMap<Long, HashMap<Int, ByteArray>>()

    private fun b64(bytes: ByteArray): String = Base64.encodeToString(bytes, Base64.NO_WRAP)
    private fun unb64(text: String): ByteArray = Base64.decode(text, Base64.NO_WRAP)

    fun store(c: Context, uid: Long, keyId: Long, seedB64: String) {
        val seed = try {
            unb64(seedB64)
        } catch (_: Exception) {
            return
        }
        if (seed.size != 32 || uid <= 0) return
        val current = load(c)
        if (current != null && current.uid == uid && current.keyId == keyId && current.seed.contentEquals(seed)) return
        val sealed = try {
            protect(seed)
        } catch (_: Exception) {
            return
        }
        Push.prefs(c).edit().putLong(UID, uid).putLong(KEY_ID, keyId).putString(SEED, b64(sealed)).apply()
        identity = Identity(uid, keyId, seed)
        synchronized(epochKeys) { epochKeys.clear() }
    }

    fun forget(c: Context) {
        Push.prefs(c).edit().remove(UID).remove(KEY_ID).remove(SEED).apply()
        clearMemory()
    }

    fun clearMemory() {
        identity = null
        synchronized(epochKeys) { epochKeys.clear() }
    }

    /** La clave guardada, solo si es de la cuenta cuyos avisos se están consultando (meta.uid de GET me/push). */
    private fun current(c: Context): Identity? {
        val id = load(c) ?: return null
        val account = Push.prefs(c).getLong("uid", 0)
        return if (account == id.uid) id else null
    }

    fun ready(c: Context) = current(c) != null

    private fun load(c: Context): Identity? {
        identity?.let { return it }
        val p = Push.prefs(c)
        val sealed = p.getString(SEED, null) ?: return null
        return try {
            Identity(p.getLong(UID, 0), p.getLong(KEY_ID, 0), reveal(unb64(sealed))).also { identity = it }
        } catch (_: Exception) {
            null
        }
    }

    private fun keystoreKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return gen.generateKey()
    }

    private fun protect(seed: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, keystoreKey())
        return cipher.iv + cipher.doFinal(seed)
    }

    private fun reveal(sealed: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, keystoreKey(), GCMParameterSpec(128, sealed, 0, 12))
        return cipher.doFinal(sealed, 12, sealed.size - 12)
    }

    private fun cached(conversation: Long, epoch: Int) = synchronized(epochKeys) { epochKeys[conversation]?.get(epoch) }

    private fun keep(conversation: Long, epoch: Int, key: ByteArray) =
        synchronized(epochKeys) { epochKeys.getOrPut(conversation) { HashMap() }[epoch] = key }

    /** GET conversations/{id}/keys: participantes y las claves del chat cifradas para esta cuenta (se descifran aquí). */
    private fun chatKeys(c: Context, conversation: Long, id: Identity): ChatKeys {
        val res = Push.request(c, "GET", "conversations/$conversation/keys")
        if (res.code != 200) throw IllegalStateException("HTTP ${res.code}")
        val data = JSONObject(res.body).getJSONObject("data")
        val wraps = data.optJSONArray("wraps") ?: JSONArray()
        for (i in 0 until wraps.length()) {
            val w = wraps.getJSONObject(i)
            val epoch = w.optInt("epoch")
            if (w.optLong("key_id") != id.keyId || cached(conversation, epoch) != null) continue
            val key = try {
                E2eeCrypto.unwrap(id.seed, conversation, epoch, id.uid, unb64(w.optString("wrapped")), unb64(w.optString("wrapper_public")))
            } catch (_: Exception) {
                null
            }
            if (key != null) keep(conversation, epoch, key)
        }
        val list = data.optJSONArray("members") ?: JSONArray()
        val members = (0 until list.length()).map { i ->
            val m = list.getJSONObject(i)
            Member(
                m.optLong("user_id"),
                if (m.isNull("key_id")) null else m.optLong("key_id"),
                if (m.isNull("public_key")) null else m.optString("public_key"),
            )
        }
        return ChatKeys(data.optBoolean("e2ee"), data.optInt("epoch"), data.optBoolean("stale"), members)
    }

    /** Resumen en una línea del mensaje descifrado (como E2eePayload.summary), o null si no se puede descifrar. */
    fun summary(c: Context, conversation: Long, sealed: JSONObject): String? {
        val id = current(c) ?: return null
        val epoch = sealed.optInt("epoch")
        val sender = sealed.optLong("sender_id")
        return try {
            val key = cached(conversation, epoch) ?: run {
                chatKeys(c, conversation, id)
                cached(conversation, epoch)
            } ?: return null
            val clear = E2eeCrypto.open(key, unb64(sealed.optString("ciphertext")), E2eeCrypto.messageAad(conversation, epoch, sender))
            describe(JSONObject(String(clear, Charsets.UTF_8)))
        } catch (_: Exception) {
            null
        }
    }

    private fun describe(p: JSONObject): String? {
        val body = p.optString("b").replace(Regex("\\s+"), " ").trim()
        val text = when (p.optString("t", "text")) {
            "image" -> if (body.isNotEmpty()) "📷 $body" else "📷 Foto"
            "video" -> if (body.isNotEmpty()) "🎥 $body" else "🎥 Video"
            "voice" -> "🎤 Nota de voz"
            "gif" -> if (p.optJSONObject("g")?.optString("kind") == "sticker") "Sticker" else "GIF"
            "location" -> "📍 Ubicación"
            else -> body
        }
        if (text.isEmpty()) return null
        return if (text.length > 300) text.take(299) + "…" else text
    }

    /**
     * Responde desde la notificación como lo haría la app (lib/core/chat_sender.dart): cifrado si el chat ya lo está
     * o si todos los participantes tienen clave; si no, en claro. Devuelve el código HTTP del envío.
     */
    fun reply(c: Context, conversation: Long, text: String): Int {
        val id = current(c)
        val keys = id?.let { chatKeys(c, conversation, it) }
        if (id == null || keys == null || (!keys.e2ee && !keys.everyoneHasKey)) {
            return Push.request(c, "POST", "conversations/$conversation/messages", JSONObject().put("body", text)).code
        }
        val payload = JSONObject().put("v", 1).put("t", "text").put("b", text).toString().toByteArray(Charsets.UTF_8)
        var code = 0
        for (attempt in 0 until 3) {
            val (epoch, key) = sendingKey(c, conversation, id, if (attempt == 0) keys else null)
            val ciphertext = E2eeCrypto.seal(key, payload, E2eeCrypto.messageAad(conversation, epoch, id.uid))
            code = Push.request(
                c, "POST", "conversations/$conversation/messages",
                JSONObject().put("e2ee_epoch", epoch).put("ciphertext", b64(ciphertext)),
            ).code
            if (code != 409) break
        }
        return code
    }

    /** Época vigente y su clave; si no hay o ya no cubre a los participantes, crea una nueva y la reparte. */
    private fun sendingKey(c: Context, conversation: Long, id: Identity, fresh: ChatKeys?): Pair<Int, ByteArray> {
        var known = fresh
        for (attempt in 0 until 3) {
            val keys = known ?: chatKeys(c, conversation, id)
            known = null
            val current = cached(conversation, keys.epoch)
            if (keys.epoch > 0 && !keys.stale && current != null) return keys.epoch to current
            val epoch = keys.epoch + 1
            val chatKey = E2eeCrypto.randomBytes(32)
            val wraps = JSONArray()
            for (m in keys.members) {
                if (m.publicKey == null || m.keyId == null) continue
                val wrapped = E2eeCrypto.wrap(id.seed, conversation, epoch, m.userId, unb64(m.publicKey), chatKey)
                wraps.put(JSONObject().put("user_id", m.userId).put("key_id", m.keyId).put("wrapped", b64(wrapped)))
            }
            val res = Push.request(c, "POST", "conversations/$conversation/keys", JSONObject().put("epoch", epoch).put("keys", wraps))
            if (res.code in 200..299) {
                keep(conversation, epoch, chatKey)
                return epoch to chatKey
            }
            if (res.code != 409) throw IllegalStateException("HTTP ${res.code}")
        }
        throw IllegalStateException("Las claves del chat cambiaron")
    }
}
