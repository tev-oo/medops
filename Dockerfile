FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN useradd --create-home appuser \
    && chmod 755 scripts/start-web.sh \
    && chown -R appuser:appuser /app

USER appuser

EXPOSE 8000

CMD ["./scripts/start-web.sh"]
