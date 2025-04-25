FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get upgrade -y && apt-get clean

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/
COPY admin/ ./admin/

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
