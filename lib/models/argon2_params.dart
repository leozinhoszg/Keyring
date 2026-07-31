class Argon2Params {
  final int memoryCost; // KiB
  final int timeCost;
  final int parallelism;
  const Argon2Params({this.memoryCost = 19456, this.timeCost = 2, this.parallelism = 1});

  /// Tetos de sanidade. Os valores vêm do cofre (e, no import, de um arquivo
  /// escolhido pelo usuário): sem limite, um `memoryCost` absurdo faz a
  /// derivação tentar alocar gigabytes e derruba o app antes de qualquer aviso.
  /// O piso acompanha a recomendação do OWASP para Argon2id.
  static const int minMemoryCost = 8 * 1024; // 8 MiB
  static const int maxMemoryCost = 1024 * 1024; // 1 GiB
  static const int maxTimeCost = 32;
  static const int maxParallelism = 16;

  Map<String, dynamic> toJson() =>
      {'memoryCost': memoryCost, 'timeCost': timeCost, 'parallelism': parallelism};

  factory Argon2Params.fromJson(Map<String, dynamic> j) {
    int read(String key, int min, int max) {
      final v = j[key];
      if (v is! int || v < min || v > max) {
        throw FormatException('Parâmetro Argon2 "$key" inválido: $v (esperado entre $min e $max)');
      }
      return v;
    }

    return Argon2Params(
      memoryCost: read('memoryCost', minMemoryCost, maxMemoryCost),
      timeCost: read('timeCost', 1, maxTimeCost),
      parallelism: read('parallelism', 1, maxParallelism),
    );
  }
}
