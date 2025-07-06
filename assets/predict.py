import numpy as np
import sys
import os
from tensorflow.keras.preprocessing import image
from tensorflow.keras.applications.mobilenet_v3 import preprocess_input
import tensorflow as tf

import tflite_runtime.interpreter as tflite 

TFLITE_MODEL_PATH = "models/bestModel.tflite"
IMG_SIZE = (224, 224)
CLASS_NAMES = ['calculator', 'clock', 'maps'] 

converter = tf.lite.TFLiteConverter.from_saved_model('path_to_saved_model')
converter.target_spec.supported_ops = [
    tf.lite.OpsSet.TFLITE_BUILTINS,  # enable TensorFlow Lite ops.
    tf.lite.OpsSet.SELECT_TF_OPS     # enable TensorFlow ops.
]
# Optionally, force lower op versions:
converter.experimental_new_converter = False
tflite_model = converter.convert()
with open('bestModel.tflite', 'wb') as f:
    f.write(tflite_model)

def load_and_prepare_image(img_path):
    img = image.load_img(img_path, target_size=IMG_SIZE)
    img_array = image.img_to_array(img)
    img_array = preprocess_input(img_array)
    img_array = np.expand_dims(img_array, axis=0).astype(np.float32)
    return img_array

def get_prediction(img_path):
    if not os.path.exists(img_path):
        print(f"Image not found: {img_path}")
        return

    interpreter = tflite.Interpreter(model_path=TFLITE_MODEL_PATH)
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()
    img_tensor = load_and_prepare_image(img_path)

    interpreter.set_tensor(input_details[0]['index'], img_tensor)
    interpreter.invoke()

    predictions = interpreter.get_tensor(output_details[0]['index'])[0]
    predicted_index = np.argmax(predictions)
    confidence = np.max(predictions)

    print(f"Predicted Class: {CLASS_NAMES[predicted_index]}")
    print(f"Confidence: {confidence:.4f}")
    return CLASS_NAMES[predicted_index]
