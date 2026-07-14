class Argon2Params {
  final int memoryCost; // KiB
  final int timeCost;
  final int parallelism;
  const Argon2Params({this.memoryCost = 19456, this.timeCost = 2, this.parallelism = 1});

  Map<String, dynamic> toJson() =>
      {'memoryCost': memoryCost, 'timeCost': timeCost, 'parallelism': parallelism};
  factory Argon2Params.fromJson(Map<String, dynamic> j) => Argon2Params(
        memoryCost: j['memoryCost'] as int,
        timeCost: j['timeCost'] as int,
        parallelism: j['parallelism'] as int,
      );
}
