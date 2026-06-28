import 'package:flutter/material.dart';

class PrivacyThemeExtension extends ThemeExtension<PrivacyThemeExtension> {
  final Color publicEventColor;
  final Color privateEventColor;
  final Color secretEventColor;

  const PrivacyThemeExtension({
    required this.publicEventColor,
    required this.privateEventColor,
    required this.secretEventColor,
  });

  @override
  ThemeExtension<PrivacyThemeExtension> copyWith({
    Color? publicEventColor,
    Color? privateEventColor,
    Color? secretEventColor,
  }) {
    return PrivacyThemeExtension(
      publicEventColor: publicEventColor ?? this.publicEventColor,
      privateEventColor: privateEventColor ?? this.privateEventColor,
      secretEventColor: secretEventColor ?? this.secretEventColor,
    );
  }

  @override
  ThemeExtension<PrivacyThemeExtension> lerp(
    covariant ThemeExtension<PrivacyThemeExtension>? other,
    double t,
  ) {
    if (other is! PrivacyThemeExtension) {
      return this;
    }
    return PrivacyThemeExtension(
      publicEventColor: Color.lerp(publicEventColor, other.publicEventColor, t)!,
      privateEventColor: Color.lerp(privateEventColor, other.privateEventColor, t)!,
      secretEventColor: Color.lerp(secretEventColor, other.secretEventColor, t)!,
    );
  }
}
