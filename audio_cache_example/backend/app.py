from flask import Flask, request, send_file, jsonify
import time
import pyttsx3
import tempfile
import os
import requests
from bs4 import BeautifulSoup

app = Flask(__name__)

@app.route('/')
def index():
    return jsonify({
        "message": "Hello from the backend!",
        "timestamp": time.time()
    })

@app.route('/speak_url')
def speak_url():
    url = request.args.get('url')
    if not url:
        return jsonify({"error": "No URL provided"}), 400

    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/114.0.0.0 Safari/537.36"
        )
    }

    try:
        resp = requests.get(url, headers=headers, timeout=5)
        resp.raise_for_status()
    except Exception as e:
        return jsonify({"error": f"Failed to fetch URL: {e}"}), 500

    soup = BeautifulSoup(resp.text, 'html.parser')
    main = soup.find('main')
    text = main.get_text(strip=True) if main else soup.body.get_text(strip=True)

    if not text or len(text) < 20:
        return jsonify({"error": "Could not extract meaningful content"}), 400

    engine = pyttsx3.init()
    # Try to use a German voice
    for voice in engine.getProperty('voices'):
        if 'de' in voice.id.lower() or 'german' in voice.name.lower():
            engine.setProperty('voice', voice.id)
            break

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".mp3")
    tmp.close() 

    print(text[:1000])

    engine.save_to_file(text[:1000], tmp.name)
    engine.runAndWait()

    response = send_file(tmp.name, mimetype='audio/mpeg')
    os.unlink(tmp.name)
    return response

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)