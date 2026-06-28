import 'dart:async';
import 'dart:io';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class ShareIntentService {
  final _controller = StreamController<List<File>>.broadcast();
  Stream<List<File>> get sharedImages => _controller.stream;
  StreamSubscription? _subscription;

  Future<void> init() async {
    final initial = await ReceiveSharingIntent.instance.getInitialMedia();
    if (initial.isNotEmpty) {
      final files = await _toFiles(initial);
      if (files.isNotEmpty) _controller.add(files);
    }

    _subscription =
        ReceiveSharingIntent.instance.getMediaStream().listen((media) async {
      final files = await _toFiles(media);
      if (files.isNotEmpty) _controller.add(files);
    });
  }

  Future<List<File>> _toFiles(List<SharedMediaFile> media) async {
    final files = <File>[];
    for (final item in media) {
      if (item.type == SharedMediaType.image) {
        files.add(File(item.path));
      }
    }
    return files;
  }

  Future<void> resetInitial() =>
      ReceiveSharingIntent.instance.reset();

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
