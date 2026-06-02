import os
import threading
import torch.nn.functional as F
import datetime
import shutil
import torch
import torch.nn as nn
import torchvision.models as models
import torchvision.transforms as transforms
from PIL import Image
from flask import Flask, request, render_template, redirect, jsonify

# إجبار البرنامج على العمل بالمعالج (CPU) لمنع مشاكل الـ DLL واستهلاك الذاكرة
os.environ["CUDA_VISIBLE_DEVICES"] = "-1"

app = Flask(__name__)

DATASET_DIR = 'dataset'
UPLOAD_FOLDER = 'static/uploads'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# قاموس مراقبة حالة التدريب الحالي بالخلفية المطور ليشمل الملف والمجلد الحالي
training_status = {
    "is_training": False,
    "progress": 0,
    "current_epoch": 0,
    "total_epochs": 2,
    "accuracy": 0.0,
    "loss": 0.0,
    "message": "",
    "current_file": "لا يوجد",
    "current_folder": "لا يوجد"
}

def get_transform_predict(img_size=224):
    return transforms.Compose([
        transforms.Resize((img_size, img_size)),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    ])

def get_available_models():
    # تأكد من أن المسار هو المجلد الرئيسي للتطبيق
    current_dir = os.path.dirname(os.path.abspath(__file__))
    files = os.listdir(current_dir)
    # البحث عن ملفات .pth
    model_files = [f for f in files if f.endswith('.pth')]
    return sorted(model_files, reverse=True)

def get_classes():
    train_dir = os.path.join(DATASET_DIR, 'train')
    if os.path.exists(train_dir):
        return sorted(os.listdir(train_dir))
    return []

def get_selected_model_info(model_name):
    if not model_name or not os.path.exists(model_name):
        return {"status": "لم يتم اختيار نموذج مدرب أو الملف غير موجود ❌", "classes": "لا يوجد"}
    
    try:
        state_dict = torch.load(model_name, map_location=torch.device('cpu'))
        out_features = state_dict['classifier.1.weight'].shape[0]
        
        current_classes = get_classes()
        if len(current_classes) >= out_features:
            trained_classes = current_classes[:out_features]
            classes_text = ", ".join(trained_classes)
        else:
            classes_text = f"يحتوي على {out_features} عوائل"
            
        return {
            "status": f"النموذج [{model_name}] جاهز للاستخدام ✅",
            "classes": classes_text
        }
    except Exception as e:
        return {"status": "خطأ في قراءة ملف النموذج ⚠️", "classes": "غير معروف"}

@app.route('/')
def index():
    classes = get_classes()
    return render_template('index.html', training=training_status, classes=classes)

@app.route('/progress')
def progress():
    return jsonify(training_status)

@app.route('/predict', methods=['POST'])
def predict():
    if 'file' not in request.files:
        return redirect('/')
    
    file = request.files['file']
    chosen_model = request.form.get('chosen_model')
    
    if file.filename == '' or not chosen_model:
        return redirect('/')
    
    classes = get_classes()
    
    if file and os.path.exists(chosen_model):
        img_path = os.path.join(UPLOAD_FOLDER, 'last_tested_image.jpg')
        file.save(img_path)
        
        # إضافة weights_only=True لتجنب التحذيرات الأمنية
        state_dict = torch.load(chosen_model, map_location=torch.device('cpu'), weights_only=True)
        num_classes = state_dict['classifier.1.weight'].shape[0]
        
        input_features = state_dict['features.0.0.weight'].shape[2] if 'features.0.0.weight' in state_dict else 224
        
        model = models.mobilenet_v2(weights=None)
        model.classifier[1] = nn.Linear(model.last_channel, num_classes)
        model.load_state_dict(state_dict)
        model.eval()
        
        img = Image.open(img_path).convert('RGB')
        transform_dynamic = get_transform_predict(input_features)
        img_t = transform_dynamic(img).unsqueeze(0)
        
        with torch.no_grad():
            outputs = model(img_t)
            # --- تعديل: حساب الاحتمالات ونسبة التأكد ---
            probs = F.softmax(outputs, dim=1)
            confidence, predicted_idx = torch.max(probs, 1)
            # ----------------------------------------
            
        current_classes = get_classes()
        if predicted_idx.item() < len(current_classes):
            result = current_classes[predicted_idx.item()]
        else:
            result = f"الفئة رقم {predicted_idx.item()}"
            
        # تحويل نسبة التأكد إلى نص مئوي (مثلاً: 98.50%)
        conf_score = f"{confidence.item() * 100:.2f}%"
            
        return render_template('index.html', 
                               prediction=result, 
                               confidence=conf_score, # إرسال نسبة التأكد
                               show_feedback=True,
                               training=training_status,
                               classes=classes)
        
    return redirect('/')

@app.route('/feedback', methods=['POST'])
def feedback():
    feedback_type = request.form.get('feedback_type')
    predicted_class = request.form.get('predicted_class')
    correct_class = request.form.get('correct_class')
    
    source_img = os.path.join(UPLOAD_FOLDER, 'last_tested_image.jpg')
    classes = get_classes()
    
    if not os.path.exists(source_img):
        return render_template('index.html', 
                               feedback_msg="⚠️ لم يتم العثور على الصورة المرفوعة مسبقاً لمزامنتها.", 
                               training=training_status, 
                               classes=classes)

    target_class = predicted_class if feedback_type == 'correct' else correct_class
    
    if target_class:
        target_dir = os.path.join(DATASET_DIR, 'train', target_class)
        os.makedirs(target_dir, exist_ok=True)
        
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        new_img_name = f"learned_{timestamp}.jpg"
        target_path = os.path.join(target_dir, new_img_name)
        
        try:
            shutil.move(source_img, target_path)
            msg = f"✅ شكراً لتغذيتك الراجعة! تم إضافة الصورة بنجاح إلى مجلد [{target_class}]. ستدخل ضمن التدريب القادم للنموذج لتصحيح العقل."
        except Exception as e:
            msg = f"❌ حدث خطأ أثناء محاولة حفظ الصورة في مجلد البيانات: {str(e)}"
    else:
        msg = "⚠️ الرجاء تحديد الفئة الصحيحة أولاً."

    return render_template('index.html', 
                           feedback_msg=msg, 
                           training=training_status, 
                           classes=classes)


# كلاس قراءة البيانات المطور لتسجيل اسم الملف والمجلد برمجياً أثناء التدريب المباشر
class SafeImageFolder(torch.utils.data.Dataset):
    def __init__(self, root, transform=None):
        from torchvision.datasets import ImageFolder
        self.dataset = ImageFolder(root)
        self.transform = transform
        
    def __len__(self):
        return len(self.dataset.imgs)
        
    def __getitem__(self, index):
        global training_status
        if index >= len(self.dataset.imgs):
            index = 0
        path, label = self.dataset.imgs[index]
        
        # استخراج اسم المجلد والملف وتمريرهما لـ UI
        try:
            folder_name = os.path.basename(os.path.dirname(path))
            file_name = os.path.basename(path)
            training_status["current_folder"] = folder_name
            training_status["current_file"] = file_name
        except:
            pass

        try:
            with open(path, 'rb') as f:
                img = Image.open(f)
                img.convert('RGB')
            
            img = Image.open(path).convert('RGB')
            if self.transform:
                img = self.transform(img)
            return img, label
            
        except Exception as e:
            print(f"\n🗑️ [تنبيه تلقائي] حذف صورة تالفة لتطهير التدريب: {path}")
            try:
                if os.path.exists(path):
                    os.remove(path)
            except:
                pass
            del self.dataset.imgs[index]
            return self.__getitem__(index % len(self.dataset.imgs) if len(self.dataset.imgs) > 0 else 0)

def run_training_background(train_dir, classes, user_epochs, user_batch_size, new_model_path, img_size):
    from torch.utils.data import DataLoader
    
    global training_status
    print("\n" + "="*50)
    print(f"🚀 [START] بدء التدريب الفعلي والمصحح ذكياً...")
    print("="*50)

    try:
        train_transform = transforms.Compose([
            transforms.Resize((img_size, img_size)),
            transforms.RandomHorizontalFlip(),
            transforms.RandomRotation(10),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
        ])
        
        train_dataset = SafeImageFolder(train_dir, transform=train_transform)
        train_loader = DataLoader(train_dataset, batch_size=user_batch_size, shuffle=True, num_workers=0)
        
        model = models.mobilenet_v2(weights=models.MobileNet_V2_Weights.DEFAULT)
        
        # إلغاء قفل طبقة التصنيف لتجنب التنبؤ الأعمى بـ Cat
        for param in model.parameters():
            param.requires_grad = False
            
        model.classifier[1] = nn.Linear(model.last_channel, len(classes))
        for param in model.classifier[1].parameters():
            param.requires_grad = True
            
        criterion = nn.CrossEntropyLoss()
        optimizer = torch.optim.Adam(model.classifier.parameters(), lr=0.002)
        
        total_batches = len(train_loader) * user_epochs
        batches_done = 0
        
        model.train()
        for epoch in range(user_epochs):
            training_status["current_epoch"] = epoch + 1
            correct_predictions = 0
            total_samples = 0
            
            for step, batch in enumerate(train_loader):
                if batch is None or len(batch) == 0:
                    continue
                    
                images, labels = batch
                optimizer.zero_grad()
                outputs = model(images)
                loss = criterion(outputs, labels)
                loss.backward()
                optimizer.step()
                
                with torch.no_grad():
                    _, preds = torch.max(outputs, 1)
                    correct_predictions += torch.sum(preds == labels.data).item()
                    total_samples += images.size(0)
                
                batches_done += 1
                
                calc_progress = int((batches_done / total_batches) * 94)
                training_status["progress"] = calc_progress if calc_progress < 94 else 94
                training_status["loss"] = round(loss.item(), 4)
                training_status["accuracy"] = round((correct_predictions / total_samples) * 100, 2)
                training_status["message"] = f"جاري التدريب والتفريق بين المجلدات... الجولة {epoch+1}/{user_epochs}"
                
                print(f"🔹 الدفعة [{step+1}/{len(train_loader)}] | المجلد: {training_status['current_folder']} | الملف: {training_status['current_file']} | الخطأ: {training_status['loss']} | الدقة: {training_status['accuracy']}%")
        
        print("\n💾 [INFO] تم اكتمال تدريب شبكة العصبونات الحيوية! جاري حفظ الملف...")
        training_status["message"] = "جاري الآن تشفير الأوزان وحفظ ملف النموذج بصيغة آمنة... 💾"
        
        cpu_state_dict = {k: v.cpu() for k, v in model.state_dict().items()}
        torch.save(cpu_state_dict, new_model_path)
        
        training_status["progress"] = 100
        training_status["message"] = f"تم بنجاح حفظ نموذج ذكي جديد باسم: {new_model_path} 🎉"
        print(f"✅ [SUCCESS] تم الحفظ!")
        
    except Exception as e:
        print(f"\n❌ [ERROR] حدث خطأ: {str(e)}")
        training_status["message"] = f"خطأ أثناء التدريب: {str(e)}"
        training_status["progress"] = 0
        training_status["is_training"] = False
    finally:
        training_status["is_training"] = False
        print("="*50)

@app.route('/train', methods=['POST'])
def train():
    global training_status
    if training_status["is_training"]:
        return redirect('/')
        
    train_dir = os.path.join(DATASET_DIR, 'train')
    classes = get_classes()
    
    if not os.path.exists(train_dir) or len(classes) == 0:
        return redirect('/')
    
    try:
        user_epochs = int(request.form.get('epochs', 2))
        user_batch_size = int(request.form.get('batch_size', 16))
        img_size = int(request.form.get('img_size', 224))
    except ValueError:
        user_epochs = 2
        user_batch_size = 16
        img_size = 224

    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M")
    suffix = "_fast" if img_size < 200 else ""
    new_model_path = f"model_{timestamp}{suffix}.pth"

    training_status["is_training"] = True
    training_status["progress"] = 0
    training_status["total_epochs"] = user_epochs
    training_status["accuracy"] = 0.0
    training_status["loss"] = 0.0
    training_status["current_file"] = "جاري القراءة..."
    training_status["current_folder"] = "جاري القراءة..."
    training_status["message"] = "بدء تهيئة الملفات بالخلفية..."
    
    thread = threading.Thread(target=run_training_background, args=(train_dir, classes, user_epochs, user_batch_size, new_model_path, img_size))
    thread.start()
    
    return redirect('/')

@app.route('/check_heartbeat', methods=['POST'])
def check_heartbeat():
    global training_status
    if training_status["is_training"]:
        return jsonify({
            "alive": True,
            "status": "نشط وعامل 🟢",
            "message": f"النموذج يتدرب حالياً على مجلد [{training_status['current_folder']}] للملف [{training_status['current_file']}]."
        })
    else:
        return jsonify({
            "alive": False,
            "status": "متوقف أو منتهي ⚪",
            "message": "لا توجد عملية تدريب قائمة حالياً."
        })

@app.route('/reset_training_status', methods=['POST'])
def reset_status():
    global training_status
    training_status["is_training"] = False
    training_status["progress"] = 0
    return jsonify({"status": "reset_done"})

@app.context_processor
def inject_global_model_vars():
    """هذه الدالة تضمن حقن المتغيرات الثلاثة الحساسة تلقائياً في أي روت يقوم بعمل render_template"""
    models_list = get_available_models()
    selected_model = request.args.get('selected_model', models_list[0] if models_list else "")
    model_info = get_selected_model_info(selected_model)
    
    return dict(
        models_list=models_list,
        selected_model=selected_model,
        model_info=model_info
    )

if __name__ == "__main__":
    # يقرأ البورت من السيرفر، وإذا لم يجده (محلياً) يشتغل على 5000
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port)