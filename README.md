# 🎵 Music Separator & Transcriber

A full-stack project that allows users to upload an audio file and:
- **Separate vocals, drums, bass, piano, and other stems** using [Spleeter](https://github.com/deezer/spleeter)
- **Transcribe vocals to text** using [OpenAI's Whisper](https://github.com/openai/whisper)
- View the separated tracks and lyrics in a **Flutter-based frontend UI**

---

## 📁 Project Structure

```plaintext
music_separator_project/
├── backend_app_folder/          # FastAPI app with audio separation + transcription
│   ├── main.py                  # FastAPI backend logic
│   ├── uploads/                 # Stores uploaded files
│   └── separated/               # Stores output stems
│
├── frontend_flutter_app/        # Flutter frontend UI
│   ├── lib/
│   └── ... (Flutter project files)
│
├── README.md                    # This file
└── requirements.txt             # Python dependencies for backend


🚀 Features
🎧 Upload .mp3, .wav, or .m4a files

🔀 Choose between 2-stem, 4-stem, or 5-stem separation

🎤 Transcribe vocals automatically using Whisper AI

🌐 Clean and interactive Flutter frontend UI

🔄 FastAPI backend with CORS support

🛠️ Tech Stack
Frontend: Flutter (Dart)

Backend: FastAPI (Python)

Audio Separation: Spleeter

Transcription: Whisper

Model Used: Whisper base and Spleeter 2/4/5 stems

📦 Backend Setup (Python + FastAPI)

✅ Step 1: Create a virtual environment

cd backend_app_folder
python -m venv venv
venv\Scripts\activate     # On Windows
# source venv/bin/activate  # On macOS/Linux

✅ Step 2: Install dependencies

pip install -r requirements.txt
Make sure ffmpeg is installed and accessible in your PATH.

✅ Step 3: Run FastAPI server

uvicorn main:app --reload
Access the backend at: http://localhost:8000

📱 Frontend Setup (Flutter)

cd frontend_flutter_app
flutter pub get
flutter run
Make sure you're using a device or emulator.

📡 API Endpoint Info
POST /upload/

Field	Type	Description
file	File	Audio file (.mp3, .wav, .m4a)
model	String	One of: 2stems, 4stems, 5stems

Response JSON:

{
  "vocals": "http://localhost:8000/separated/songname/vocals.wav",
  "drums": "http://localhost:8000/separated/songname/drums.wav",
  ...
  "lyrics": "Transcribed lyrics here"
}

📸 Screenshots.


👨‍💻 Author
Rohith Rajesh K
GitHub: rohu069

📜 License
This project is open-source and available under the MIT License.
