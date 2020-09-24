import 'package:flutter/material.dart';

class FaradayNotification extends Notification {
  final String name;
  final dynamic arguments;

  FaradayNotification(this.name, this.arguments)
      : assert(name != null && name.isNotEmpty),
        super();
}
