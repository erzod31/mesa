import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'windows_updates.dart';
import 'update_signature.dart';

const updateFeed = String.fromEnvironment(
  'MESA_UPDATE_FEED',
  defaultValue: 'https://starfly.tailc69897.ts.net:9443/descargar/update.json',
);

class AndroidRelease {
  AndroidRelease(
    this.version,
    this.code,
    this.size,
    this.sha256,
    this.url,
    this.minSdk,
    this.abis,
    this.notes,
  );
  final String version, sha256;
  final int code, size, minSdk;
  final Uri url;
  final List<String> abis, notes;
  factory AndroidRelease.parse(Map<String, dynamic> data, Uri origin) {
    final path = '${data['apk_path'] ?? ''}';
    final version = data['version'],
        code = data['version_code'],
        size = data['size'];
    final minSdk = data['min_sdk'], sha = '${data['sha256'] ?? ''}';
    final abis = data['abis'], notes = data['notes'];
    if (data['package'] != 'com.mesa.mesa' ||
        version is! String ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
        code is! int ||
        code < 1 ||
        code > 2147483647 ||
        size is! int ||
        size < 1 ||
        size > 120000000 ||
        minSdk is! int ||
        minSdk < 24 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha) ||
        path != '/descargar/Mesa-Android-$version-$code.apk' ||
        abis is! List ||
        abis.isEmpty ||
        !abis.every((v) => v is String) ||
        notes is! List ||
        notes.length > 20 ||
        !notes.every((v) => v is String && v.length <= 1000)) {
      throw Exception('Los datos de la actualización no son válidos.');
    }
    return AndroidRelease(
      version,
      code,
      size,
      sha,
      origin.resolve(path),
      minSdk,
      abis.cast<String>(),
      notes.cast<String>(),
    );
  }
  Map<String, dynamic> get nativeArguments => {
    'version': version,
    'version_code': code,
    'size': size,
    'sha256': sha256,
    'url': url.toString(),
    'feed_origin': url.origin,
  };
}

class UpdateApi {
  UpdateApi(this.client, {Uri? feed, this.publicKey = updatePublicKey})
    : feed = feed ?? Uri.parse(updateFeed);
  final http.Client client;
  final String publicKey;
  final Uri feed;
  bool sameOrigin(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.host == feed.host &&
      uri.port == feed.port;
  Future<AndroidRelease> check() async {
    if (feed.scheme != 'https' ||
        feed.host.isEmpty ||
        feed.userInfo.isNotEmpty) {
      throw Exception('El origen de las actualizaciones debe usar HTTPS.');
    }
    var uri = feed;
    for (var redirect = 0; redirect <= 3; redirect++) {
      if (!sameOrigin(uri)) {
        throw Exception('La actualización redirige a un origen no permitido.');
      }
      final request = http.Request('GET', uri)..followRedirects = false;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 12));
      final bytes = <int>[];
      await for (final part in response.stream.timeout(
        const Duration(seconds: 8),
      )) {
        if (bytes.length + part.length > 16000) {
          throw Exception('La respuesta de actualización es demasiado grande.');
        }
        bytes.addAll(part);
      }
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        if (location == null) {
          throw Exception('Redirección sin destino.');
        }
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != 200) {
        throw Exception(
          'El ordenador no ofrece la actualización (HTTP ${response.statusCode}).',
        );
      }
      final data = Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)));
      await verifyAndroidUpdate(data, publicKey: publicKey);
      return AndroidRelease.parse(data, feed);
    }
    throw Exception('Demasiadas redirecciones de actualización.');
  }
}

class WindowsRelease extends AndroidRelease {
  WindowsRelease(
    super.version,
    super.code,
    super.size,
    super.sha256,
    super.url,
    super.minSdk,
    super.abis,
    super.notes,
  );
  factory WindowsRelease.parse(Map<String, dynamic> data) {
    if (data['product'] != 'com.mesa.mesa.windows' ||
        data['platform'] != 'windows' ||
        data['architecture'] != 'x64' ||
        data['version'] is! String ||
        data['version_code'] is! int ||
        data['size'] is! int ||
        data['notes'] is! List ||
        data['sha256'] is! String ||
        data['url'] is! String) {
      throw Exception('La actualización no corresponde a Mesa Windows.');
    }
    return WindowsRelease(
      data['version'],
      data['version_code'],
      data['size'],
      data['sha256'],
      Uri.parse(data['url']),
      0,
      ['x64'],
      List<String>.from(data['notes']),
    );
  }
}

class AppUpdatePage extends StatefulWidget {
  const AppUpdatePage({
    super.key,
    required this.client,
    this.api,
    this.channel = const MethodChannel('mesa/updates'),
    this.platform,
    this.desktopBridge,
    this.beforeClose,
  });
  final http.Client client;
  final UpdateApi? api;
  final MethodChannel channel;
  final TargetPlatform? platform;
  final DesktopUpdateBridge? desktopBridge;
  final Future<void> Function()? beforeClose;
  @override
  State<AppUpdatePage> createState() => _AppUpdatePageState();
}

class _AppUpdatePageState extends State<AppUpdatePage>
    with WidgetsBindingObserver {
  Map<String, dynamic>? installed;
  AndroidRelease? release;
  String status = 'Buscando actualizaciones…';
  bool checking = true, downloading = false, ready = false, installing = false;
  bool waitingPermission = false, cancelled = false;
  int received = 0;
  bool get windows =>
      (widget.platform ?? defaultTargetPlatform) == TargetPlatform.windows;
  DesktopUpdateBridge? get desktop =>
      widget.desktopBridge ?? windowsUpdateBridge;
  Future<dynamic> invoke(String method, [Map<String, dynamic>? arguments]) {
    if (windows) {
      if (desktop == null) {
        throw PlatformException(
          code: 'launcher',
          message: 'Abre Mesa desde el acceso de la instalación Windows para actualizarla. Una copia antigua o portable requiere una primera instalación manual.',
        );
      }
      return desktop!.invoke(method, arguments);
    }
    return widget.channel.invokeMethod<dynamic>(method, arguments);
  }

  bool get newer =>
      release != null &&
      installed != null &&
      release!.code > (installed!['version_code'] as num).toInt();
  bool get compatible =>
      release != null &&
      installed != null &&
      release!.minSdk <= (installed!['sdk'] as num).toInt() &&
      (installed!['abis'] as List).any(release!.abis.contains);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (windows) {
      desktop?.progress((value, total) {
        if (mounted && downloading) setState(() => received = value);
      });
    } else {
      widget.channel.setMethodCallHandler((call) async {
        if (call.method == 'progress' && mounted && downloading) {
          setState(
            () =>
                received = ((call.arguments as Map)['received'] as num).toInt(),
          );
        }
      });
    }
    check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (downloading) {
      invoke('cancel').catchError((_) {});
    }
    if (windows) {
      desktop?.progress(null);
    } else {
      widget.channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && waitingPermission) {
      waitingPermission = false;
      resumePermission();
    }
  }

  Future<void> resumePermission() async {
    try {
      final current = await info();
      if (!mounted) {
        return;
      }
      if (current['can_install'] == true) {
        await install();
      } else {
        setState(
          () => status = 'No se concedió el permiso. Puedes pulsar Instalar actualización para volver a intentarlo.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => status = 'No se pudo comprobar el permiso. Vuelve a intentar la instalación.',
        );
      }
    }
  }

  Future<Map<String, dynamic>> info() async =>
      Map<String, dynamic>.from(await invoke('info') as Map);

  Future<void> check() async {
    setState(() {
      checking = true;
      ready = false;
      release = null;
      status = 'Buscando actualizaciones…';
    });
    try {
      final current = await info();
      if (mounted) setState(() => installed = current);
      final latest = windows
          ? WindowsRelease.parse(
              Map<String, dynamic>.from(await invoke('check') as Map),
            )
          : await (widget.api ?? UpdateApi(widget.client)).check();
      if (!mounted) {
        return;
      }
      setState(() {
        installed = current;
        release = latest;
        status = windows && current['can_install'] != true
            ? 'Esta copia requiere una primera instalación manual. Abre Mesa desde su acceso instalado para las siguientes actualizaciones.'
            : newer
            ? compatible
                  ? 'Hay una nueva versión de Mesa.'
                  : 'Esta versión no es compatible con tu teléfono.'
            : 'Ya tienes la versión más reciente disponible.';
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => status = windows
              ? (error is PlatformException
                    ? error.message ?? 'No se pudo comprobar el canal Windows.'
                    : 'No se pudo comprobar el canal Windows. Revisa Tailscale y vuelve a intentarlo.')
              : 'No se pudo comprobar la actualización. Activa Tailscale, comprueba Internet y que el ordenador esté encendido.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => checking = false);
      }
    }
  }

  Future<void> download() async {
    if (!newer || !compatible || downloading) {
      return;
    }
    setState(() {
      downloading = true;
      ready = false;
      cancelled = false;
      received = 0;
      status = 'Descargando actualización…';
    });
    try {
      await invoke('download', release!.nativeArguments);
      if (cancelled) {
        throw PlatformException(
          code: 'cancelled',
          message: 'Descarga cancelada.',
        );
      }
      if (mounted) {
        setState(() {
          ready = true;
          status = 'Descarga comprobada. Ya puedes instalarla.';
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => status = error.code == 'cancelled'
              ? 'Descarga cancelada. Puedes volver a intentarlo.'
              : error.message ??
                    'No se pudo descargar. Reintenta con Tailscale activo.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              status = 'No se pudo descargar. Reintenta con Tailscale activo.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => downloading = false);
      }
    }
  }

  Future<void> install() async {
    if (!ready || installing) {
      return;
    }
    if (windows) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Actualizar y reabrir Mesa'),
          content: const Text(
            'Mesa se cerrará para abrir el instalador de Windows. Confirma sus pasos; después se reabrirá la app. Tus recetas y configuración se conservan. No desinstales Mesa.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => installing = true);
    try {
      final current = await info();
      if (windows && current['can_install'] != true) {
        throw PlatformException(
          code: 'manual',
          message: 'Esta copia requiere una primera instalación manual de Mesa Windows.',
        );
      }
      if (current['can_install'] != true) {
        if (mounted) {
          setState(
            () => status =
                'Permite a Mesa instalar actualizaciones y vuelve a la app.',
          );
        }
        waitingPermission = true;
        await invoke('permission');
        return;
      }
      await widget.beforeClose?.call();
      final handoff = await invoke('install', release!.nativeArguments);
      if (windows) {
        if (handoff is! Map || handoff['close_app'] != true) {
          throw PlatformException(
            code: 'handoff',
            message: 'Windows no confirmó la preparación de la actualización. Mesa sigue abierta.',
          );
        }
        await desktop!.closeForUpdate();
        return;
      }
      if (mounted) {
        setState(
          () => status = 'Confirma la actualización en el instalador de Android. Si la cancelas, puedes instalarla de nuevo desde aquí.',
        );
      }
    } on PlatformException catch (error) {
      waitingPermission = false;
      if (mounted) {
        setState(
          () =>
              status = error.message ?? 'Android no pudo abrir el instalador.',
        );
      }
    } catch (_) {
      waitingPermission = false;
      if (mounted) {
        setState(
          () => status =
              'No se pudo iniciar la instalación. Vuelve a intentarlo.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => installing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Actualizar Mesa')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.system_update_alt, size: 54),
        const SizedBox(height: 16),
        if (installed != null)
          Text(
            'Versión instalada: ${installed!['version']}',
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 16),
        Text(status, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        if (checking) const LinearProgressIndicator(),
        if (newer) ...[
          Text(
            'Mesa ${release!.version} · ${(release!.size / 1000000).toStringAsFixed(1)} MB',
          ),
          const SizedBox(height: 10),
          for (final note in release!.notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('• $note'),
            ),
        ],
        if (downloading) ...[
          LinearProgressIndicator(
            value: (received / release!.size).clamp(0, 1),
          ),
          const SizedBox(height: 8),
          Text(
            '${(received / 1000000).toStringAsFixed(1)} / ${(release!.size / 1000000).toStringAsFixed(1)} MB',
          ),
          TextButton(
            onPressed: cancelled
                ? null
                : () async {
                    setState(() {
                      cancelled = true;
                      status = 'Cancelando descarga…';
                    });
                    await invoke('cancel');
                  },
            child: const Text('Cancelar descarga'),
          ),
        ],
        if (!checking && !downloading) ...[
          if (newer && compatible && !ready)
            FilledButton.icon(
              onPressed: download,
              icon: const Icon(Icons.download),
              label: const Text('Descargar actualización'),
            ),
          if (ready)
            FilledButton.icon(
              onPressed: installing ? null : install,
              icon: const Icon(Icons.system_update),
              label: Text(
                installing ? 'Comprobando…' : 'Instalar actualización',
              ),
            ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: installing ? null : check,
            child: const Text('Buscar actualizaciones'),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          windows
              ? 'El canal Windows debe estar disponible por HTTPS. Mesa comprueba la firma del canal, el producto, la versión, el tamaño y SHA-256 antes de abrir el instalador. Requiere confirmar y cerrar la app; el asistente la reabre. No desinstales Mesa.'
              : 'Requiere Tailscale y el ordenador encendido. Android pedirá confirmar la instalación y permite abrir Mesa al terminar. Tus recetas y tu conexión familiar se conservan. No desinstales Mesa.',
        ),
      ],
    ),
  );
}
