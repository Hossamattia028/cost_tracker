import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../core/app_strings.dart';
import '../models/account.dart';
import '../services/amount_recognizer.dart';
import '../services/app_provider.dart';

enum RecordMode { image, text }

/// Read-only result of recognizing one image's amount.
class PendingImageItem {
  final File file;
  String? amount; // recognized value (read-only)
  bool extracting;
  bool failed;

  PendingImageItem({
    required this.file,
    this.amount,
    this.extracting = true,
    this.failed = false,
  });
}

class AddRecordScreen extends StatefulWidget {
  final Account? preselectedAccount;
  final List<File>? sharedImages;

  const AddRecordScreen({
    super.key,
    this.preselectedAccount,
    this.sharedImages,
  });

  @override
  State<AddRecordScreen> createState() => _AddRecordScreenState();
}

class _AddRecordScreenState extends State<AddRecordScreen> {
  final _noteCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  final _recognizer = AmountRecognizer();
  final _picker = ImagePicker();

  RecordMode _mode = RecordMode.image;
  String? _selectedAccountId;
  final List<PendingImageItem> _items = [];
  List<String> _textAmounts = [];
  bool _submitting = false;
  bool _extractingText = false;

  @override
  void initState() {
    super.initState();
    _selectedAccountId = widget.preselectedAccount?.id;
    if (widget.sharedImages != null && widget.sharedImages!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _addImages(widget.sharedImages!);
      });
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _textCtrl.dispose();
    _recognizer.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Image mode
  // ---------------------------------------------------------------------------

  Future<void> _addImages(List<File> files) async {
    final newItems =
        files.map((file) => PendingImageItem(file: file)).toList();
    setState(() => _items.addAll(newItems));
    await _recognizeItems(newItems);
  }

  Future<void> _recognizeItems(List<PendingImageItem> items) async {
    if (items.isEmpty) return;
    setState(() {
      for (final item in items) {
        item.extracting = true;
        item.failed = false;
      }
    });
    try {
      final amounts = await _recognizer.amountsFromImages(
        items.map((item) => item.file).toList(),
      );
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < items.length; i++) {
          final item = items[i];
          final amount = i < amounts.length ? amounts[i] : null;
          if (amount == null) {
            item.failed = true;
            item.amount = null;
          } else {
            item.amount = amount;
            item.failed = false;
          }
          item.extracting = false;
        }
      });
    } catch (e) {
      debugPrint('Image amount recognition error: $e');
      if (!mounted) return;
      setState(() {
        for (final item in items) {
          item.failed = true;
          item.amount = null;
          item.extracting = false;
        }
      });
    }
  }

  Future<void> _recognizeItem(PendingImageItem item) =>
      _recognizeItems([item]);

  Future<bool> _ensureCameraPermission() async {
    var status = await Permission.camera.status;
    if (status.isGranted) return true;
    status = await Permission.camera.request();
    if (status.isGranted) return true;

    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(AppStrings.cameraPermissionDenied),
        action: status.isPermanentlyDenied
            ? const SnackBarAction(
                label: AppStrings.openSettings,
                onPressed: openAppSettings,
              )
            : null,
      ),
    );
    return false;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _pickImages(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        if (!await _ensureCameraPermission()) return;
        final xFile = await _picker.pickImage(source: source, imageQuality: 100);
        if (xFile == null) return;
        await _addImages([File(xFile.path)]);
        return;
      }
      final xFiles = await _picker.pickMultiImage();
      if (xFiles.isEmpty) return;
      await _addImages(xFiles.map((f) => File(f.path)).toList());
    } catch (e) {
      _showError('${AppStrings.imagePickFailed}: $e');
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text(AppStrings.takePhoto),
              onTap: () {
                Navigator.pop(context);
                _pickImages(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text(AppStrings.chooseGallery),
              onTap: () {
                Navigator.pop(context);
                _pickImages(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  double get _imageAmountsSum {
    var sum = 0.0;
    for (final i in _items) {
      sum += double.tryParse(i.amount?.replaceAll(',', '') ?? '') ?? 0;
    }
    return sum;
  }

  // ---------------------------------------------------------------------------
  // Text mode
  // ---------------------------------------------------------------------------

  Future<void> _extractFromText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      _showError(AppStrings.enterTextFirst);
      return;
    }
    setState(() => _extractingText = true);
    try {
      final amounts = await _recognizer.amountsFromText(text);
      if (!mounted) return;
      setState(() => _textAmounts = amounts);
      if (amounts.isEmpty) _showError(AppStrings.noAmountsFound);
    } catch (e) {
      _showError('${AppStrings.extractFailed}: $e');
    } finally {
      if (mounted) setState(() => _extractingText = false);
    }
  }

  void _removeTextAmount(int index) {
    setState(() => _textAmounts = List.of(_textAmounts)..removeAt(index));
  }

  double get _textAmountsSum {
    var sum = 0.0;
    for (final a in _textAmounts) {
      sum += double.tryParse(a.replaceAll(',', '')) ?? 0;
    }
    return sum;
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  bool _validateAccount() {
    if (_selectedAccountId != null) return true;
    _showError(AppStrings.selectAccountFirst);
    return false;
  }

  Future<void> _submit() async {
    if (!_validateAccount()) return;
    if (_mode == RecordMode.image) {
      await _submitImages();
    } else {
      await _submitText();
    }
  }

  Future<void> _submitImages() async {
    if (_items.isEmpty) {
      _showError(AppStrings.addImagesFirst);
      return;
    }
    if (_items.any((i) => i.extracting)) {
      _showError(AppStrings.waitExtraction);
      return;
    }
    if (_items.any((i) => i.failed || i.amount == null)) {
      _showError(AppStrings.fixFailedFirst);
      return;
    }

    final images = <File>[];
    final amounts = <double>[];
    for (final item in _items) {
      final value = double.tryParse(item.amount!.replaceAll(',', ''));
      if (value == null || value <= 0) {
        _showError(AppStrings.fixFailedFirst);
        return;
      }
      images.add(item.file);
      amounts.add(value);
    }

    setState(() => _submitting = true);
    try {
      await context.read<AppProvider>().addRecordsBatch(
            accountId: _selectedAccountId!,
            images: images,
            amounts: amounts,
            note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.recordsAdded)),
        );
        Navigator.pop(context, true);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitText() async {
    if (_textAmounts.isEmpty) {
      _showError(AppStrings.noAmountsFound);
      return;
    }
    final amounts = <double>[];
    for (final a in _textAmounts) {
      final value = double.tryParse(a.replaceAll(',', ''));
      if (value == null || value <= 0) {
        _showError(AppStrings.extractFailed);
        return;
      }
      amounts.add(value);
    }

    final note = _noteCtrl.text.trim();
    setState(() => _submitting = true);
    try {
      await context.read<AppProvider>().addManualRecords(
            accountId: _selectedAccountId!,
            amounts: amounts,
            note: note.isEmpty ? null : note,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.recordsAdded)),
        );
        Navigator.pop(context, true);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AppProvider>().accounts;
    final dropdownValue = accounts.any((a) => a.id == _selectedAccountId)
        ? _selectedAccountId
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.sharedImages != null
              ? AppStrings.sharedImages
              : AppStrings.newRecord,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: dropdownValue,
              decoration: const InputDecoration(
                labelText: AppStrings.selectAccount,
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
              items: accounts
                  .map((a) => DropdownMenuItem(
                        value: a.id,
                        child: Text(a.name),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedAccountId = v),
            ),
            const SizedBox(height: 20),
            if (widget.sharedImages == null) _modeSelector(),
            const SizedBox(height: 16),
            if (_mode == RecordMode.image)
              _imageSection(context)
            else
              _textSection(context),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(AppStrings.confirm),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeSelector() {
    return SegmentedButton<RecordMode>(
      segments: const [
        ButtonSegment(
          value: RecordMode.image,
          icon: Icon(Icons.image_outlined),
          label: Text(AppStrings.modeImage),
        ),
        ButtonSegment(
          value: RecordMode.text,
          icon: Icon(Icons.text_fields),
          label: Text(AppStrings.modeText),
        ),
      ],
      selected: {_mode},
      onSelectionChanged: (s) => setState(() => _mode = s.first),
    );
  }

  Widget _sumCard(ColorScheme cs, double sum, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.summarize_outlined, color: cs.onPrimaryContainer),
          const SizedBox(width: 8),
          Text('${AppStrings.sumLabel} ($count)',
              style: TextStyle(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            sum.toStringAsFixed(2),
            style: TextStyle(
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  // ---- Text mode UI --------------------------------------------------------

  Widget _textSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, _) {
            final maxHeight = MediaQuery.of(context).size.height * 0.45;
            return ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: 200,
                maxHeight: maxHeight < 200 ? 200 : maxHeight,
              ),
              child: TextField(
                controller: _textCtrl,
                expands: true,
                maxLines: null,
                minLines: null,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: AppStrings.recordText,
                  hintText: AppStrings.recordTextMultiHint,
                  alignLabelWithHint: true,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        const Row(
          children: [
            Icon(Icons.auto_awesome, size: 14),
            SizedBox(width: 6),
            Expanded(
              child:
                  Text(AppStrings.aiMultiHint, style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _extractingText ? null : _extractFromText,
          icon: _extractingText
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          label: Text(_extractingText
              ? AppStrings.extractingAmounts
              : AppStrings.extractAmounts),
        ),
        const SizedBox(height: 16),
        if (_textAmounts.isNotEmpty) ...[
          Row(
            children: [
              const Text(AppStrings.detectedAmounts,
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(AppStrings.detectedCount(_textAmounts.length),
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          ...List.generate(
            _textAmounts.length,
            (i) => _readonlyAmountRow(
              cs,
              index: i,
              amount: _textAmounts[i],
              onRemove: () => _removeTextAmount(i),
            ),
          ),
          const SizedBox(height: 8),
          _sumCard(cs, _textAmountsSum, _textAmounts.length),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _noteCtrl,
          decoration: const InputDecoration(
            labelText: AppStrings.noteOptional,
            prefixIcon: Icon(Icons.notes_outlined),
          ),
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _readonlyAmountRow(
    ColorScheme cs, {
    required int index,
    required String amount,
    required VoidCallback onRemove,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cs.surfaceContainerLow,
      child: ListTile(
        leading: CircleAvatar(
          radius: 14,
          backgroundColor: cs.secondaryContainer,
          child: Text('${index + 1}',
              style:
                  TextStyle(fontSize: 12, color: cs.onSecondaryContainer)),
        ),
        title: Text(
          amount,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: cs.primary,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close),
          onPressed: onRemove,
        ),
      ),
    );
  }

  // ---- Image mode UI -------------------------------------------------------

  Widget _imageSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.photo_library_outlined, size: 18),
            const SizedBox(width: 6),
            const Text(AppStrings.uploadImages,
                style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              onPressed: _showImageSourceSheet,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text(AppStrings.uploadImages),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_items.isEmpty)
          GestureDetector(
            onTap: _showImageSourceSheet,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant),
                color: cs.primaryContainer.withValues(alpha: 0.2),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined, size: 40),
                  SizedBox(height: 8),
                  Text(AppStrings.tapToUpload),
                  Text(AppStrings.aiPoweredHint,
                      style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          )
        else ...[
          ...List.generate(_items.length, (i) => _imageItemCard(cs, i)),
          const SizedBox(height: 8),
          _sumCard(cs, _imageAmountsSum, _items.length),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _noteCtrl,
          decoration: const InputDecoration(
            labelText: AppStrings.noteOptional,
            prefixIcon: Icon(Icons.notes_outlined),
          ),
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _imageItemCard(ColorScheme cs, int index) {
    final item = _items[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                item.file,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _imageItemStatus(cs, item)),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => _removeItem(index),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageItemStatus(ColorScheme cs, PendingImageItem item) {
    if (item.extracting) {
      return const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(AppStrings.reading),
        ],
      );
    }
    if (item.failed || item.amount == null) {
      return Row(
        children: [
          Icon(Icons.error_outline, color: cs.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(AppStrings.extractFailed,
                style: TextStyle(color: cs.error)),
          ),
          TextButton.icon(
            onPressed: () => _recognizeItem(item),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text(AppStrings.retry),
          ),
        ],
      );
    }
    return Row(
      children: [
        const Text('${AppStrings.amount}: '),
        Text(
          item.amount!,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: cs.primary,
          ),
        ),
      ],
    );
  }
}
