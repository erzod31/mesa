import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:http/http.dart' as http;

import 'photo_data.dart';
import 'licensed_photos.dart';

export 'photo_data.dart';

/// Sharing is restricted to currently visible consumers of one gallery. No disk
/// cache, global ImageCache, credentials or background image prefetch is used.
class GalleryPhotoSession {
  GalleryPhotoSession({this.clientFactory});
  final http.Client Function()? clientFactory;
  final _active = <String, _GalleryPhotoRequest>{};
  final _queue = <_GalleryPhotoRequest>[];
  int _running = 0;
  bool _closed = false;
  GalleryPhotoLease acquire(String url, {bool priority = true}) {
    if (_closed) throw StateError('Galería cerrada.');
    if (_active[url]?.failed == true) _active.remove(url);
    final request = _active.putIfAbsent(url, () {
      final value = _GalleryPhotoRequest(url, priority);
      _queue.add(value);
      return value;
    });
    request.users++;
    if (priority) request.priority = true;
    _drain();
    return GalleryPhotoLease(request.done.future, () => _release(request));
  }

  void _release(_GalleryPhotoRequest request) {
    if (--request.users > 0) return;
    if (identical(_active[request.url], request)) _active.remove(request.url);
    _queue.remove(request);
    request.connection?.close();
    if (!request.done.isCompleted) {
      request.done.completeError(StateError('La foto ya no está visible.'));
    }
  }

  void _drain() {
    _queue.sort((a, b) => (b.priority ? 1 : 0).compareTo(a.priority ? 1 : 0));
    while (!_closed && _running < 3 && _queue.isNotEmpty) {
      final request = _queue.removeAt(0);
      _running++;
      unawaited(() async {
        final connection = clientFactory?.call() ?? directPhotoClient();
        request.connection = connection;
        try {
          final bytes = await fetchOnlinePhoto(connection, request.url).timeout(
            Duration(
              seconds: documentPhotoReference(request.url) != null ? 60 : 30,
            ),
          );
          if (!request.done.isCompleted) request.done.complete(bytes);
        } catch (error, stack) {
          request.failed = true;
          if (!request.done.isCompleted) {
            request.done.completeError(error, stack);
          }
        } finally {
          connection.close();
          request.connection = null;
          _running--;
          _drain();
        }
      }());
    }
  }

  void dispose() {
    _closed = true;
    for (final request in _active.values) {
      request.connection?.close();
      if (!request.done.isCompleted) {
        request.done.completeError(StateError('Galería cerrada.'));
      }
    }
    _queue.clear();
    _active.clear();
  }
}

class GalleryPhotoLease {
  GalleryPhotoLease(this.bytes, this._release);
  final Future<Uint8List> bytes;
  final VoidCallback _release;
  bool _released = false;
  void release() {
    if (!_released) {
      _released = true;
      _release();
    }
  }
}

class _GalleryPhotoRequest {
  _GalleryPhotoRequest(this.url, this.priority);
  final String url;
  bool priority;
  bool failed = false;
  int users = 0;
  http.Client? connection;
  final done = Completer<Uint8List>();
}

class RecipePhoto extends StatefulWidget {
  const RecipePhoto(
    this.photo, {
    super.key,
    this.fit = BoxFit.cover,
    this.clientFactory,
    this.session,
    this.maxDimension = 1600,
    this.priority = true,
  });
  final Map<String, dynamic> photo;
  final BoxFit fit;
  final http.Client Function()? clientFactory;
  final GalleryPhotoSession? session;
  final int maxDimension;
  final bool priority;
  @override
  State<RecipePhoto> createState() => _RecipePhotoState();
}

class _RecipePhotoState extends State<RecipePhoto> with WidgetsBindingObserver {
  ui.Image? image;
  http.Client? client;
  int requestId = 0;
  bool failed = false, paused = false;
  bool? displayActive;
  GalleryPhotoLease? lease;
  String get url => widget.photo['url'] as String? ?? '';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    if (displayActive == active) return;
    displayActive = active;
    if (active) {
      unawaited(load());
    } else {
      release();
    }
  }

  void release() {
    requestId++;
    client?.close();
    client = null;
    image?.dispose();
    image = null;
    lease?.release();
    lease = null;
  }

  @override
  void didUpdateWidget(RecipePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo['url'] != url) {
      release();
      unawaited(load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      paused = true;
      release();
      if (mounted) setState(() {});
    } else if (paused) {
      paused = false;
      unawaited(load());
    }
  }

  Future<void> load() async {
    if (paused || displayActive != true) return;
    if (!onlinePhotoUrl(url)) {
      if (mounted) setState(() => failed = true);
      return;
    }
    final current = ++requestId;
    lease?.release();
    lease = null;
    failed = false;
    final connection = widget.session == null
        ? (widget.clientFactory?.call() ?? directPhotoClient())
        : null;
    client = connection;
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? decoded;
    try {
      if (widget.session != null) {
        lease = widget.session!.acquire(url, priority: widget.priority);
      }
      final bytes = await (lease?.bytes ?? fetchOnlinePhoto(connection!, url))
          .timeout(
            Duration(seconds: documentPhotoReference(url) != null ? 60 : 30),
          );
      if (!mounted || current != requestId) return;
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width * descriptor.height > 40000000) {
        throw Exception('Imagen demasiado grande.');
      }
      final ratio =
          widget.maxDimension /
          (descriptor.width > descriptor.height
              ? descriptor.width
              : descriptor.height);
      codec = await descriptor.instantiateCodec(
        targetWidth: ratio < 1
            ? (descriptor.width * ratio).round().clamp(1, widget.maxDimension)
            : null,
        targetHeight: ratio < 1
            ? (descriptor.height * ratio).round().clamp(1, widget.maxDimension)
            : null,
      );
      decoded = (await codec.getNextFrame()).image;
      if (!mounted || current != requestId) return;
      setState(() {
        image?.dispose();
        image = decoded;
        decoded = null;
      });
    } catch (_) {
      if (mounted && current == requestId) setState(() => failed = true);
    } finally {
      decoded?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
      connection?.close();
      if (identical(client, connection)) client = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (image != null) {
      return Semantics(
        label: widget.photo['caption'] as String? ?? 'Foto de la receta',
        child: RawImage(
          image: image,
          fit:
              (Uri.tryParse(url)?.host.endsWith('creativegan.net') == true ||
                  widget.photo['license'] != null ||
                  documentPhotoReference(url) != null)
              ? BoxFit.contain
              : widget.fit,
        ),
      );
    }
    return Center(
      child: failed
          ? TextButton.icon(
              onPressed: paused
                  ? null
                  : () {
                      setState(() => failed = false);
                      unawaited(load());
                    },
              icon: const Icon(Icons.refresh),
              label: const Text('Ver foto en línea'),
            )
          : const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
    );
  }
}

class PhotoGallery extends StatefulWidget {
  const PhotoGallery({
    super.key,
    required this.photos,
    this.onRemove,
    this.onCover,
  });
  final List<Map<String, dynamic>> photos;
  final ValueChanged<int>? onRemove, onCover;
  @override
  State<PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<PhotoGallery> {
  int selected = 0;
  final pager = PageController();
  final session = GalleryPhotoSession();
  @override
  void dispose() {
    pager.dispose();
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) return const SizedBox.shrink();
    selected = selected.clamp(0, widget.photos.length - 1);
    final photo = widget.photos[selected];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 230,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: PageView.builder(
              controller: pager,
              itemCount: widget.photos.length,
              onPageChanged: (i) => setState(() => selected = i),
              itemBuilder: (context, i) => InkWell(
                onTap: () => showDialog(
                  context: context,
                  builder: (context) => Dialog.fullscreen(
                    child: Scaffold(
                      appBar: AppBar(
                        title: Text('Foto ${i + 1} de ${widget.photos.length}'),
                      ),
                      body: InteractiveViewer(
                        minScale: .5,
                        maxScale: 5,
                        child: Center(
                          child: RecipePhoto(
                            widget.photos[i],
                            fit: BoxFit.contain,
                            session: session,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                child: RecipePhoto(widget.photos[i], session: session),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (widget.photos.length > 1)
          Text(
            'Foto ${selected + 1} de ${widget.photos.length} · toca para ampliar',
          ),
        if (widget.photos.length > 1)
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollCacheExtent: const ScrollCacheExtent.pixels(0),
              scrollDirection: Axis.horizontal,
              itemCount: widget.photos.length,
              separatorBuilder: (_, i) => const SizedBox(width: 8),
              itemBuilder: (context, i) => Semantics(
                label: 'Ver foto ${i + 1}',
                button: true,
                child: InkWell(
                  onTap: () {
                    setState(() => selected = i);
                    pager.jumpToPage(i);
                  },
                  child: Container(
                    width: 85,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        width: i == selected ? 3 : 1,
                        color: i == selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: RecipePhoto(
                      widget.photos[i],
                      session: session,
                      maxDimension: 180,
                      priority: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if ((photo['caption'] as String? ?? '').isNotEmpty)
          Text(photo['caption']),
        if ((photo['artist'] as String? ?? '').isNotEmpty ||
            (photo['source'] as String? ?? '').isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Créditos de esta foto'),
            children: [
              SelectableText(
                [
                  photo['artist'],
                  photo['license'],
                  photo['license_url'],
                  photo['source'],
                  if ((photo['license'] as String? ?? '').isNotEmpty)
                    'Foto consultada directamente en la fuente.',
                ].whereType<String>().where((s) => s.isNotEmpty).join('\n'),
              ),
            ],
          ),
        if ((photo['error'] as String? ?? '').isNotEmpty)
          Text(
            photo['error'],
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (widget.onCover != null || widget.onRemove != null)
          Wrap(
            spacing: 8,
            children: [
              if (widget.onCover != null)
                TextButton.icon(
                  onPressed: () => widget.onCover!(selected),
                  icon: const Icon(Icons.photo_outlined),
                  label: const Text('Usar de portada'),
                ),
              if (widget.onRemove != null)
                TextButton.icon(
                  onPressed: () => widget.onRemove!(selected),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Quitar esta foto'),
                ),
            ],
          ),
      ],
    );
  }
}
