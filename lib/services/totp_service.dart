import 'package:otp/otp.dart';

class TotpService {
  static const int _interval = 30;
  static const int _digits = 6;

  String generateSecret() => OTP.randomSecret();

  String _codeAt(String secret, int millis) => OTP.generateTOTPCodeString(
        secret,
        millis,
        interval: _interval,
        length: _digits,
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );

  String currentCode(String secret) =>
      _codeAt(secret, DateTime.now().millisecondsSinceEpoch);

  bool verify(String token, String secret) {
    final now = DateTime.now().millisecondsSinceEpoch;
    const step = _interval * 1000;
    for (final offset in [0, -step, step]) {
      if (_codeAt(secret, now + offset) == token) return true;
    }
    return false;
  }

  String keyUri(String secret, {required String label, required String issuer}) {
    final l = Uri.encodeComponent('$issuer:$label');
    return 'otpauth://totp/$l?secret=$secret&issuer=${Uri.encodeComponent(issuer)}&period=$_interval&digits=$_digits';
  }
}
