FROM python:3.11-slim

WORKDIR /app
COPY app.py .

RUN apt-get update && apt-get install -y \
    espeak \
    libespeak1 \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

RUN pip install flask pyttsx3 beautifulsoup4 requests

CMD ["python", "app.py"]