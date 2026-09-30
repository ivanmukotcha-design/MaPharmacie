import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class BackupCipher {
  static const maxFileBytes = 32 * 1024 * 1024;
  static const maxPlainBytes = 23 * 1024 * 1024;
  static const iterations = 600000;
  static const _format = 'pharmaflow-backup';
  static final _aad = utf8.encode(
    'pharmaflow-backup:v2:aes-256-gcm:pbkdf2-sha256:600000',
  );

  static Map<String, dynamic> readEnvelope(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxFileBytes) {
      throw const FormatException(
        'Le fichier est vide ou dépasse la limite de 32 Mo.',
      );
    }
    try {
      return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
    } catch (_) {
      throw const FormatException(
        'Ce fichier n’est pas une sauvegarde PharmaFlow valide.',
      );
    }
  }

  static Future<Uint8List> encrypt(String contents, String password) async {
    if (password.runes.length < 12 || password.trim().isEmpty) {
      throw const FormatException(
        'Choisissez une phrase secrète d’au moins 12 caractères.',
      );
    }
    final plain = utf8.encode(contents);
    if (plain.length > maxPlainBytes) {
      throw const FormatException(
        'La sauvegarde dépasse la limite de 23 Mo de données. Contactez le support.',
      );
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final cipher = AesGcm.with256bits();
    final key = await _key(password, salt);
    final box = await cipher.encrypt(plain, secretKey: key, aad: _aad);
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': _format,
          'version': 2,
          'cipher': 'aes-256-gcm',
          'kdf': 'pbkdf2-sha256',
          'iterations': iterations,
          'salt': base64Encode(salt),
          'nonce': base64Encode(box.nonce),
          'mac': base64Encode(box.mac.bytes),
          'ciphertext': base64Encode(box.cipherText),
        }),
      ),
    );
  }

  static Future<String> decrypt(Uint8List bytes, String password) async {
    final envelope = readEnvelope(bytes);
    if (envelope['format'] != _format ||
        envelope['version'] != 2 ||
        envelope['cipher'] != 'aes-256-gcm' ||
        envelope['kdf'] != 'pbkdf2-sha256' ||
        envelope['iterations'] != iterations) {
      throw const FormatException(
        'Format de sauvegarde chiffrée non pris en charge.',
      );
    }
    try {
      final salt = base64Decode(envelope['salt'] as String);
      final nonce = base64Decode(envelope['nonce'] as String);
      final mac = base64Decode(envelope['mac'] as String);
      final cipherText = base64Decode(envelope['ciphertext'] as String);
      if (salt.length != 16 ||
          nonce.length != 12 ||
          mac.length != 16 ||
          cipherText.length > maxPlainBytes) {
        throw const FormatException('Paramètres de sauvegarde invalides.');
      }
      final key = await _key(password, salt);
      final plain = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
        aad: _aad,
      );
      return utf8.decode(plain);
    } catch (_) {
      throw const FormatException(
        'Phrase secrète incorrecte ou sauvegarde endommagée. Aucune donnée n’a été modifiée.',
      );
    }
  }

  static Future<SecretKey> _key(String password, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
}
