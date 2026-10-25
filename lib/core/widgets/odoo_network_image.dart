import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A drop-in replacement for [Image.network] that loads images from Odoo
/// servers using a default validating [HttpClient].
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

  static final HttpClient _client = HttpClient();

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
      if (!_looksLikeImage(byteList)) {
        // Odoo sometimes answers image requests with an HTML login/401
        // page (status 200) when the session cookie is dead — feeding
        // that to the codec produces "Invalid image data" noise.
        throw const FormatException(
          'Response is not a decodable image (likely HTML error page)',
        );
      }
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
      child = _buildError(context, _error ?? 'No data', null);
    } else {
      child = Image.memory(
        _bytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (_, Object e, StackTrace? st) => _buildError(context, e, st),
      );
    }

    if (widget.borderRadius != null) {
      child = ClipRRect(borderRadius: widget.borderRadius!, child: child);
    }

    return child;
  }

  /// Falls back to a neutral placeholder when the caller provided no
  /// [OdooNetworkImage.errorBuilder] — prevents "Invalid image data"
  /// noise from crashing print-outs.
  Widget _buildError(BuildContext context, Object error, StackTrace? st) {
    return widget.errorBuilder?.call(context, error, st) ??
        SizedBox(
          width: widget.width,
          height: widget.height,
          child: Icon(
            Icons.broken_image_outlined,
            size: (widget.width ?? 40) * 0.6,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
          ),
        );
  }

  /// PNG / JPEG / GIF / WebP / BMP magic-byte sniffing.
  static bool _looksLikeImage(Uint8List b) {
    if (b.length < 8) return false;
    // PNG
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return true;
    }
    // JPEG
    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return true;
    // GIF
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return true;
    // BMP
    if (b[0] == 0x42 && b[1] == 0x4D) return true;
    // WebP: "RIFF" + 4-size + "WEBP"
    if (b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b.length >= 12 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return true;
    }
    return false;
  }
}
