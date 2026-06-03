# FROM python:3.10-slim

# WORKDIR /app

# # تثبيت متطلبات النظام
# RUN apt-get update && apt-get install -y --no-install-recommends \
#     build-essential \
#     && rm -rf /var/lib/apt/lists/*

# # تثبيت المكتبات (نقلنا هذه الخطوة للأعلى لتسريع الـ Build)
# RUN pip install --no-cache-dir flask werkzeug Pillow gunicorn
# RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu

# # نسخ كل شيء (باستثناء ما هو في .dockerignore)=
# COPY . .

# # استخدام gunicorn للإنتاج
# CMD gunicorn --bind 0.0.0.0:$PORT --timeout 600 app:app



FROM python:3.12-slim
WORKDIR /app

# تثبيت مكتبات النظام اللازمة لـ OpenCV و PyTorch
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# تثبيت المتطلبات من الملف مباشرة (أسرع وأكثر تنظيماً)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu

# نسخ كود المشروع (بما في ذلك ملفات النموذج .prototxt و .caffemodel)
COPY . .

# استخدام gunicorn للإنتاج
CMD gunicorn --bind 0.0.0.0:$PORT --timeout 600 app:app