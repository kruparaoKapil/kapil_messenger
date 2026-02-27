import 'package:encrypt/encrypt.dart';

class EncryptionService {
  // A static 32-byte key for AES-256 encryption.
  // In a real LAN messenger without a server, users often configure a "Network Key".
  // For this project, we'll use a predefined key.
  static final _key = Key.fromUtf8('kapil_messenger_32_byte_secret_k');
  static final _iv = IV.fromLength(16);
  static final _encrypter = Encrypter(AES(_key));

  static String encrypt(String plainText) {
    try {
      return _encrypter.encrypt(plainText, iv: _iv).base64;
    } catch (e) {
      print("Encryption error: $e");
      return plainText;
    }
  }

  static String decrypt(String encryptedText) {
    try {
      return _encrypter.decrypt64(encryptedText, iv: _iv);
    } catch (e) {
      print("Decryption error: $e");
      return encryptedText;
    }
  }
}
