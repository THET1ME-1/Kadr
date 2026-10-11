import 'package:flutter/material.dart';

/// Плашка с отменой действия: «Удалено · Отменить».
///
/// Гаснет сама через шесть секунд. С Flutter 3.38 плашка с кнопкой по
/// умолчанию висит, пока её не смахнут. А отмена возвращает данные такими,
/// какими они были до действия: нажатая через полчаса, она стёрла бы всё,
/// что человек успел сделать после.
SnackBar undoSnackBar({
  required String text,
  required String label,
  required VoidCallback onUndo,
  Color? backgroundColor,
}) =>
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: backgroundColor,
      persist: false,
      duration: const Duration(seconds: 6),
      content: Text(text),
      action: SnackBarAction(label: label, onPressed: onUndo),
    );
