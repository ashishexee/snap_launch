import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:device_apps/device_apps.dart';
import 'package:image/image.dart' as img;

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
      _interpreter = await Interpreter.fromAsset(
        'assets/models/bestModel.tflite',
      );

      final labelsData = await rootBundle.loadString(
        'assets/models/labels.txt',
      );
      _labels =
          labelsData.split('\n').where((label) => label.isNotEmpty).toList();

      print("Model and labels loaded!");
      print("Loaded labels: $_labels");
      print("Number of labels: ${_labels.length}");
    } catch (e) {
      print("Failed to load model: $e");
    }
  }

  Future<List<double>> _processImageForInference(File imageFile) async {
    // Read the image as bytes and decode
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
    var buffer = Float32List.view(convertedBytes.buffer);
    int pixelIndex = 0;

    for (var i = 0; i < size; i++) {
      for (var j = 0; j < size; j++) {
        final pixel = image.getPixel(j, i);
        num r = pixel.r;
        num g = pixel.g;
        num b = pixel.b;

        buffer[pixelIndex++] = (r - 128) / 128.0;
        buffer[pixelIndex++] = (g - 128) / 128.0;
        buffer[pixelIndex++] = (b - 128) / 128.0;
      }
    }
    return convertedBytes.buffer.asFloat32List();
  }

  Future<void> _predictImage(File image) async {
    setState(() => _isLoading = true);

    try {
      final inputData = await _processImageForInference(image);

      var inputShape = [
        1,
        _inputSize,
        _inputSize,
        3,
      ];

      var outputShape = _interpreter.getOutputTensor(0).shape;
      var outputType = _interpreter.getOutputTensor(0).type;

      Float32List outputBuffer = Float32List(
        outputShape.reduce((a, b) => a * b),
      );

      print("Loaded labels: $_labels");
      print("Number of labels: ${_labels.length}");

      print("Input shape: $inputShape");
      print("Input data sample: ${inputData.take(10).toList()}");

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

  void _launchApp(String className) async {
    // ye bhi ek baar dekh liyo warna isme asa krr sakte hai ki
    // user ko choice dede ki konsa device hai or hum kuch krke pata
    // laga le ki konse device mai app chal rha hai ye dekh lena warna mai krr dunga
    final Map<String, String> packageNames = {
      'calculator': 'com.miui.calculator',
      'clock': 'com.google.android.deskclock',
      'maps': 'com.google.android.apps.maps',
    };
    final packageName = packageNames[className.toLowerCase()];
    if (packageName != null && await DeviceApps.isAppInstalled(packageName)) {
      DeviceApps.openApp(packageName);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('App not found or configured: $className')),
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
                        onPressed: () => _launchApp(_predictedClass!),
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
          onPressed: _pickImage,
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
