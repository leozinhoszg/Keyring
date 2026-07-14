class VaultSettings {
  final int autoLockMinutes;
  final int clipboardClearSeconds;
  const VaultSettings({this.autoLockMinutes = 5, this.clipboardClearSeconds = 20});

  Map<String, dynamic> toJson() =>
      {'autoLockMinutes': autoLockMinutes, 'clipboardClearSeconds': clipboardClearSeconds};
  factory VaultSettings.fromJson(Map<String, dynamic> j) => VaultSettings(
        autoLockMinutes: j['autoLockMinutes'] as int? ?? 5,
        clipboardClearSeconds: j['clipboardClearSeconds'] as int? ?? 20,
      );
}
