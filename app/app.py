import os
import time
import logging
from flask import Flask, jsonify
import psycopg2
from psycopg2 import pool

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Read DB config from environment variables (injected by ConfigMap + Secrets)
DB_HOST     = os.environ.get("DB_HOST", "postgres-service")
DB_PORT     = os.environ.get("DB_PORT", "5432")
DB_NAME     = os.environ.get("DB_NAME", "appdb")
DB_USER     = os.environ.get("DB_USER", "appuser")
DB_PASSWORD = os.environ.get("DB_PASSWORD")  # Injected via Kubernetes Secret

# Connection pool (best practice: reuse connections)
connection_pool = None

def init_pool(retries=10, delay=3):
    """Initialize the PostgreSQL connection pool with retry logic."""
    global connection_pool
    for attempt in range(1, retries + 1):
        try:
            connection_pool = psycopg2.pool.SimpleConnectionPool(
                minconn=1,
                maxconn=10,
                host=DB_HOST,
                port=DB_PORT,
                dbname=DB_NAME,
                user=DB_USER,
                password=DB_PASSWORD,
            )
            logger.info("Database connection pool created successfully.")
            return
        except Exception as e:
            logger.warning(f"Attempt {attempt}/{retries} - DB not ready: {e}")
            if attempt < retries:
                time.sleep(delay)
    raise RuntimeError("Could not connect to the database after multiple attempts.")


@app.route("/", methods=["GET"])
def home():
    return jsonify({"status": "ok", "message": "Book Catalog API is running"}), 200


@app.route("/health", methods=["GET"])
def health():
    """Liveness probe endpoint."""
    return jsonify({"status": "healthy"}), 200


@app.route("/ready", methods=["GET"])
def ready():
    """Readiness probe endpoint - checks DB connectivity."""
    try:
        conn = connection_pool.getconn()
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        cursor.close()
        connection_pool.putconn(conn)
        return jsonify({"status": "ready"}), 200
    except Exception as e:
        logger.error(f"Readiness check failed: {e}")
        return jsonify({"status": "not ready", "error": str(e)}), 503


@app.route("/books", methods=["GET"])
def get_books():
    """Return all books from the database."""
    try:
        conn = connection_pool.getconn()
        cursor = conn.cursor()
        cursor.execute("""
            SELECT id, title, author, genre, published_year, available
            FROM books
            ORDER BY id
        """)
        rows = cursor.fetchall()
        cursor.close()
        connection_pool.putconn(conn)

        books = [
            {
                "id": row[0],
                "title": row[1],
                "author": row[2],
                "genre": row[3],
                "published_year": row[4],
                "available": row[5],
            }
            for row in rows
        ]
        return jsonify({"count": len(books), "books": books}), 200

    except Exception as e:
        logger.error(f"Error fetching books: {e}")
        return jsonify({"error": "Failed to fetch books", "detail": str(e)}), 500


@app.route("/books/<int:book_id>", methods=["GET"])
def get_book(book_id):
    """Return a single book by ID."""
    try:
        conn = connection_pool.getconn()
        cursor = conn.cursor()
        cursor.execute("""
            SELECT id, title, author, genre, published_year, available
            FROM books WHERE id = %s
        """, (book_id,))
        row = cursor.fetchone()
        cursor.close()
        connection_pool.putconn(conn)

        if row is None:
            return jsonify({"error": "Book not found"}), 404

        book = {
            "id": row[0],
            "title": row[1],
            "author": row[2],
            "genre": row[3],
            "published_year": row[4],
            "available": row[5],
        }
        return jsonify(book), 200

    except Exception as e:
        logger.error(f"Error fetching book {book_id}: {e}")
        return jsonify({"error": "Failed to fetch book", "detail": str(e)}), 500


if __name__ == "__main__":
    init_pool()
    app.run(host="0.0.0.0", port=5000)
