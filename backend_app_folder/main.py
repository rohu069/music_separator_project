from fastapi import FastAPI, File, UploadFile, BackgroundTasks
from fastapi.responses import FileResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import shutil
import os
import sys
import uuid
import subprocess
import re

ffmpeg_path = r"C:\Users\rodra\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-8.1.1-full_build\bin"
if os.path.exists(ffmpeg_path):
    os.environ["PATH"] = ffmpeg_path + os.pathsep + os.environ.get("PATH", "")
    if hasattr(os, "add_dll_directory"):
        os.add_dll_directory(ffmpeg_path)

app = FastAPI(title="Music Separator API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

UPLOAD_DIR = "uploads"
OUTPUT_DIR = "output"

os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(OUTPUT_DIR, exist_ok=True)

# In-memory dictionary to track task status
# In production, use a database or Redis
tasks = {}

def process_audio(task_id: str, file_path: str):
    tasks[task_id] = {"status": "processing", "progress": 0}
    
    try:
        process = subprocess.Popen(
            [sys.executable, "-m", "demucs.separate", "-n", "htdemucs", "--mp3", "--two-stems", "vocals", "-o", OUTPUT_DIR, file_path],
            stderr=subprocess.PIPE,
            stdout=subprocess.PIPE,
            universal_newlines=True,
            encoding='utf-8',
            errors='replace'
        )
        
        for line in process.stderr:
            match = re.search(r'(\d+)%\|', line)
            if match:
                tasks[task_id]["progress"] = int(match.group(1))
                
        process.wait()
        if process.returncode == 0:
            tasks[task_id] = {"status": "completed", "progress": 100}
        else:
            tasks[task_id] = {"status": "failed", "progress": tasks[task_id].get("progress", 0)}
    except Exception as e:
        tasks[task_id] = {"status": "failed", "progress": 0}

@app.post("/upload")
async def upload_audio(background_tasks: BackgroundTasks, file: UploadFile = File(...)):
    task_id = str(uuid.uuid4())
    file_ext = os.path.splitext(file.filename)[1]
    safe_filename = f"{task_id}{file_ext}"
    file_path = os.path.join(UPLOAD_DIR, safe_filename)
    
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    tasks[task_id] = {"status": "queued", "progress": 0}
    background_tasks.add_task(process_audio, task_id, file_path)
    
    return {"task_id": task_id, "status": "queued", "progress": 0, "filename": safe_filename}

@app.get("/status/{task_id}")
async def get_status(task_id: str):
    task_info = tasks.get(task_id, {"status": "not_found", "progress": 0})
    if isinstance(task_info, str):
        task_info = {"status": task_info, "progress": 0}
    return {"task_id": task_id, "status": task_info["status"], "progress": task_info.get("progress", 0)}

@app.get("/download/{task_id}/{stem}")
async def download_stem(task_id: str, stem: str):
    task_dir = os.path.join(OUTPUT_DIR, "htdemucs", task_id)
    if stem == "vocals":
        stem_path = os.path.join(task_dir, "vocals.mp3")
    elif stem == "accompaniment":
        stem_path = os.path.join(task_dir, "no_vocals.mp3")
    else:
        return JSONResponse(status_code=400, content={"error": "Invalid stem name. Use 'vocals' or 'accompaniment'."})
    
    if not os.path.exists(stem_path):
        return JSONResponse(status_code=404, content={"error": "Stem not found. Processing may not be complete or stem name is invalid."})
        
    return FileResponse(stem_path, media_type="audio/mpeg", filename=f"{stem}.mp3")

@app.get("/")
async def root():
    return {"message": "Music Separator API is running"}
