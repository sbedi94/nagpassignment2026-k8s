# ── Stage 1: build dependencies ───────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

# Install only what's needed to compile psycopg2-binary
RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Stage 2: lean runtime image ───────────────────────────────────────────────
FROM python:3.12-slim

# Non-root user for security best practice
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application source
COPY app.py wsgi.py ./

# Switch to non-root user
USER appuser

EXPOSE 5000

# Use gunicorn for production; 4 workers suitable for 4-pod deployment
CMD ["gunicorn", "--workers", "4", "--bind", "0.0.0.0:5000", "--timeout", "120", "--access-logfile", "-", "wsgi:app"]
