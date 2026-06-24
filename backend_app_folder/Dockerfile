FROM python:3.9

WORKDIR /app

# Install system dependencies for audio processing
RUN apt-get update && apt-get install -y ffmpeg libsndfile1

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Expose port (default 8000 for local, dynamic for cloud)
ENV PORT=8000
EXPOSE $PORT

# Command to run the application dynamically grabbing the PORT environment variable
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port $PORT"]
