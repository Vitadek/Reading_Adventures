-- Schema for the Reading Adventures app.
-- Postgres runs this automatically on first container start
-- (because it's mounted into /docker-entrypoint-initdb.d/).

CREATE TABLE IF NOT EXISTS books (
    id          SERIAL PRIMARY KEY,
    title       VARCHAR(500) NOT NULL,
    filename    VARCHAR(500) NOT NULL,
    uploaded_at TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS quizzes (
    id              SERIAL PRIMARY KEY,
    book_id         INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    questions_json  JSONB   NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_quizzes_book_id    ON quizzes (book_id);
CREATE INDEX IF NOT EXISTS idx_books_uploaded_at  ON books   (uploaded_at DESC);
CREATE INDEX IF NOT EXISTS idx_quizzes_created_at ON quizzes (created_at DESC);
