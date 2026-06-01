# 1. استخدام نسخة بايثون رسمية وخفيفة ومستقرة
FROM python:3.10-slim

# 2. تعيين مجلد العمل داخل الحاوية
WORKDIR /app

# 3. تثبيت أدوات النظام الأساسية المساعدة إذا لزم الأمر
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# 4. تثبيت مكتبات الذكاء الاصطناعي وسيرفر الفلاسك مباشرة
# تم اختيار نسخ مستقرة ومتوافقة للعمل على المعالج (CPU) لتقليل حجم الحاوية
RUN pip install --no-cache-dir flask werkzeug Pillow
RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu

# 5. نسخ ملفات المشروع الأساسية فقط (المجلدات سيتم تحديدها عبر الهيكل المصفى)
COPY app.py /app/
COPY templates/ /app/templates/
# COPY static /app/static/
# 6. فتح المنفذ (Port) الافتراضي لفلاسك
EXPOSE 5000

# 7. متغير بيئي لإجبار بايثون على إظهار المخرجات والطباعة في الكونسول مباشرة دون تأخير
ENV PYTHONUNBUFFERED=1

# 8. أمر تشغيل السيرفر وتوجيهه ليستقبل الاتصالات من خارج الحاوية
CMD ["python", "app.py", "--host=0.0.0.0"]