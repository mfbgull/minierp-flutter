import 'dart:convert';

abstract final class PasswordPolicy {
  static const minimumCharacters = 12;
  static const maximumBytes = 72;

  static bool isTooShort(String value) =>
      value.runes.length < minimumCharacters;

  static bool isTooLong(String value) =>
      utf8.encode(value).length > maximumBytes;
}
