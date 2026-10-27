import time
from flask import Flask, jsonify, request, Response
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)

REQUESTS = Counter("http_requests_total", "Total HTTP requests", ["method", "path", "status"])
LATENCY = Histogram("http_request_duration_seconds", "Request latency in seconds", ["path"])


@app.before_request
def start_timer():
    request.start_time = time.time()


@app.after_request
def record_metrics(response):
    if request.path not in ("/metrics", "/health"):
        path = request.url_rule.rule if request.url_rule else "unmatched"
        REQUESTS.labels(request.method, path, str(response.status_code)).inc()
        LATENCY.labels(path).observe(time.time() - request.start_time)
    return response


@app.route("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


@app.route("/health")
def health():
    return jsonify({"status": "healthy"})


@app.route("/")
def home():
    return jsonify({"message": "Cloud DevOps Portfolio - Stage 6", "version": "1.0"})


@app.route("/fail")
def fail():
    return jsonify({"error": "deliberate failure for the SLO demo"}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
