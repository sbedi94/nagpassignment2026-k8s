"""
Gunicorn configuration / entry point.
We call init_pool() inside the application factory so every gunicorn worker
gets its own independent connection pool.
"""
from app import app, init_pool

# Initialise the pool once per worker process
init_pool()

if __name__ == "__main__":
    app.run()
