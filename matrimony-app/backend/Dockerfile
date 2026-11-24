FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app

RUN pip install --no-cache-dir uv
COPY pyproject.toml ./
COPY app ./app
RUN uv pip install --system --no-cache .

COPY alembic.ini ./
COPY alembic ./alembic
COPY scripts ./scripts

RUN useradd --create-home appuser
USER appuser

EXPOSE 8000
# Migrations run on start; fine for a single instance. With several instances, run them
# as a separate release step instead.
CMD ["sh", "-c", "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers"]
