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

# تثبيت كافة مكتبات النظام المطلوبة لـ OpenCV و DeepFace و X11
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libgl1 \
    libglib2.0-0 \
    libx11-6 \
    libxcb1 \
    libxcb-shm0 \
    libxcb-render0 \
    libxcb-render-util0 \
    libxcb-xfixes0 \
    libxcb-shape0 \
    libxcb-randr0 \
    libxcb-image0 \
    libxcb-keysyms1 \
    libxcb-icccm4 \
    libxcb-sync1 \
    libxcb-xinerama0 \
    libxcb-xkb1 \
    libxkbcommon-x11-0 \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir --upgrade pip gunicorn
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

ENV PATH="/usr/local/bin:${PATH}"
COPY . .

CMD ["/usr/local/bin/gunicorn", "--bind", "0.0.0.0:10000", "--timeout", "600", "app:app"]
# c983b35