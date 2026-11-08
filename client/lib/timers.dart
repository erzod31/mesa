import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'store.dart';

class KitchenTimers extends ChangeNotifier {
  KitchenTimers(this.store);
  final Cookbook store;
  final notifications = FlutterLocalNotificationsPlugin();
  static const native = MethodChannel('mesa/native');
  List<Map<String, dynamic>> items = [];
  Timer? tick;
  bool ready = false;
  String warning = '';
  Future<void> init({bool enableNotifications = true}) async {
    tzdata.initializeTimeZones();
    try {
      if (!enableNotifications) throw StateError('Perfil de comprobación');
      await notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
          windows: WindowsInitializationSettings(
            appName: 'Mesa',
            appUserModelId: 'Mesa.Recetario.Familiar',
            guid: '165ab3ae-8d53-43dd-9a6c-a3a6c5ee7891',
          ),
        ),
      );
      ready = true;
    } catch (_) {
      warning = 'No se han podido activar las notificaciones. Los temporizadores siguen visibles en la app.';
    }
    final saved = store.prefs['timers'];
    if (saved != null && saved.isNotEmpty) {
      try {
        final decoded = jsonDecode(saved);
        if (decoded is! List) throw const FormatException();
        final ids = <int>{};
        items = [];
        for (final item in decoded) {
          if (item is! Map ||
              item['id'] is! int ||
              item['id'] < 0 ||
              item['id'] > 2147483647 ||
              item['name'] is! String ||
              item['end'] is! int ||
              item['paused'] is! bool ||
              item['remaining'] is! int ||
              item['remaining'] < 0 ||
              !ids.add(item['id'])) {
            warning = 'Hay temporizadores dañados que no se pudieron recuperar. El recetario sigue disponible.';
            continue;
          }
          items.add(Map<String, dynamic>.from(item));
        }
      } catch (_) {
        items = [];
        warning = 'No se pudieron recuperar los temporizadores guardados. Puedes crear uno nuevo.';
      }
    }
    tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (Platform.isWindows && ready) {
        for (final item in items) {
          if (item['paused'] != true &&
              remaining(item) <= 0 &&
              item['announced'] != true) {
            item['announced'] = true;
            unawaited(
              notifications
                  .show(
                    id: item['id'],
                    title: 'Tiempo terminado · ${item['name']}',
                    body: 'Vuelve a tu receta en Mesa.',
                    notificationDetails: const NotificationDetails(
                      windows: WindowsNotificationDetails(),
                    ),
                  )
                  .catchError((Object _) {}),
            );
            unawaited(persist());
          }
        }
      }
      notifyListeners();
    });
  }

  int remaining(Map<String, dynamic> item) => item['paused'] == true
      ? item['remaining'] as int
      : ((item['end'] as int) - DateTime.now().millisecondsSinceEpoch) ~/ 1000;
  Future<void> persist() => store.preference('timers', jsonEncode(items));
  Future<void> schedule(Map<String, dynamic> item) async {
    if (!ready) return;
    item['announced'] = false;
    if (Platform.isWindows) {
      warning = 'En Windows, mantén Mesa abierta para recibir el aviso del temporizador.';
      notifyListeners();
      return;
    }
    try {
      var mode = AndroidScheduleMode.exactAllowWhileIdle;
      if (Platform.isAndroid) {
        final android = notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final permission = await android?.requestNotificationsPermission();
        if (permission == false) {
          warning = 'Activa las notificaciones para recibir avisos con la pantalla bloqueada.';
          return;
        }
        final allowed = await android?.canScheduleExactNotifications();
        if (allowed != true) {
          final accepted = await android?.requestExactAlarmsPermission();
          if (accepted != true) {
            mode = AndroidScheduleMode.inexactAllowWhileIdle;
            warning = 'Sin permiso de alarmas exactas, el aviso puede retrasarse. Mantén la app visible para este temporizador.';
          }
        }
      }
      await notifications.zonedSchedule(
        id: item['id'],
        title: 'Tiempo terminado · ${item['name']}',
        body: 'Vuelve a tu receta en Mesa.',
        scheduledDate: tz.TZDateTime.from(
          DateTime.fromMillisecondsSinceEpoch(item['end']).toUtc(),
          tz.UTC,
        ),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'mesa_timers',
            'Temporizadores de cocina',
            channelDescription: 'Avisos locales de cocina',
            importance: Importance.max,
            priority: Priority.high,
            icon: 'ic_notification',
          ),
          windows: WindowsNotificationDetails(),
        ),
        androidScheduleMode: mode,
      );
    } catch (_) {
      warning = 'El sistema no ha permitido programar el aviso. Mantén la app abierta y revisa los permisos.';
    }
    notifyListeners();
  }

  Future<void> add(String name, int seconds) async {
    if (seconds <= 0 || seconds > 86400) {
      throw Exception('Introduce una duración de hasta 24 horas.');
    }
    var id = DateTime.now().millisecondsSinceEpoch % 2147483647;
    while (items.any((item) => item['id'] == id)) {
      id = (id + 1) % 2147483647;
    }
    final item = <String, dynamic>{
      'id': id,
      'name': name,
      'end': DateTime.now()
          .add(Duration(seconds: seconds))
          .millisecondsSinceEpoch,
      'paused': false,
      'remaining': seconds,
    };
    items.add(item);
    await persist();
    await schedule(item);
    notifyListeners();
  }

  Future<void> toggle(Map<String, dynamic> item) async {
    if (item['paused'] == true) {
      item['end'] = DateTime.now()
          .add(Duration(seconds: item['remaining']))
          .millisecondsSinceEpoch;
      item['paused'] = false;
      await schedule(item);
    } else {
      item['remaining'] = remaining(item).clamp(0, 86400);
      item['paused'] = true;
      try {
        await notifications.cancel(id: item['id']);
      } catch (_) {}
    }
    await persist();
    notifyListeners();
  }

  Future<void> remove(Map<String, dynamic> item) async {
    try {
      await notifications.cancel(id: item['id']);
    } catch (_) {}
    items.remove(item);
    await persist();
    notifyListeners();
  }

  Future<void> minute(Map<String, dynamic> item) async {
    if (item['paused'] == true) {
      item['remaining'] += 60;
    } else {
      item['end'] = DateTime.now()
          .add(Duration(seconds: remaining(item).clamp(0, 86400) + 60))
          .millisecondsSinceEpoch;
      await schedule(item);
    }
    await persist();
    notifyListeners();
  }

  static Future<void> awake(bool enabled) async {
    try {
      await native.invokeMethod('awake', enabled);
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }

  @override
  void dispose() {
    tick?.cancel();
    super.dispose();
  }
}
