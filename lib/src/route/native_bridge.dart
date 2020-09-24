import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:g_faraday/src/channel.dart';
import 'package:g_faraday/src/utils/notification.dart';

import 'arg.dart';
import 'navigator.dart';

const EventChannel _notification = EventChannel('g_faraday/notification');

class FaradayNativeBridge extends StatefulWidget {
  final RouteFactory onGenerateRoute;
  final RouteFactory onUnknownRoute;

  final RouteFactory mockNativeRouteFactory;
  final RouteSettings mockInitialSettings;

  FaradayNativeBridge({
    Key key,
    @required this.onGenerateRoute,
    this.onUnknownRoute,
    this.mockNativeRouteFactory,
    this.mockInitialSettings,
  }) : super(key: key);

  static FaradayNativeBridgeState of(BuildContext context) {
    FaradayNativeBridgeState faraday;
    if (context is StatefulElement &&
        context.state is FaradayNativeBridgeState) {
      faraday = context.state as FaradayNativeBridgeState;
    }
    return faraday ??
        context.findAncestorStateOfType<FaradayNativeBridgeState>();
  }

  @override
  FaradayNativeBridgeState createState() => FaradayNativeBridgeState();
}

class FaradayNativeBridgeState extends State<FaradayNativeBridge> {
  List<FaradayNavigator> _navigatorStack = [];
  int _index;
  int _preIndex = 0;
  int _seq = 0;

  RouteSettings get _mockInitialSettings => widget.mockInitialSettings;
  RouteFactory get _mockNativeRouteFactory => widget.mockNativeRouteFactory;

  StreamSubscription _subscriptionNotification;

  @override
  void initState() {
    super.initState();
    channel.setMethodCallHandler(_handler);

    _subscriptionNotification =
        _notification.receiveBroadcastStream().listen((data) {
      if (data is Map) {
        final name = data['name'];
        if (name is String && context != null) {
          FaradayNotification(name, data['arguments']).dispatch(context);
        }
      }
    });
    //
    if (kDebugMode) {
      if (widget.mockInitialSettings != null) {
        _handler(MethodCall('pageCreate', {
          'name': _mockInitialSettings.name,
          'arg': _mockInitialSettings.arguments
        }));
      }
    }
  }

  void dispose() {
    _subscriptionNotification.cancel();
    super.dispose();
  }

  Future<T> push<T extends Object>(
    String name, {
    Map<String, dynamic> arguments,
    bool present = false,
    bool flutterRoute = false,
  }) async {
    if (kDebugMode) {
      if (_mockNativeRouteFactory != null) {
        if (flutterRoute) {
          final key = _navigatorStack.last.key as LabeledGlobalKey;
          if (key.currentState is FaradayNavigatorState) {
            return (key.currentState as FaradayNavigatorState)
                .pushNamed(name, arguments: arguments);
          }
        }
        return Navigator.of(context, rootNavigator: true)
            .push(_mockNativeRouteFactory(RouteSettings(
          name: name,
          arguments: {
            'present': present,
            'flutterRoute': flutterRoute,
            if (arguments != null) ...arguments
          },
        )));
      }
    }
    //
    return channel.invokeMethod(
      'pushNativePage',
      {
        'name': name,
        'present': present,
        'flutterRoute': flutterRoute,
        if (arguments != null) 'arguments': arguments
      },
    );
  }

  Future<void> pop<T extends Object>(Key key, [T result]) async {
    if (kDebugMode) {
      if (_mockNativeRouteFactory != null) {
        return Navigator.of(context, rootNavigator: true).maybePop(result);
      }
    }
    assert(_navigatorStack.isNotEmpty);
    assert(_navigatorStack[_index].arg.key == key);
    await channel.invokeMethod('popContainer', result);
  }

  Future<void> disableHorizontalSwipePopGesture(bool disable) async {
    if (kDebugMode) {
      if (_mockNativeRouteFactory != null) {
        return;
      }
    }
    await channel.invokeMethod('disableHorizontalSwipePopGesture', disable);
  }

  bool isOnTop(Key key) {
    return _navigatorStack.isNotEmpty && _navigatorStack[_index].arg.key == key;
  }

  @override
  Widget build(BuildContext context) {
    if (_index == -1 || _navigatorStack.isEmpty)
      return Container(
        alignment: Alignment.center,
        child: Text(
          'hot restart losts all states, please trigger re-create.',
          textAlign: TextAlign.center,
        ),
      );

    return IndexedStack(
      children: _navigatorStack,
      index: _index,
    );
  }

  Future<dynamic> _handler(MethodCall call) {
    int index() {
      int seq = call.arguments as int;
      final index = _navigatorStack.indexWhere((n) => n.arg.seq == seq);
      return index;
    }

    switch (call.method) {
      case 'pageCreate':
        String name = call.arguments['name'];
        final arg = FaradayArguments(call.arguments['arguments'], name, _seq++);
        _navigatorStack.add(appRoot(arg));
        _updateIndex(_navigatorStack.length - 1);
        return Future.value(arg.seq);
      case 'pageShow':
        _updateIndex(index());
        return Future.value(true);
      case 'pageHidden':
        if (index() == _index) _updateIndex(_preIndex);
        return Future.value(true);
      case 'pageDealloc':
        final current = _navigatorStack[_index];
        _navigatorStack.removeAt(index());
        _updateIndex(_navigatorStack.indexOf(current));
        return Future.value(true);
      default:
        return Future.value(false);
    }
  }

  void _updateIndex(int index) {
    setState(() {
      _preIndex = _index;
      _index = index;
      debugPrint('index: $_index, preIndex: $_preIndex, max_seq: $_seq');
    });
  }

  FaradayNavigator appRoot(FaradayArguments arg) {
    final initialSettings =
        RouteSettings(name: arg.name, arguments: arg.arguments);
    return FaradayNavigator(
      key: GlobalKey(debugLabel: 'seq: ${arg.seq}'),
      arg: arg,
      initialRoute: arg.name,
      onGenerateRoute: (settings) {
        if (kDebugMode) {
          if (settings.name == "/")
            return widget.onGenerateRoute(initialSettings);
        }
        return widget.onGenerateRoute(settings);
      },
      onUnknownRoute: widget.onUnknownRoute,
      onGenerateInitialRoutes: (navigator, initialRoute) => [
        widget.onGenerateRoute(initialSettings) ??
            widget.onUnknownRoute(initialSettings),
      ],
    );
  }
}
