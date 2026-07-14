int evaluateStrength(String pw) {
  if (pw.isEmpty) return 0;
  var score = 0;
  if (pw.length >= 8) score++;
  if (pw.length >= 14) score++;
  var classes = 0;
  if (RegExp(r'[a-z]').hasMatch(pw)) classes++;
  if (RegExp(r'[A-Z]').hasMatch(pw)) classes++;
  if (RegExp(r'[0-9]').hasMatch(pw)) classes++;
  if (RegExp(r'[^a-zA-Z0-9]').hasMatch(pw)) classes++;
  if (classes >= 3) score++;
  if (classes >= 4 && pw.length >= 12) score++;
  return score.clamp(0, 4);
}

const _labels = ['Muito fraca', 'Fraca', 'Razoavel', 'Forte', 'Muito forte'];
String strengthLabel(int score) => _labels[score.clamp(0, 4)];
