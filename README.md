# EdgeLLM Test

EdgeLLM Test is an iOS application that demonstrates on-device Large Language Model (LLM) inference using the Gemma 3 2B model. The app provides a multimodal input interface where users can interact with the LLM running entirely on their device, without requiring an internet connection.

## Features

- **On-Device LLM**: Runs the Gemma 3 2B model locally on iOS devices using MediaPipe.
- **Real-time Chat Interface**: Clean, intuitive UI:
   - history = home screen
   - hold to peek into a thread
   - last convo + new thread in the interaction zone
   - voice top level
   - quick & handy inputs
- **Streaming Responses**: See the AI's response as it's being generated
- **No Internet Required**: All processing happens on-device for privacy and offline use

## Requirements

- iOS 17.0 or later
- Xcode 15.0 or later
- CocoaPods

## Installation

1. Clone the repository
2. Install dependencies using CocoaPods
3. Open the workspace in Xcode:
4. Download the Gemma 2B file from Kaggle. Drop the file into the edgellmtest folder and then update the filename in `LlmInference.swift` to match the downloaded file name.
5. Build and run the project on your iOS device.

## Project Structure

Views

The interface uses SwiftUI. Each screen is a struct in the Views folder. We keep every view short and focused.

ContentView. This is the root. It holds the app wide state through TranslationViewModel. It lists the translation history, the language selector, and the bottom input bar. It pushes other screens with the navigation stack.

BottomInputView. This is the bar at the bottom that accepts text, voice, and camera input. It keeps its own local text state. It sends user actions back to ContentView with closures. That keeps the component pure and testable.

ChatThreadView. This screen shows one chat thread about one translation. It draws a header with the original sentence and the first target line. It shows messages in a lazy stack inside a scroll view. It auto scrolls to the latest message. It calls ChatThreadViewModel to send and stream answers.

ChatThreadViewModel. This object fetches or creates a chat thread record in SwiftData. It sends the user question to Gemma through ChatService. It streams partial answers and updates the last assistant message every fifty milliseconds. It stores all messages for later.

BottomCameraView. This wraps the camera preview layer. It shows the shutter button at the bottom. It uses a mask to round the top corners.

CapturedPhotoView. This view shows the captured photo or a processed version. The user can retake, run text recognition, or ask for object translation.

TextSelectionView. This view runs Vision on the photo. It draws an overlay on each detected text block. The user taps a block to pick it and can then translate the text.

CameraSheet. This is the flow controller for the camera. It switches between preview, captured photo, and text selection views.

Every view stays lean. Heavy work lives in view models or services. That makes the UI easy to read and easy to change. All screens work in dark and light mode. We tested them on iPhone and iPad.

Main logic

TranslationViewModel. This is the brain. It loads the Gemma 3n model on a background thread. It keeps the language picks, the sampling settings, and the current chat. It builds prompts, starts the stream, and writes each finished card to SwiftData. It also tracks load time, token count, and tokens per second.

ChatService. A global actor that keeps one Chat per model. This saves memory and avoids extra warm up.

OnDeviceModel. At launch we copy the task file to the app support folder. We unzip the vision parts next to it. We pass both paths to LlmInference so text and image prompts work offline.

Chat. A thin wrapper on LlmInference.Session. We add text with addQueryChunk. We add one photo with addImageToQuery. We call generateResponseAsync and stream back chunks.

WhisperService. A direct wrapper over the whisper C api. We record a sixteen kilohertz mono wav. After stop we run whisper\_full and get plain text.

Camera and EffectsPipeline. Camera gives photos on an async stream. EffectsPipeline runs Vision to lift the subject, blurs the background, and can cut a sticker with a transparent edge. We send that image to TranslationViewModel for image translation.

TTSManager. Picks a female voice for the target language and speaks the answer through AVSpeechSynthesizer.

DataModel. Owns camera and effects pipeline. It maps each capture to ui state so SwiftUI can react.

Error handling. Every async task checks for cancel. We show clear messages for missing models or mic issues.

## Dependencies

- **MediaPipeTasksGenAI**: Google's MediaPipe framework for on-device AI
- **MediaPipeTasksGenAIC**: C implementation of MediaPipe tasks for GenAI

## Usage

1. Launch the app on your iOS device
2. Wait for the model to load (this may take a few moments on first launch)
3. Type your message in the text field at the bottom
4. press return to send your message
5. Watch as the AI generates a response in real-time

## Development

To modify the model parameters:
- Edit the `Chat` class in `LlmInference.swift` to adjust parameters like temperature, top-k, and top-p
- The default settings are:
  - temperature: 0.9
  - top-k: 40
  - top-p: 0.9
  - max tokens: 1000

## Acknowledgements

- Google's MediaPipe team for the on-device LLM inference capabilities
- The Gemma model team for creating the open-source LLM used in this project
