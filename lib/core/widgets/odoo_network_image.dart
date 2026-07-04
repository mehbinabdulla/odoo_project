import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A drop-in replacement for [Image.network] that uses a certificate-bypassing
/// [HttpClient]. Use this wherever you need to load images from Odoo servers
/// that may have self-signed certificates.
///
/// Falls back to [errorBuilder] when the image cannot be loaded.
class OdooNetworkImage extends StatefulWidget {
  final String url;
  final Map<String, String> headers;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final Widget? loadingWidget;
  final BorderRadius? borderRadius;

  const OdooNetworkImage({
    super.key,
    required this.url,
    this.headers = const {},
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorBuilder,
    this.loadingWidget,
    this.borderRadius,
  });

  @override
  State<OdooNetworkImage> createState() => _OdooNetworkImageState();
}

class _OdooNetworkImageState extends State<OdooNetworkImage> {
  Uint8List? _bytes;
  Object? _error;
  bool _loading = true;

  static final HttpClient _client = HttpClient()
    ..badCertificateCallback = (cert, host, port) => true;

  static final Map<String, Uint8List> _cache = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(OdooNetworkImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || !mapEquals(old.headers, widget.headers)) {
      _load();
    }
  }

  Future<void> _load() async {
    if (_cache.containsKey(widget.url)) {
      if (mounted) {
        setState(() {
          _bytes = _cache[widget.url];
          _loading = false;
          _error = null;
        });
      }
      return;
    }

    if (mounted) setState(() { _loading = true; _error = null; _bytes = null; });
    try {
      final uri = Uri.parse(widget.url);
      final request = await _client.getUrl(uri);
      widget.headers.forEach((k, v) => request.headers.set(k, v));
      final response = await request.close();
      final bytes = await response.fold<List<int>>(
        [],
        (acc, chunk) => acc..addAll(chunk),
      );
      final byteList = Uint8List.fromList(bytes);
      _cache[widget.url] = byteList;
      if (mounted) {
        setState(() {
          _bytes = byteList;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (_loading) {
      child = widget.loadingWidget ??
          SizedBox(
            width: widget.width,
            height: widget.height,
            child: const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
    } else if (_error != null || _bytes == null) {
      child = widget.errorBuilder?.call(context, _error ?? 'No data', null) ??
          SizedBox(width: widget.width, height: widget.height);
    } else {
      child = Image.memory(
        _bytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: widget.errorBuilder,
      );
    }

    if (widget.borderRadius != null) {
      child = ClipRRect(borderRadius: widget.borderRadius!, child: child);
    }

    return child;
  }
}
