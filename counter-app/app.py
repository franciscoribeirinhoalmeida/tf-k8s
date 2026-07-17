from flask import Flask
import redis
import os
import socket

app = Flask(__name__)

redis_client = redis.Redis(
    host=os.getenv("REDIS_HOST", "redis-service"),
    port=6379,
    password=os.getenv("REDIS_PASSWORD"),
    decode_responses=True
)

@app.route("/")
def home():
    visits = redis_client.incr("visits")

    return f"""
    <html>
        <body>
            <h1>Visitor Counter</h1>
            <p>Visits: {visits}</p>
            <p>Hostname: {socket.gethostname()}</p>
        </body>
    </html>
    """

@app.route("/health")
def health():
    return "OK", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)