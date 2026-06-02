// static/script.js

// دالة عرض الملفات
function showFile(type) {
    if (type === 'home') {
        window.location.href = "/"; // العودة للرئيسية
        return;
    }

    // تحديد اسم الملف بناءً على النوع (يجب أن تكون الملفات داخل مجلد static)
    const fileName = (type === 'html') ? 'html.txt' : 'python.txt';
    
    fetch('/static/' + fileName)
        .then(response => {
            if (!response.ok) throw new Error('الملف غير موجود');
            return response.text();
        })
        .then(data => {
            document.getElementById('codeContent').innerText = data;
        })
        .catch(err => {
            document.getElementById('codeContent').innerText = "خطأ في تحميل الملف: " + err.message;
        });
}

// دالة تبديل النموذج (كما هي)
function switchModel(modelName) {
    if (modelName) { window.location.href = "/?selected_model=" + encodeURIComponent(modelName); }
}

// دالة فحص التقدم (باقي الدوال)
function checkProgress() { /* كود الدالة الخاص بك هنا */ }
function checkBackendHeartbeat() { /* كود الدالة الخاص بك هنا */ }

window.onload = function() { checkProgress(); };