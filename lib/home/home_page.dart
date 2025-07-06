import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:url_launcher/url_launcher.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  File? _selectedImage;
  String? _predictedClass;
  bool _isLoading = false;
  late Interpreter _interpreter;
  late List<String> _labels;
  final int _inputSize = 224;
  bool _modelReady = false;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  @override
  void dispose() {
    _interpreter.close();
    super.dispose();
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/model.tflite');

      final labelsData = await rootBundle.loadString(
        'assets/models/labels.txt',
      );
      _labels =
          labelsData
              .split('\n')
              .map((label) => label.trim())
              .where((label) => label.isNotEmpty)
              // Add this line to split by space and get the name
              .map((label) => label.substring(label.indexOf(' ') + 1))
              .toList();

      setState(() {
        _modelReady = true;
      });
      print("Model and labels loaded!");
    } catch (e) {
      print("Failed to load model: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load model: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<List<double>> _processImageForInference(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    img.Image? image = img.decodeImage(bytes);

    if (image == null) {
      throw Exception('Failed to decode image');
    }

    // Resize image to required dimensions using the image package
    image = img.copyResize(image, width: _inputSize, height: _inputSize);

    return _imageToByteListFloat32(image);
  }

  Float32List _imageToByteListFloat32(img.Image image) {
    final int size = _inputSize;
    var convertedBytes = Float32List(1 * size * size * 3);
    int pixelIndex = 0;

    for (var i = 0; i < size; i++) {
      for (var j = 0; j < size; j++) {
        final pixel = image.getPixel(j, i);
        final r = img.getRed(pixel);
        final g = img.getGreen(pixel);
        final b = img.getBlue(pixel);

        convertedBytes[pixelIndex++] = (r - 127.5) / 127.5;
        convertedBytes[pixelIndex++] = (g - 127.5) / 127.5;
        convertedBytes[pixelIndex++] = (b - 127.5) / 127.5;
      }
    }
    return convertedBytes;
  }

  Future<void> _predictImage(File image) async {
    setState(() => _isLoading = true);

    try {
      final inputData = await _processImageForInference(image);

      var inputShape = [1, _inputSize, _inputSize, 3];

      var outputShape = _interpreter.getOutputTensor(0).shape;
      var outputType = _interpreter.getOutputTensor(0).type;

      Float32List outputBuffer = Float32List(
        outputShape.reduce((a, b) => a * b),
      );

      print("Loaded labels: $_labels");
      print("Number of labels: ${_labels.length}");

      print("Input shape: $inputShape");
      print("Input data sample: ${inputData.take(10).toList()}");
      print("Input tensor shape: ${_interpreter.getInputTensor(0).shape}");
      print("Input tensor type: ${_interpreter.getInputTensor(0).type}");

      _interpreter.run(
        Float32List.fromList(inputData).buffer,
        outputBuffer.buffer,
      );

      List<double> results = outputBuffer.toList();

      print("Output shape: $outputShape");
      print("Output values: $results");

      double maxScore = 0.0;
      int predictedIndex = 0;

      for (int i = 0; i < results.length; i++) {
        if (results[i] > maxScore) {
          maxScore = results[i];
          predictedIndex = i;
        }
      }

      print("Predicted index: $predictedIndex");
      print("Predicted label: ${_labels[predictedIndex]}");
      print("Max score: $maxScore");

      setState(() {
        _isLoading = false;
        _predictedClass = _labels[predictedIndex];
      });

      _showResultDialog(_predictedClass!, (maxScore * 100).toStringAsFixed(2));
    } catch (e) {
      setState(() => _isLoading = false);
      print('Error during prediction: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error during prediction: $e')));
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
        _predictedClass = null;
      });
      await _predictImage(_selectedImage!);
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImage = null;
      _predictedClass = null;
    });
  }

  // Replace _launchApp with this:
  void _launchPredictedUrl() async {
    String? url;
    if (_predictedClass == 'calculator') {
      url =
          "https://play.google.com/store/apps/details?id=com.google.android.calculator";
    } else if (_predictedClass == 'clock') {
      url =
          "https://play.google.com/store/apps/details?id=com.google.android.deskclock";
    } else if (_predictedClass == 'maps') {
      url =
          "https://play.google.com/store/apps/details?id=com.google.android.apps.maps";
    }
    if (url != null && url.isNotEmpty && await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No valid URL provided for $_predictedClass')),
      );
    }
  }

  void _showResultDialog(String label, String confidence) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text("Prediction Result"),
            content: Text("Predicted App: $label\nConfidence: $confidence%"),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("OK"),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Snap Launch'),
        centerTitle: true,
        elevation: isDarkMode ? 0 : 4,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors:
                isDarkMode
                    ? [
                      Theme.of(context).scaffoldBackgroundColor,
                      Theme.of(
                        context,
                      ).scaffoldBackgroundColor.withOpacity(0.8),
                    ]
                    : [Colors.deepPurple.shade50, Colors.grey.shade200],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: isDarkMode ? 4 : 12,
              shadowColor:
                  isDarkMode
                      ? Colors.black.withOpacity(0.3)
                      : Theme.of(context).primaryColor.withOpacity(0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Upload an Image',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select an image to identify an app.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                    const SizedBox(height: 24),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                      child:
                          _isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : _selectedImage == null
                              ? _buildImagePlaceholder()
                              : _buildImagePreview(),
                    ),
                    const SizedBox(height: 24),
                    _buildButtons(),
                    if (_predictedClass != null && !_isLoading) ...[
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.launch),
                        label: Text('Launch $_predictedClass!'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 30,
                            vertical: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _launchPredictedUrl,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      key: const ValueKey('placeholder'),
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[850] : Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).primaryColor.withOpacity(0.2),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_camera_back_outlined,
            size: 60,
            color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 8),
          Text(
            'No image selected',
            style: TextStyle(
              fontSize: 16,
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return Container(
      key: const ValueKey('image_preview'),
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).primaryColor.withOpacity(0.5),
          width: 3,
        ),
        image: DecorationImage(
          image: FileImage(_selectedImage!),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Select'),
          onPressed: _modelReady ? _pickImage : null,
        ),
        if (_selectedImage != null)
          TextButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: _removeImage,
          ),
      ],
    );
  }
}
