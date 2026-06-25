# 🎵 Retro Music Player & AI Separator

Welcome to the **Retro Music Player & AI Separator**! This is a full-stack project that marries a nostalgic, iPod-classic-inspired music player interface with cutting-edge AI technologies for audio separation and transcription.

Whether you want to stream trending tracks, manage your local music library, or isolate the vocals and instruments from your favorite songs, this application has you covered.

---

## 🌟 Key Features

### 📱 The Nostalgic Player (Frontend)
Experience music through a beautifully crafted, retro-style interface built with Flutter.
- **Classic Wheel Navigation**: Scroll through menus and seek tracks using a nostalgic, circular scroll-wheel interface with haptic feedback.
- **Online Streaming**: Integrated with the [Audius API](https://audius.co/) to fetch and stream trending tracks directly from the decentralized network.
- **Local Music Support**: Seamlessly browse and play audio files stored locally on your device.
- **Playlists & Favorites**: Create custom playlists, favorite your top tracks, and manage your library easily.
- **Dark & Light Modes**: Switch between themes for the perfect viewing experience in any lighting.

### 🎛️ The AI Separator (Backend)
Harness the power of machine learning to deconstruct your music.
- **Stem Separation**: Upload any `.mp3`, `.wav`, or `.m4a` file and separate it into different tracks using [Spleeter](https://github.com/deezer/spleeter).
  - *2-Stem*: Vocals / Accompaniment
  - *4-Stem*: Vocals / Drums / Bass / Other
  - *5-Stem*: Vocals / Drums / Bass / Piano / Other
- **Vocal Transcription**: Automatically transcribe isolated vocals to text using [OpenAI's Whisper](https://github.com/openai/whisper).
- **Interactive UI**: Listen to individual stems, adjust their volumes, and read the transcribed lyrics directly within the Flutter app's "Music Separator" screen.

---

## 🛠️ Tech Stack

**Frontend (Mobile/Web/Desktop)**
- [Flutter](https://flutter.dev/) & Dart
- `just_audio` for robust audio playback
- `on_audio_query` for local file querying

**Backend (Audio Processing Server)**
- [Python 3](https://www.python.org/) & [FastAPI](https://fastapi.tiangolo.com/)
- [Spleeter](https://github.com/deezer/spleeter) (Audio Separation)
- [Whisper AI](https://github.com/openai/whisper) (Transcription)
- `ffmpeg` (Audio manipulation)

---

## 📁 Project Structure

```plaintext
music_separator_project/
├── backend_app_folder/          # Python/FastAPI server for AI processing
│   ├── main.py                  # API endpoints and logic
│   ├── requirements.txt         # Backend dependencies
│   ├── uploads/                 # Temporary storage for uploads
│   └── separated/               # Output directory for isolated stems
│
├── flutter_app_folder/          # Flutter UI
│   ├── lib/
│   │   ├── screens/             # UI screens (Home, Separator, Playlists, etc.)
│   │   ├── services/            # Audius API & Backend communication
│   │   └── main.dart            # App entry point
│   └── pubspec.yaml             # Frontend dependencies
│
└── README.md                    # Project documentation
```

---

## 🚀 Getting Started

To run the full stack, you will need to start both the backend server and the frontend application.

### 1. Backend Setup (AI Separator)

You need Python installed. We highly recommend using a virtual environment.

```bash
cd backend_app_folder

# Create and activate virtual environment
python -m venv venv
# On Windows:
venv\Scripts\activate
# On macOS/Linux:
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```
> **Note**: You must have `ffmpeg` installed and added to your system's PATH for Spleeter to work correctly.

Run the FastAPI server:
```bash
uvicorn main:app --reload
```
The server will run on `http://localhost:8000`.

### 2. Frontend Setup (Flutter Player)

Ensure you have [Flutter](https://docs.flutter.dev/get-started/install) installed.

```bash
cd flutter_app_folder

# Fetch dependencies
flutter pub get

# Run the app (ensure you have an emulator running or device connected)
flutter run
```

> **Important for physical devices**: If running the backend on your PC and the frontend on a physical phone, ensure both are on the same Wi-Fi network and update the backend URL in the Flutter app to point to your PC's local IP address (e.g., `192.168.1.x:8000`) instead of `localhost`.

---

## 📡 Backend API Reference

**POST `/upload/`**
Separates the audio file and transcribes lyrics.

| Field | Type   | Description                                     |
|-------|--------|-------------------------------------------------|
| file  | File   | Audio file to process (.mp3, .wav, .m4a)        |
| model | String | Separation model to use: `2stems`, `4stems`, `5stems` |

**Response Example:**
```json
{
  "vocals": "http://localhost:8000/separated/track/vocals.wav",
  "drums": "http://localhost:8000/separated/track/drums.wav",
  "bass": "http://localhost:8000/separated/track/bass.wav",
  "other": "http://localhost:8000/separated/track/other.wav",
  "lyrics": "Transcribed lyrics generated by Whisper..."
}
```

---

## 👨‍💻 Author

**Rohith Rajesh K**  
GitHub: [@rohu069](https://github.com/rohu069)

## 📜 License

This project is open-source and available under the MIT License. Feel free to fork, modify, and use it in your own projects!
