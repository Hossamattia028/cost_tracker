import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import 'device_id_service.dart';

class UploadedImage {
  final int id;
  final String url;

  const UploadedImage({required this.id, required this.url});

  factory UploadedImage.fromJson(Map<String, dynamic> json) => UploadedImage(
        id: (json['id'] as num).toInt(),
        url: json['url'] as String,
      );
}

UploadedImage? uploadedImageFromResponse(Map<String, dynamic> decoded) {
  final raw = decoded['data'];
  final Map<String, dynamic>? item;
  if (raw is List && raw.isNotEmpty) {
    item = raw.first as Map<String, dynamic>;
  } else if (raw is Map<String, dynamic>) {
    item = raw;
  } else {
    return null;
  }
  return UploadedImage.fromJson(item);
}

class ImageApiService {
  ImageApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// POST https://…/api/images  (multipart field: `image`)
  static final Uri _uploadUri =
      Uri.parse('${AppConstants.imageApiBaseUrl}/images');

  static Uri _imageUri(int id) =>
      Uri.parse('${AppConstants.imageApiBaseUrl}/images/$id');

  Future<Map<String, String>> _headers() async => {
        'Accept': 'application/json',
        'X-Device-Id': await DeviceIdService.getDeviceId(),
        'X-Platform': Platform.isIOS ? 'ios' : 'android',
      };

  Future<UploadedImage> uploadImage(File file) async {
    final request = http.MultipartRequest('POST', _uploadUri);
    request.headers.addAll(await _headers());
    request.files.add(await http.MultipartFile.fromPath('image', file.path));

    final streamed = await _client.send(request);
    final body = await streamed.stream.bytesToString();
    debugPrint('Image upload response: $body');

    if (streamed.statusCode != 201 && streamed.statusCode != 200) {
      throw Exception('Image upload failed (${streamed.statusCode}): $body');
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    if (decoded['status'] != true) {
      throw Exception(
        'Image upload failed: ${decoded['message'] ?? body}',
      );
    }
    final uploaded = uploadedImageFromResponse(decoded);
    if (uploaded == null) throw Exception('Image upload returned no data');
    return uploaded;
  }

  Future<String> getImageUrl(int id) async {
    final response = await _client.get(
      _imageUri(id),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Image fetch failed ($id, ${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['status'] != true) {
      throw Exception(
        'Image fetch failed: ${decoded['message'] ?? response.body}',
      );
    }
    final uploaded = uploadedImageFromResponse(decoded);
    if (uploaded == null || uploaded.url.isEmpty) {
      throw Exception('Image fetch returned no url for id $id');
    }
    return uploaded.url;
  }

  Future<void> deleteImage(int id) async {
    final response = await _client.delete(
      _imageUri(id),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      debugPrint(
        'Image delete failed ($id, ${response.statusCode}): ${response.body}',
      );
    }
  }

  void dispose() => _client.close();
}
